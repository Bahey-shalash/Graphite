// Loading and running Obsidian community plugins: `App`, `Plugin`, the module loader that
// gives plugins `require('obsidian')`, the command and ribbon registries, Markdown
// post-processors, and the messages Graphite sends to the runtime.
(function installRuntimePlugins(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Component, Vault, Workspace, MetadataCache, FileManager, Keymap, Notice, MarkdownView, normalizePath } = exportedApi;
    const hostBridge = runtime.hostBridge;

    // MARK: Modules a plugin can require

    /// Node.js and Electron modules. Obsidian mobile has none of them either, so plugins
    /// that need them are desktop-only in Obsidian too.
    const desktopModuleNames = new Set([
        'electron', 'fs', 'fs/promises', 'path', 'os', 'child_process', 'crypto', 'http', 'https', 'net', 'tls', 'dns', 'zlib',
        'stream', 'util', 'url', 'events', 'buffer', 'assert', 'worker_threads', 'readline', 'process', 'module', 'vm', 'querystring',
        'string_decoder', 'timers', 'tty', 'dgram', 'cluster', 'perf_hooks', 'v8', 'original-fs',
    ]);

    /// Why a module is missing, in words a person can act on; null for unknown modules.
    function missingModuleExplanation(moduleName) {
        const baseName = moduleName.replace(/^node:/, '');
        if (desktopModuleNames.has(baseName) || desktopModuleNames.has(baseName.split('/')[0])) {
            return 'It needs “' + baseName + '”, which only Obsidian\'s desktop app provides.';
        }
        if (moduleName.startsWith('@codemirror/') || moduleName.startsWith('@lezer/')) {
            return 'It needs “' + moduleName + '”, a part of CodeMirror that Obsidian does not provide to plugins.';
        }
        return null;
    }

    /// CodeMirror 6 and Lezer, which Obsidian gives plugins. Plugins load them to define
    /// editor extensions; the libraries are real, but Graphite's editor is native, so the
    /// extensions a plugin registers do not run (`registerEditorExtension` says so).
    const codeMirrorModules = globalScope.GraphiteCodeMirrorModules || {};

    class UnsupportedModuleError extends Error {
        constructor(moduleName, explanation) {
            super(explanation);
            this.name = 'UnsupportedModuleError';
            this.moduleName = moduleName;
        }
    }

    /// Obsidian's classes are compiled to ES5 functions, so plugins built for ES5 extend them
    /// with `_super.call(this, …) || this`, which an ES2015 class refuses ("cannot be invoked
    /// without 'new'"). Plugins get each class as a function that, called with `new` or by a
    /// subclass's `super`, constructs the class; called as ES5's `_super.call(this, …)`, it
    /// constructs the class for the subclass that `this` belongs to and returns it, which
    /// `|| this` (TypeScript) and `_possibleConstructorReturn` (Babel) then use as `this`.
    /// Its prototype is the class's own, so `instanceof` answers alike for both.
    const callableClasses = new WeakMap();
    function isClass(value) {
        return typeof value === 'function' && /^class[\s{]/.test(Function.prototype.toString.call(value));
    }
    function callableClass(classValue) {
        let callable = callableClasses.get(classValue);
        if (callable) return callable;
        callable = function constructClassForPlugin(...constructorArguments) {
            if (new.target) return Reflect.construct(classValue, constructorArguments, new.target);
            const subclass = this && typeof this === 'object' && typeof this.constructor === 'function' && this.constructor.prototype instanceof classValue ? this.constructor : classValue;
            return Reflect.construct(classValue, constructorArguments, subclass);
        };
        callable.prototype = classValue.prototype;
        Object.setPrototypeOf(callable, classValue);
        Object.defineProperty(callable, 'name', { value: classValue.name });
        callableClasses.set(classValue, callable);
        return callable;
    }
    const pluginFacingObsidianModule = new Proxy(exportedApi, {
        get(target, key) {
            const value = Reflect.get(target, key);
            return isClass(value) ? callableClass(value) : value;
        },
        getOwnPropertyDescriptor(target, key) {
            const descriptor = Reflect.getOwnPropertyDescriptor(target, key);
            if (descriptor && 'value' in descriptor && isClass(descriptor.value)) {
                // A proxy may report a different value only for a configurable property.
                if (descriptor.configurable) descriptor.value = callableClass(descriptor.value);
            }
            return descriptor;
        },
    });

    /// Turns a plugin's `main.js` into a CommonJS module function. In WebKit the code is
    /// loaded as a script from a blob URL of its own, so the plugin's frames in error stacks
    /// carry an address the runtime maps back to the plugin; elsewhere (the Node tests) it is
    /// evaluated with a `sourceURL` naming the plugin, which V8's stacks show.
    let nextPluginSourceNumber = 1;
    runtime.pluginModuleFactories = {};
    /// Whether this engine's error stacks show the `sourceURL` of evaluated code (V8 does,
    /// JavaScriptCore does not), found once by trying it.
    let stacksShowSourceNames = null;
    function engineStacksShowSourceNames() {
        if (stacksShowSourceNames === null) {
            try {
                const probe = (0, globalScope.eval)('(function sourceNameProbe() { return new Error().stack; })\n//# sourceURL=plugin:graphite-source-name-probe/main.js');
                stacksShowSourceNames = /plugin:graphite-source-name-probe\//.test(String(probe()));
            } catch (error) {
                stacksShowSourceNames = true;
            }
        }
        return stacksShowSourceNames;
    }
    /// How long a plugin's script may take to load from its blob before loading fails.
    const pluginScriptLoadMilliseconds = 20000;
    function evaluatePluginSource(pluginIdentifier, mainSource) {
        const sourceName = '\n})\n//# sourceURL=plugin:' + pluginIdentifier + '/main.js';
        const document = globalScope.document;
        const loadsFromScripts = !engineStacksShowSourceNames() && Boolean(globalScope.Blob && globalScope.URL && globalScope.URL.createObjectURL && document);
        if (!loadsFromScripts) return (0, globalScope.eval)('(function anonymous(require, module, exports) {\n' + mainSource + sourceName);
        const key = pluginIdentifier + '#' + nextPluginSourceNumber;
        nextPluginSourceNumber += 1;
        const wrapped = 'GraphitePluginRuntime.pluginModuleFactories[' + JSON.stringify(key) + '] = (function anonymous(require, module, exports) {\n' + mainSource + sourceName;
        const address = globalScope.URL.createObjectURL(new globalScope.Blob([wrapped], { type: 'text/javascript' }));
        runtime.pluginIdentifiersBySourceAddress.set(address, pluginIdentifier);
        return new Promise((resolve, reject) => {
            let evaluationError = null;
            const noteEvaluationError = (event) => { if (event.filename === address) evaluationError = event.error || new Error(event.message); };
            globalScope.addEventListener('error', noteEvaluationError);
            const script = document.createElement('script');
            let isFinished = false;
            const timeout = globalScope.setTimeout(() => finish(), pluginScriptLoadMilliseconds);
            const finish = () => {
                if (isFinished) return;
                isFinished = true;
                globalScope.clearTimeout(timeout);
                globalScope.removeEventListener('error', noteEvaluationError);
                script.remove();
                globalScope.URL.revokeObjectURL(address);
                const moduleFactory = runtime.pluginModuleFactories[key];
                delete runtime.pluginModuleFactories[key];
                if (typeof moduleFactory === 'function') resolve(moduleFactory);
                else reject(evaluationError || new Error('The plugin\'s main.js could not be read as JavaScript.'));
            };
            script.onload = finish;
            script.onerror = finish;
            script.src = address;
            document.head.appendChild(script);
        });
    }

    /// What a plugin gets for a Node.js or Electron module. Plugins built for desktop and
    /// mobile require them as they load and use them only on desktop (Git loads `path` and
    /// `child_process` and uses isomorphic-git on mobile), so requiring one must not fail.
    /// Anything read from the stand-in is another stand-in; calling or constructing one
    /// reports the module and throws why it is missing, as requiring it used to.
    function desktopModuleStandIn(moduleName, memberPath, pluginIdentifier, explanation) {
        const target = function desktopModuleMember() {};
        const fail = () => {
            runtime.reportUnsupportedFeature('Module “' + moduleName + '”', pluginIdentifier);
            throw new UnsupportedModuleError(moduleName, explanation + (memberPath ? ' (' + memberPath + ')' : ''));
        };
        return new Proxy(target, {
            get(standIn, key) {
                if (typeof key === 'symbol' || key === '__esModule' || key === 'then' || key === 'prototype' || key === 'toJSON') return undefined;
                if (key === 'toString' || key === 'valueOf') return () => '[desktop module ' + moduleName + ']';
                return desktopModuleStandIn(moduleName, memberPath ? memberPath + '.' + key : key, pluginIdentifier, explanation);
            },
            has() { return false; },
            ownKeys() { return ['prototype'].filter((key) => Object.prototype.hasOwnProperty.call(target, key)); },
            getOwnPropertyDescriptor(standIn, key) { return Reflect.getOwnPropertyDescriptor(standIn, key); },
            set() { return true; },
            apply: fail,
            construct: fail,
        });
    }

    function createPluginRequire(pluginIdentifier) {
        return function require(moduleName) {
            if (moduleName === 'obsidian') return pluginFacingObsidianModule;
            if (Object.prototype.hasOwnProperty.call(codeMirrorModules, moduleName)) return codeMirrorModules[moduleName];
            const explanation = missingModuleExplanation(moduleName);
            const baseName = moduleName.replace(/^node:/, '');
            if (desktopModuleNames.has(baseName) || desktopModuleNames.has(baseName.split('/')[0])) {
                return desktopModuleStandIn(baseName, '', pluginIdentifier, explanation);
            }
            runtime.reportUnsupportedFeature('Module “' + moduleName + '”', pluginIdentifier);
            if (explanation) throw new UnsupportedModuleError(moduleName, explanation);
            throw new UnsupportedModuleError(moduleName, 'It requires “' + moduleName + '”, which Obsidian does not provide to plugins.');
        };
    }

    // MARK: Commands

    class CommandRegistry {
        constructor(app) {
            this.app = app;
            this.commands = {};
            this.editorCommands = {};
            this.isNotificationScheduled = false;
        }
        addCommand(command) {
            this.commands[command.id] = command;
            this.scheduleNotification();
        }
        removeCommand(commandIdentifier) {
            delete this.commands[commandIdentifier];
            this.scheduleNotification();
        }
        findCommand(commandIdentifier) { return this.commands[commandIdentifier] || null; }
        listCommands() { return Object.values(this.commands); }
        executeCommandById(commandIdentifier) {
            const command = this.commands[commandIdentifier];
            if (!command) return false;
            return this.executeCommand(command);
        }
        /// Runs `command` if it is available now; false when it is not.
        executeCommand(command) {
            const workspace = this.app.workspace;
            const markdownView = workspace.getActiveViewOfType(MarkdownView);
            const editor = markdownView ? markdownView.editor : null;
            if (command.editorCheckCallback) {
                if (!editor || !command.editorCheckCallback(true, editor, markdownView)) return false;
                command.editorCheckCallback(false, editor, markdownView);
                return true;
            }
            if (command.editorCallback) {
                if (!editor) return false;
                const outcome = command.editorCallback(editor, markdownView);
                if (outcome && outcome.catch) outcome.catch((error) => reportCommandFailure(command, error));
                return true;
            }
            if (command.checkCallback) {
                if (!command.checkCallback(true)) return false;
                command.checkCallback(false);
                return true;
            }
            if (command.callback) {
                const outcome = command.callback();
                if (outcome && outcome.catch) outcome.catch((error) => reportCommandFailure(command, error));
                return true;
            }
            return false;
        }
        scheduleNotification() {
            if (this.isNotificationScheduled) return;
            this.isNotificationScheduled = true;
            Promise.resolve().then(() => {
                this.isNotificationScheduled = false;
                hostBridge.notify('commands.changed', {
                    commands: this.listCommands().map((command) => ({
                        commandIdentifier: command.id,
                        name: command.name,
                        icon: command.icon || null,
                        needsEditor: Boolean(command.editorCallback || command.editorCheckCallback),
                        pluginIdentifier: command.pluginIdentifier || null,
                    })),
                });
            });
        }
    }

    function reportCommandFailure(command, error) {
        console.error(error);
        hostBridge.notify('plugin.failure', { pluginIdentifier: command.pluginIdentifier || null, message: '“' + command.name + '” failed: ' + (error && error.message ? error.message : String(error)) });
    }

    // MARK: Ribbon

    class RibbonRegistry {
        constructor() {
            this.items = [];
            this.nextItemNumber = 1;
        }
        add(pluginIdentifier, icon, title, callback) {
            const element = createDiv({ cls: 'side-dock-ribbon-action clickable-icon', attr: { 'aria-label': title } });
            exportedApi.setIcon(element, icon);
            const item = { ribbonIdentifier: 'ribbon-' + this.nextItemNumber, pluginIdentifier, icon, title, callback, element };
            this.nextItemNumber += 1;
            this.items.push(item);
            element.addEventListener('click', (event) => callback(event));
            this.notify();
            return item;
        }
        remove(item) {
            this.items.remove(item);
            item.element.detach();
            this.notify();
        }
        notify() {
            hostBridge.notify('ribbon.changed', {
                items: this.items.map((item) => ({ ribbonIdentifier: item.ribbonIdentifier, pluginIdentifier: item.pluginIdentifier, icon: item.icon, title: item.title })),
            });
        }
        run(ribbonIdentifier) {
            const item = this.items.find((candidate) => candidate.ribbonIdentifier === ribbonIdentifier);
            if (!item) return false;
            item.callback(new globalScope.MouseEvent('click'));
            return true;
        }
    }

    // MARK: Markdown post-processing

    runtime.markdownPostProcessors = [];
    runtime.codeBlockProcessors = new Map();

    let isCodeBlockLanguageNotificationScheduled = false;
    /// Tells Graphite which code block languages plugins draw, once per turn of changes:
    /// its reading view draws blocks in those languages through their plugin.
    let isPostProcessorNotificationScheduled = false;
    /// Tells Graphite whether plugins change how notes read (`registerMarkdownPostProcessor`):
    /// its reading view then offers each part of a note to them.
    runtime.postProcessorsChanged = function postProcessorsChanged() {
        if (isPostProcessorNotificationScheduled) return;
        isPostProcessorNotificationScheduled = true;
        Promise.resolve().then(() => {
            isPostProcessorNotificationScheduled = false;
            const owners = Array.from(new Set(runtime.markdownPostProcessors.map((registered) => registered.pluginIdentifier).filter(Boolean)));
            hostBridge.notify('postProcessors.changed', { pluginIdentifiers: owners });
        });
    };

    runtime.codeBlockLanguagesChanged = function codeBlockLanguagesChanged() {
        if (isCodeBlockLanguageNotificationScheduled) return;
        isCodeBlockLanguageNotificationScheduled = true;
        Promise.resolve().then(() => {
            isCodeBlockLanguageNotificationScheduled = false;
            const owners = {};
            for (const [language, registered] of runtime.codeBlockProcessors) owners[language] = registered.pluginIdentifier;
            hostBridge.notify('codeBlocks.changed', { languages: Array.from(runtime.codeBlockProcessors.keys()), owners });
        });
    };

    function postProcessorContext(element, sourcePath, component, markdown) {
        const frontmatterInformation = typeof markdown === 'string' ? exportedApi.getFrontMatterInfo(markdown) : null;
        let frontmatter = null;
        if (frontmatterInformation && frontmatterInformation.exists) {
            try { frontmatter = exportedApi.parseYaml(frontmatterInformation.frontmatter); } catch (error) { frontmatter = null; }
        }
        return {
            docId: 'graphite-' + Math.random().toString(36).slice(2),
            sourcePath,
            frontmatter,
            el: element,
            addChild(child) { if (component) component.addChild(child); else child.load(); },
            getSectionInfo() { return null; },
        };
    }

    runtime.runCodeBlockProcessor = async function runCodeBlockProcessor(language, handler, element, context) {
        const codeElements = Array.from(element.querySelectorAll('pre > code.language-' + CSS.escape(language)));
        for (const codeElement of codeElements) {
            const preElement = codeElement.parentElement;
            const blockElement = createDiv({ cls: 'block-language-' + language });
            preElement.replaceWith(blockElement);
            try {
                await handler(codeElement.textContent.replace(/\n$/, ''), blockElement, context);
            } catch (error) {
                console.error(error);
                blockElement.createEl('pre', { cls: 'graphite-plugin-error', text: String(error && error.message ? error.message : error) });
            }
        }
    };

    runtime.runMarkdownPostProcessors = async function runMarkdownPostProcessors(element, sourcePath, component, markdown) {
        const context = postProcessorContext(element, sourcePath, component, markdown);
        for (const [language, registered] of runtime.codeBlockProcessors) await runtime.runCodeBlockProcessor(language, registered.handler, element, context);
        const ordered = runtime.markdownPostProcessors.slice().sort((firstProcessor, secondProcessor) => firstProcessor.sortOrder - secondProcessor.sortOrder);
        for (const registered of ordered) {
            try {
                await registered.postProcessor(element, context);
            } catch (error) {
                console.error(error);
            }
        }
    };

    // MARK: Plugin

    class Plugin extends Component {
        constructor(app, manifest) {
            super();
            this.app = app;
            this.manifest = manifest;
        }

        /// Plugins' `onload` is usually asynchronous, so loading waits for it.
        async load() {
            if (this.isComponentLoaded) return;
            this.isComponentLoaded = true;
            await this.onload();
            for (const child of this.childComponents.slice()) child.load();
        }

        pluginFolderPath() {
            return normalizePath(this.manifest.dir || (this.app.vault.configDir + '/plugins/' + this.manifest.id));
        }

        async loadData() {
            const dataPath = this.pluginFolderPath() + '/data.json';
            if (!(await this.app.vault.adapter.exists(dataPath))) return null;
            const text = await this.app.vault.adapter.read(dataPath);
            if (text.trim() === '') return null;
            return JSON.parse(text);
        }

        async saveData(data) {
            const dataPath = this.pluginFolderPath() + '/data.json';
            await this.app.vault.adapter.write(dataPath, JSON.stringify(data, null, 2));
        }

        addCommand(command) {
            const registry = this.app.commands;
            command.id = this.manifest.id + ':' + command.id;
            command.name = this.manifest.name + ': ' + command.name;
            command.pluginIdentifier = this.manifest.id;
            registry.addCommand(command);
            this.register(() => registry.removeCommand(command.id));
            return command;
        }

        removeCommand(commandIdentifier) {
            this.app.commands.removeCommand(this.manifest.id + ':' + commandIdentifier);
        }

        addRibbonIcon(icon, title, callback) {
            const item = runtime.ribbon.add(this.manifest.id, icon, title, callback);
            this.register(() => runtime.ribbon.remove(item));
            return item.element;
        }

        /// Obsidian mobile does not show its status bar, so the item exists but is not shown.
        addStatusBarItem() {
            const element = this.app.statusBar.containerEl.createDiv({ cls: 'status-bar-item plugin-' + this.manifest.id.replace(/[^A-Za-z0-9_-]/g, '-') });
            this.register(() => element.detach());
            return element;
        }

        addSettingTab(settingTab) {
            const registry = runtime.settingTabsByPlugin;
            const tabs = registry.get(this.manifest.id) || [];
            tabs.push(settingTab);
            registry.set(this.manifest.id, tabs);
            try { settingTab.settingItems = settingTab.getSettingDefinitions() || []; } catch (error) { console.error(error); }
            hostBridge.notify('plugin.settingTabChanged', { pluginIdentifier: this.manifest.id, hasSettingTab: true });
            this.register(() => {
                const remaining = (registry.get(this.manifest.id) || []).filter((tab) => tab !== settingTab);
                if (remaining.length > 0) registry.set(this.manifest.id, remaining); else registry.delete(this.manifest.id);
                if (runtime.pluginSurface.shownSettingTab === settingTab) runtime.pluginSurface.handleClosedByPerson();
                hostBridge.notify('plugin.settingTabChanged', { pluginIdentifier: this.manifest.id, hasSettingTab: remaining.length > 0 });
            });
        }

        registerView(viewType, viewCreator) {
            const workspace = this.app.workspace;
            workspace.viewCreatorsByType.set(viewType, viewCreator);
            for (const leaf of workspace.pluginLeaves.slice()) {
                const waiting = leaf.waitingViewState;
                if (waiting && waiting.viewState.type === viewType) {
                    leaf.setViewState(waiting.viewState, waiting.ephemeralState).catch((error) => console.error('Graphite could not open a plugin view.', error));
                }
            }
            this.register(() => {
                workspace.detachLeavesOfType(viewType);
                workspace.viewCreatorsByType.delete(viewType);
            });
        }

        registerExtensions(extensions) {
            runtime.reportUnsupportedFeature('Opening .' + extensions.join(', .') + ' files in a plugin view', this.manifest.id);
        }

        registerMarkdownPostProcessor(postProcessor, sortOrder) {
            const registered = { postProcessor, sortOrder: sortOrder || 0, pluginIdentifier: this.manifest.id };
            runtime.markdownPostProcessors.push(registered);
            runtime.postProcessorsChanged();
            this.register(() => {
                runtime.markdownPostProcessors = runtime.markdownPostProcessors.filter((candidate) => candidate !== registered);
                runtime.postProcessorsChanged();
            });
            return postProcessor;
        }

        registerMarkdownCodeBlockProcessor(language, handler, sortOrder) {
            const registered = { handler, sortOrder: sortOrder || 0, pluginIdentifier: this.manifest.id };
            runtime.codeBlockProcessors.set(language, registered);
            runtime.codeBlockLanguagesChanged();
            this.register(() => {
                if (runtime.codeBlockProcessors.get(language) !== registered) return;
                runtime.codeBlockProcessors.delete(language);
                runtime.codeBlockLanguagesChanged();
            });
            return handler;
        }

        registerEditorExtension() {
            runtime.reportUnsupportedFeature('CodeMirror editor extensions', this.manifest.id);
        }

        registerEditorSuggest(editorSuggest) {
            editorSuggest.pluginIdentifier = this.manifest.id;
            runtime.editorSuggests.push(editorSuggest);
            runtime.editorListenersChanged();
            this.register(() => {
                const position = runtime.editorSuggests.indexOf(editorSuggest);
                if (position !== -1) runtime.editorSuggests.splice(position, 1);
                runtime.editorListenersChanged();
            });
        }

        registerObsidianProtocolHandler(action, handler) {
            runtime.protocolHandlers.set(action, handler);
            this.register(() => { if (runtime.protocolHandlers.get(action) === handler) runtime.protocolHandlers.delete(action); });
        }

        registerHoverLinkSource() {}

        registerBasesView() {
            runtime.reportUnsupportedFeature('Bases views from plugins', this.manifest.id);
            return false;
        }

        registerCliHandler() {
            runtime.reportUnsupportedFeature('Command-line handlers', this.manifest.id);
        }

        onUserEnable() {}
        onExternalSettingsChange() {}
    }

    // MARK: CodeMirror 5 modes

    /// Obsidian still exposes CodeMirror 5's mode registry as `window.CodeMirror`, for
    /// syntax highlighting of code blocks. Plugins register modes at load; Graphite draws
    /// code natively, so modes are kept but never used.
    const legacyCodeMirror = {
        modes: {},
        mimeModes: {},
        Pass: {},
        defineMode(modeName, modeFactory) {
            this.modes[modeName] = modeFactory;
            runtime.reportUnsupportedFeature('Syntax highlighting modes (CodeMirror 5)');
        },
        defineMIME(mimeType, specification) { this.mimeModes[mimeType] = specification; },
        getMode() { return { token(stream) { if (stream && stream.skipToEnd) stream.skipToEnd(); return null; }, startState() { return {}; } }; },
        overlayMode(baseMode) { return baseMode; },
        startState(mode) { return mode && mode.startState ? mode.startState() : true; },
        copyState(mode, state) { return Object.assign({}, state); },
        innerMode(mode, state) { return { mode, state }; },
        defineSimpleMode(modeName, states) { this.defineMode(modeName, () => states); },
        helpers: {},
        registerHelper(helperType, helperName, helper) {
            const helpers = this.helpers[helperType] || (this.helpers[helperType] = {});
            helpers[helperName] = helper;
        },
        registerGlobalHelper(helperType, helperName, predicate, helper) { this.registerHelper(helperType, helperName, helper); },
        defineExtension() {},
        defineDocExtension() {},
        defineOption() {},
        defineInitHook() {},
        extendMode() {},
        commands: {},
        keyMap: {},
        modeInfo: [],
        findModeByName() { return null; },
        findModeByMIME() { return null; },
        findModeByExtension() { return null; },
        findModeByFileName() { return null; },
        runMode() {},
    };
    if (!globalScope.CodeMirror) globalScope.CodeMirror = legacyCodeMirror;

    runtime.settingTabsByPlugin = new Map();
    runtime.protocolHandlers = new Map();

    // MARK: App

    class PluginManager {
        constructor(app) {
            this.app = app;
            this.plugins = {};
            this.manifests = {};
            this.enabledPlugins = new Set();
            this.styleElementsByPlugin = new Map();
        }
        getPlugin(pluginIdentifier) { return this.plugins[pluginIdentifier] || null; }

        /// Evaluates a plugin's `main.js` as Obsidian does, as a CommonJS module, and loads it.
        async loadPlugin(description) {
            const manifest = description.manifest;
            const pluginIdentifier = manifest.id;
            if (this.plugins[pluginIdentifier]) await this.unloadPlugin(pluginIdentifier);
            this.manifests[pluginIdentifier] = manifest;
            if (description.styles) {
                const styleElement = globalScope.document.createElement('style');
                styleElement.setAttribute('data-graphite-plugin', pluginIdentifier);
                styleElement.textContent = description.styles;
                globalScope.document.head.appendChild(styleElement);
                this.styleElementsByPlugin.set(pluginIdentifier, styleElement);
            }
            try {
                const pluginModule = { exports: {} };
                let moduleFactory = evaluatePluginSource(pluginIdentifier, description.mainSource);
                if (moduleFactory && typeof moduleFactory.then === 'function') moduleFactory = await moduleFactory;
                moduleFactory(createPluginRequire(pluginIdentifier), pluginModule, pluginModule.exports);
                const PluginClass = pluginModule.exports && (pluginModule.exports.default || pluginModule.exports);
                if (typeof PluginClass !== 'function') throw new Error('The plugin\'s main.js does not export a plugin class.');
                const plugin = new PluginClass(this.app, manifest);
                if (!(plugin instanceof Plugin)) throw new Error('The plugin\'s main class does not extend Obsidian\'s Plugin.');
                this.plugins[pluginIdentifier] = plugin;
                this.enabledPlugins.add(pluginIdentifier);
                await plugin.load();
                if (description.isEnabledByPerson && plugin.onUserEnable) plugin.onUserEnable();
                return { isLoaded: true };
            } catch (error) {
                const plugin = this.plugins[pluginIdentifier];
                if (plugin) { try { plugin.unload(); } catch (unloadError) { console.error(unloadError); } }
                delete this.plugins[pluginIdentifier];
                this.enabledPlugins.delete(pluginIdentifier);
                const styleElement = this.styleElementsByPlugin.get(pluginIdentifier);
                if (styleElement) styleElement.remove();
                this.styleElementsByPlugin.delete(pluginIdentifier);
                console.error('Graphite could not load the plugin “' + pluginIdentifier + '”.', error);
                return {
                    isLoaded: false,
                    errorMessage: error && error.message ? error.message : String(error),
                    missingModule: error instanceof UnsupportedModuleError ? error.moduleName : null,
                    stack: error && error.stack ? String(error.stack).slice(0, 4000) : null,
                };
            }
        }

        async unloadPlugin(pluginIdentifier) {
            const plugin = this.plugins[pluginIdentifier];
            if (plugin) {
                try { plugin.unload(); } catch (error) { console.error(error); }
            }
            delete this.plugins[pluginIdentifier];
            this.enabledPlugins.delete(pluginIdentifier);
            const styleElement = this.styleElementsByPlugin.get(pluginIdentifier);
            if (styleElement) styleElement.remove();
            this.styleElementsByPlugin.delete(pluginIdentifier);
        }

        async enablePluginAndSave(pluginIdentifier) {
            await hostBridge.send('plugins.setEnabled', { pluginIdentifier, isEnabled: true });
            return true;
        }
        async disablePluginAndSave(pluginIdentifier) {
            await hostBridge.send('plugins.setEnabled', { pluginIdentifier, isEnabled: false });
            return true;
        }
        async enablePlugin(pluginIdentifier) { return this.enablePluginAndSave(pluginIdentifier); }
        async disablePlugin(pluginIdentifier) { return this.disablePluginAndSave(pluginIdentifier); }
    }

    /// Obsidian's core plugins as plugins look them up (`app.internalPlugins`), with the
    /// settings Graphite shares with Obsidian.
    class InternalPluginRegistry {
        constructor() {
            // `plugins` is Obsidian's own (undocumented) name, which plugins read directly.
            this.plugins = {};
        }
        configure(corePlugins) {
            this.plugins = {};
            for (const corePlugin of corePlugins || []) {
                this.plugins[corePlugin.identifier] = { enabled: corePlugin.isEnabled, instance: { id: corePlugin.identifier, options: corePlugin.options || {} } };
            }
        }
        getPluginById(pluginIdentifier) { return this.plugins[pluginIdentifier] || null; }
        getEnabledPluginById(pluginIdentifier) {
            const plugin = this.plugins[pluginIdentifier];
            return plugin && plugin.enabled ? plugin.instance : null;
        }
        getEnabledPlugins() {
            return Object.values(this.plugins).filter((plugin) => plugin.enabled).map((plugin) => plugin.instance);
        }
    }

    /// Obsidian's property types (`app.metadataTypeManager`, undocumented): the vault's
    /// `.obsidian/types.json`, which Graphite's Properties view reads and writes too.
    class MetadataTypeManager {
        constructor(app) {
            this.app = app;
            this.types = {};
            this.unsavedTypes = {};
            this.isSaveScheduled = false;
            this.typesSave = Promise.resolve();
        }
        typesPath() { return normalizePath(this.app.vault.configDir + '/types.json'); }
        async loadTypes() {
            try {
                if (!(await this.app.vault.adapter.exists(this.typesPath()))) return;
                const configuration = JSON.parse(await this.app.vault.adapter.read(this.typesPath()));
                this.types = configuration && typeof configuration.types === 'object' && configuration.types ? configuration.types : {};
            } catch (error) {
                console.warn('Graphite could not read the vault\'s property types for plugins.', error);
            }
        }
        getAllProperties() {
            const properties = this.app.metadataCache.getAllPropertyInfos();
            for (const name of Object.keys(this.types)) {
                const key = name.toLowerCase();
                properties[key] = Object.assign({ name, occurrences: 0 }, properties[key] || {}, { type: this.types[name] });
            }
            return properties;
        }
        getPropertyInfo(name) { return this.getAllProperties()[String(name).toLowerCase()] || null; }
        getAssignedType(name) {
            const assignedName = Object.keys(this.types).find((candidate) => candidate.toLowerCase() === String(name).toLowerCase());
            return assignedName ? this.types[assignedName] : null;
        }
        getTypeInfo(name) {
            const assigned = this.getAssignedType(name);
            const inferred = this.getPropertyInfo(name);
            return { expected: { type: assigned || (inferred ? inferred.type : 'text') }, inferred: { type: inferred ? inferred.type : 'text' } };
        }
        /// Assigns a type as Obsidian's Properties view does: at once in memory, then saved,
        /// keeping the rest of the file. Plugins set several types without waiting (Tasks sets
        /// 22 as it loads), so the types set meanwhile are written together, in one save.
        setType(name, type) {
            this.types[name] = type;
            this.unsavedTypes[name] = type;
            if (!this.isSaveScheduled) {
                this.isSaveScheduled = true;
                this.typesSave = this.typesSave.catch(() => {}).then(() => this.saveUnsavedTypes());
            }
            return this.typesSave;
        }
        async saveUnsavedTypes() {
            this.isSaveScheduled = false;
            const unsavedTypes = this.unsavedTypes;
            this.unsavedTypes = {};
            const merge = (existingText) => {
                const configuration = existingText.trim() ? JSON.parse(existingText) : {};
                const types = configuration.types && typeof configuration.types === 'object' ? configuration.types : {};
                if (Object.keys(unsavedTypes).every((name) => types[name] === unsavedTypes[name])) return existingText;
                Object.assign(types, unsavedTypes);
                configuration.types = types;
                this.types = Object.assign({}, types, this.unsavedTypes);
                return JSON.stringify(configuration, null, 2);
            };
            try {
                await this.app.vault.adapter.process(this.typesPath(), merge);
            } catch (error) {
                if (await this.app.vault.adapter.exists(this.typesPath())) throw error;
                await this.app.vault.adapter.write(this.typesPath(), merge(''));
            }
        }
        on() { return { events: new exportedApi.Events(), name: '', callback() {} }; }
        offref() {}
    }

    /// Obsidian's registry of embedded views (`app.embedRegistry`, undocumented). Plugins use
    /// it to borrow Obsidian's own CodeMirror note editor, which Graphite does not have.
    function makeEmbedRegistry() {
        const embedByExtension = new Proxy({}, {
            get(target, extension) {
                if (typeof extension !== 'string') return undefined;
                runtime.unsupported('Obsidian\'s embedded “.' + extension + '” views (embedRegistry)', 'Graphite\'s notes are edited natively, without Obsidian\'s CodeMirror note editor.');
                return undefined;
            },
        });
        return {
            embedByExtension,
            registerExtension() { runtime.reportUnsupportedFeature('Embedded views for file types (embedRegistry)'); },
            registerExtensions() { runtime.reportUnsupportedFeature('Embedded views for file types (embedRegistry)'); },
            unregisterExtension() {},
            unregisterExtensions() {},
            isExtensionRegistered() { return false; },
        };
    }

    /// Obsidian's registry of view types (undocumented), which plugins read to find a view's
    /// creator or the type that opens a file extension. Its `viewByType` is the workspace's
    /// own list, so what plugins register through `registerView` appears in it.
    function makeViewRegistry(workspace) {
        const viewByType = new Proxy({}, {
            get(target, viewType) {
                if (typeof viewType === 'string' && workspace.viewCreatorsByType.has(viewType)) return workspace.viewCreatorsByType.get(viewType);
                return Reflect.get(target, viewType);
            },
            set(target, viewType, viewCreator) { workspace.viewCreatorsByType.set(viewType, viewCreator); return true; },
            deleteProperty(target, viewType) { workspace.viewCreatorsByType.delete(viewType); return true; },
            has(target, viewType) { return workspace.viewCreatorsByType.has(viewType); },
            ownKeys() { return Array.from(workspace.viewCreatorsByType.keys()); },
            getOwnPropertyDescriptor(target, viewType) {
                return workspace.viewCreatorsByType.has(viewType) ? { value: workspace.viewCreatorsByType.get(viewType), writable: true, enumerable: true, configurable: true } : undefined;
            },
        });
        const registry = new exportedApi.Events();
        Object.assign(registry, {
            viewByType,
            typeByExtension: {},
            registerView(viewType, viewCreator) { workspace.viewCreatorsByType.set(viewType, viewCreator); registry.trigger('view-registered', viewType); },
            unregisterView(viewType) { workspace.viewCreatorsByType.delete(viewType); registry.trigger('view-unregistered', viewType); },
            getViewCreatorByType(viewType) { return workspace.viewCreatorsByType.get(viewType); },
            isExtensionRegistered(extension) { return Object.prototype.hasOwnProperty.call(registry.typeByExtension, extension); },
            getTypeByExtension(extension) { return registry.typeByExtension[extension]; },
            registerExtensions() { runtime.reportUnsupportedFeature('Opening files in a plugin view'); },
            unregisterExtensions() {},
        });
        return registry;
    }

    class App {
        constructor() {
            this.keymap = new Keymap();
            this.scope = this.keymap.getRootScope();
            this.vault = new Vault();
            this.workspace = new Workspace(this);
            this.metadataCache = new MetadataCache(this);
            this.fileManager = new FileManager(this);
            this.commands = new CommandRegistry(this);
            this.plugins = new PluginManager(this);
            this.internalPlugins = new InternalPluginRegistry();
            this.secretStorage = new exportedApi.SecretStorage();
            this.metadataTypeManager = new MetadataTypeManager(this);
            this.embedRegistry = makeEmbedRegistry();
            this.viewRegistry = makeViewRegistry(this.workspace);
            // Obsidian's status bar, which its mobile app keeps hidden. Plugins that reach for it
            // (Commander adds its buttons there) get an element that is never shown.
            this.statusBar = { containerEl: createDiv({ cls: 'status-bar' }) };
            // Obsidian's record of folded headings per note (undocumented). Plugins that copy a
            // template's folds into a new note (Calendar, through the daily notes helper) call
            // it; Graphite keeps folds itself, so there are none to copy and nothing is kept.
            this.foldManager = { load() { return null; }, save() {} };
            // Obsidian's hotkey registry (undocumented). Graphite's keyboard shortcuts are its
            // own, so plugins that read the hotkeys set for their commands (Editing Toolbar
            // shows them beside its buttons) find none, and what they set is not used.
            this.hotkeyManager = {
                customKeys: {},
                defaultKeys: {},
                getHotkeys(commandIdentifier) { return this.customKeys[commandIdentifier] || []; },
                getDefaultHotkeys(commandIdentifier) { return this.defaultKeys[commandIdentifier] || []; },
                setHotkeys(commandIdentifier, hotkeys) { this.customKeys[commandIdentifier] = hotkeys; },
                removeHotkeys(commandIdentifier) { delete this.customKeys[commandIdentifier]; },
                addDefaultHotkeys(commandIdentifier, hotkeys) { this.defaultKeys[commandIdentifier] = hotkeys; },
                removeDefaultHotkeys(commandIdentifier) { delete this.defaultKeys[commandIdentifier]; },
                printHotkeyForCommand() { return ''; },
                save() {},
                load() {},
                bake() {},
            };
            this.lastEvent = null;
            this.isMobile = true;
            this.appId = '';
            this.setting = {
                open: () => hostBridge.notify('settings.open', { pluginIdentifier: null }),
                openTabById: (tabIdentifier) => hostBridge.notify('settings.open', { pluginIdentifier: tabIdentifier }),
                close: () => runtime.pluginSurface.handleClosedByPerson(),
                closeActiveTab: () => runtime.pluginSurface.handleClosedByPerson(),
                // Obsidian's lists of setting tabs (undocumented): Graphite's own settings are
                // native, so only the plugins' tabs are listed (Smart Connections finds its own).
                get pluginTabs() { return Array.from(runtime.settingTabsByPlugin.values()).flat(); },
                settingTabs: [],
            };
        }
        loadLocalStorage(key) {
            try {
                const stored = globalScope.localStorage.getItem(this.appId + '-' + key);
                return stored === null ? null : JSON.parse(stored);
            } catch (error) {
                return null;
            }
        }
        saveLocalStorage(key, data) {
            try {
                if (data === null || data === undefined) globalScope.localStorage.removeItem(this.appId + '-' + key);
                else globalScope.localStorage.setItem(this.appId + '-' + key, JSON.stringify(data));
            } catch (error) {
                console.warn('Graphite could not keep a plugin value on this device.', error);
            }
        }
        isDarkMode() { return globalScope.document.body.hasClass('theme-dark'); }
        /// Obsidian's base theme (undocumented): `obsidian` is dark, `moonstone` light.
        getTheme() { return this.isDarkMode() ? 'obsidian' : 'moonstone'; }
        /// Graphite's appearance follows the system and its own settings, so a plugin cannot
        /// switch it; the request is reported (System Dark Mode does what Graphite already does).
        setTheme(theme) {
            if (theme === this.getTheme()) return;
            runtime.reportUnsupportedFeature('Changing Graphite\'s appearance (light or dark)');
        }
    }

    runtime.ribbon = new RibbonRegistry();

    /// Obsidian's Vim mode adapter, a global its plugins add Vim commands to (Linter sets
    /// `CodeMirrorAdapter.commands.save` as it loads). Graphite's editor has no Vim mode, so
    /// what plugins add here is kept and never run.
    if (!globalScope.CodeMirrorAdapter) {
        const keptVimDefinitions = () => {};
        globalScope.CodeMirrorAdapter = {
            commands: {},
            Vim: {
                defineEx: keptVimDefinitions, defineAction: keptVimDefinitions, defineMotion: keptVimDefinitions, defineOperator: keptVimDefinitions,
                defineOption: keptVimDefinitions, defineRegister: keptVimDefinitions, map: keptVimDefinitions, noremap: keptVimDefinitions,
                unmap: keptVimDefinitions, mapclear: keptVimDefinitions, mapCommand: keptVimDefinitions, setOption: keptVimDefinitions,
                getOption: () => undefined, handleEx: keptVimDefinitions, handleKey: keptVimDefinitions, exitInsertMode: keptVimDefinitions,
            },
        };
    }

    // MARK: Typing in a note

    /// The plugins' typing suggestions, in the order Obsidian asks them.
    runtime.editorSuggests = [];
    /// How long a plugin may take to find its suggestions before the list stays closed.
    const suggestionWaitMilliseconds = 3000;

    let isEditorListenerNotificationScheduled = false;
    /// Tells Graphite whether plugins want to hear typing (`editor-change`) or suggest while
    /// typing (`EditorSuggest`), so its editor sends the note only when one does.
    runtime.editorListenersChanged = function editorListenersChanged() {
        if (isEditorListenerNotificationScheduled) return;
        isEditorListenerNotificationScheduled = true;
        Promise.resolve().then(() => {
            isEditorListenerNotificationScheduled = false;
            const workspace = runtime.app && runtime.app.workspace;
            hostBridge.notify('editor.listenersChanged', {
                hasEditorChangeListeners: Boolean(workspace) && workspace.listenerCount('editor-change') > 0,
                hasEditorSuggestions: runtime.editorSuggests.length > 0,
            });
        });
    };

    /// The suggestions shown last, kept until one is chosen or newer ones replace them.
    let shownSuggestion = null;

    /// What a suggestion item reads as, from what the plugin drew: Obsidian's title and
    /// note when it used them, its text otherwise.
    function suggestionText(element) {
        const titleElement = element.querySelector('.suggestion-title');
        const noteElement = element.querySelector('.suggestion-note');
        const title = (titleElement || element).textContent.replace(/\s+/g, ' ').trim();
        const subtitle = noteElement && titleElement ? noteElement.textContent.replace(/\s+/g, ' ').trim() : '';
        return { title, subtitle: subtitle || null };
    }

    /// Asks the registered suggests at the cursor, as Obsidian does after each change: the
    /// first whose `onTrigger` answers is shown, with at most its `limit` items.
    async function findSuggestions(editor, view, requestIdentifier) {
        const cursor = editor.getCursor();
        // The suggest open before closes when another one, or none, answers now, as
        // Obsidian closes it: Natural Language Dates forgets where its `@` was.
        const previouslyOpen = runtime.editorSuggests.find((editorSuggest) => editorSuggest.isOpen) || null;
        const closePreviouslyOpen = (except) => { if (previouslyOpen && previouslyOpen !== except) previouslyOpen.close(); };
        for (const editorSuggest of runtime.editorSuggests.slice()) {
            let trigger = null;
            try {
                trigger = editorSuggest.onTrigger(cursor, editor, view.file);
            } catch (error) {
                console.error(error);
                hostBridge.notify('plugin.failure', { pluginIdentifier: editorSuggest.pluginIdentifier || null, message: 'Suggestions failed: ' + (error && error.message ? error.message : String(error)) });
                continue;
            }
            if (!trigger) continue;
            closePreviouslyOpen(editorSuggest);
            const context = { editor, file: view.file, start: trigger.start, end: trigger.end, query: trigger.query };
            editorSuggest.context = context;
            let values = [];
            try {
                values = await Promise.race([
                    Promise.resolve(editorSuggest.getSuggestions(context)),
                    new Promise((resolve) => globalScope.setTimeout(() => resolve(null), suggestionWaitMilliseconds)),
                ]) || [];
            } catch (error) {
                console.error(error);
                values = [];
            }
            values = Array.from(values).slice(0, editorSuggest.limit || 100);
            if (values.length === 0) {
                editorSuggest.close();
                return null;
            }
            editorSuggest.open();
            const items = values.map((value, position) => {
                const element = createDiv({ cls: 'suggestion-item' });
                try { editorSuggest.renderSuggestion(value, element); } catch (error) { console.error(error); element.setText(String(value)); }
                return Object.assign({ position }, suggestionText(element));
            });
            shownSuggestion = { requestIdentifier, editorSuggest, values, context };
            return { requestIdentifier, pluginIdentifier: editorSuggest.pluginIdentifier || null, items };
        }
        closePreviouslyOpen(null);
        shownSuggestion = null;
        return null;
    }

    // MARK: Context menus

    let isMenuListenerNotificationScheduled = false;
    /// Tells Graphite whether plugins add items to file and editor menus, so its menus offer
    /// plugins' actions only when there can be some.
    runtime.menuListenersChanged = function menuListenersChanged() {
        if (isMenuListenerNotificationScheduled) return;
        isMenuListenerNotificationScheduled = true;
        Promise.resolve().then(() => {
            isMenuListenerNotificationScheduled = false;
            const workspace = runtime.app && runtime.app.workspace;
            if (!workspace) return;
            hostBridge.notify('menus.changed', {
                hasFileMenuItems: workspace.listenerCount('file-menu') + workspace.listenerCount('files-menu') > 0,
                hasEditorMenuItems: workspace.listenerCount('editor-menu') > 0,
            });
        });
    };

    /// Menus Graphite shows with plugins' items, until an item is chosen or the menu closes.
    const openMenus = new Map();

    /// The items plugins added to `menu`, as Graphite shows them; the menu is kept until
    /// Graphite says which was chosen.
    function offerMenu(menuIdentifier, menu) {
        const choices = menu.flattenedItems().filter((entry) => !entry.isSeparator);
        if (choices.length === 0) {
            menu.hide();
            return { items: [] };
        }
        openMenus.set(menuIdentifier, { menu, choices });
        return {
            items: choices.map((entry, position) => ({
                position, title: entry.title, icon: entry.icon || null, isChecked: entry.isChecked, isDisabled: entry.isDisabled, isWarning: entry.isWarning, section: entry.section || '',
            })),
        };
    }

    function closeMenu(menuIdentifier) {
        const openMenu = openMenus.get(menuIdentifier);
        if (!openMenu) return null;
        openMenus.delete(menuIdentifier);
        return openMenu;
    }

    // MARK: Messages from Graphite

    function applyTheme(appearance) {
        const body = globalScope.document.body;
        if (!body) return;
        const isDark = appearance === 'dark';
        body.toggleClass('theme-dark', isDark);
        body.toggleClass('theme-light', !isDark);
        if (runtime.app) runtime.app.workspace.trigger('css-change');
    }

    const messageHandlers = {
        async 'runtime.start'(message) {
            const app = new App();
            runtime.app = app;
            globalScope.app = app;
            app.appId = message.vault.identifier;
            app.vault.vaultName = message.vault.name;
            app.vault.configDir = message.vault.configurationDirectory || '.obsidian';
            app.vault.configuration = message.vault.configuration || {};
            app.internalPlugins.configure(message.vault.corePlugins);
            app.secretStorage.adoptSecrets(message.vault.secrets);
            if (message.compatibleApiVersion) runtime.compatibleApiVersion = message.compatibleApiVersion;
            app.workspace.lastOpenFiles = message.recentFiles || [];
            runtime.configurePlatform(message.device || {});
            applyTheme(message.appearance);
            await app.vault.loadFileTree();
            await app.metadataTypeManager.loadTypes();
            app.metadataCache.observeVault();
            app.metadataCache.startInitialRead();
            return { fileCount: app.vault.getAllLoadedFiles().length };
        },
        async 'runtime.stop'() {
            const app = runtime.app;
            if (!app) return {};
            app.workspace.trigger('quit', { add() {}, cancel() {} });
            if (runtime.releaseAllCodeBlocks) runtime.releaseAllCodeBlocks();
            for (const pluginIdentifier of Object.keys(app.plugins.plugins)) await app.plugins.unloadPlugin(pluginIdentifier);
            runtime.pluginSurface.handleClosedByPerson();
            return {};
        },
        async 'plugin.load'(message) {
            return runtime.app.plugins.loadPlugin(message);
        },
        async 'plugin.unload'(message) {
            await runtime.app.plugins.unloadPlugin(message.pluginIdentifier);
            return {};
        },
        async 'plugins.layoutReady'() {
            runtime.app.workspace.markLayoutReady();
            return {};
        },
        async 'vault.configuration'(message) {
            runtime.app.vault.configuration = message.configuration || {};
            if (message.corePlugins) runtime.app.internalPlugins.configure(message.corePlugins);
            return {};
        },
        async 'appearance.changed'(message) {
            applyTheme(message.appearance);
            return {};
        },
        async 'workspace.activeDocument'(message) {
            runtime.app.workspace.setActiveDocument(message.activeDocument || null);
            if (message.recentFiles) runtime.app.workspace.lastOpenFiles = message.recentFiles;
            return {};
        },
        async 'vault.changes'(message) {
            const app = runtime.app;
            for (const move of message.moves || []) app.vault.reconcileMovedPath(normalizePath(move.path), normalizePath(move.destinationPath));
            await app.vault.reconcileChangedPaths(message.changes || []);
            notifyPluginsOfSettingsChanges(message.changes || []);
            return {};
        },
        /// Runs a command for Graphite's command palette or a keyboard shortcut.
        async 'command.run'(message) {
            const app = runtime.app;
            if (message.activeDocument) app.workspace.setActiveDocument(message.activeDocument);
            const command = app.commands.findCommand(message.commandIdentifier);
            if (!command) return { outcome: 'missing' };
            try {
                return { outcome: app.commands.executeCommand(command) ? 'ran' : 'unavailable' };
            } catch (error) {
                reportCommandFailure(command, error);
                return { outcome: 'failed', message: error && error.message ? error.message : String(error) };
            }
        },
        async 'ribbon.run'(message) {
            try {
                return { outcome: runtime.ribbon.run(message.ribbonIdentifier) ? 'ran' : 'missing' };
            } catch (error) {
                console.error(error);
                return { outcome: 'failed', message: error && error.message ? error.message : String(error) };
            }
        },
        async 'settings.show'(message) {
            const tabs = runtime.settingTabsByPlugin.get(message.pluginIdentifier) || [];
            if (tabs.length === 0) return { hasSettingTab: false };
            const manifest = runtime.app.plugins.manifests[message.pluginIdentifier];
            try {
                runtime.pluginSurface.showSettingTab(tabs[0], manifest ? manifest.name : message.pluginIdentifier);
            } catch (error) {
                console.error(error);
                return { hasSettingTab: true, errorMessage: error && error.message ? error.message : String(error) };
            }
            return { hasSettingTab: true };
        },
        async 'view.show'(message) {
            const leaf = runtime.app.workspace.getLeafById(message.leafIdentifier);
            if (!leaf) return { isShown: false };
            await runtime.app.workspace.revealLeaf(leaf);
            return { isShown: true };
        },
        async 'surface.closed'() {
            runtime.pluginSurface.handleClosedByPerson();
            return {};
        },
        /// The note as its editor holds it after the person typed: plugins listening for
        /// `editor-change` hear of it, and the suggestions at the cursor come back.
        async 'editor.update'(message) {
            const app = runtime.app;
            const previousView = app.workspace.getActiveViewOfType(MarkdownView);
            const previousText = previousView && previousView.editor ? previousView.editor.getValue() : null;
            const previousPath = previousView && previousView.file ? previousView.file.path : null;
            if (message.activeDocument) app.workspace.setActiveDocument(message.activeDocument);
            const view = app.workspace.getActiveViewOfType(MarkdownView);
            if (!view || !view.editor) return { suggestion: null };
            if (previousText !== null && previousPath === (view.file && view.file.path) && previousText !== view.editor.getValue()) {
                app.workspace.trigger('editor-change', view.editor, view);
            }
            if (!message.wantsSuggestions) return { suggestion: null };
            return { suggestion: await findSuggestions(view.editor, view, message.requestIdentifier) };
        },
        /// The person closed the suggestions (Escape) without choosing one.
        async 'editor.closeSuggestions'() {
            for (const editorSuggest of runtime.editorSuggests) { if (editorSuggest.isOpen) editorSuggest.close(); }
            shownSuggestion = null;
            return {};
        },
        /// The person chose a suggestion: the plugin inserts it through the editor.
        async 'editor.chooseSuggestion'(message) {
            const suggestion = shownSuggestion;
            if (!suggestion || suggestion.requestIdentifier !== message.requestIdentifier || !(message.position in suggestion.values)) return { outcome: 'missing' };
            shownSuggestion = null;
            const editorSuggest = suggestion.editorSuggest;
            editorSuggest.context = suggestion.context;
            try {
                editorSuggest.selectSuggestion(suggestion.values[message.position], new globalScope.KeyboardEvent('keydown', { key: 'Enter' }));
                return { outcome: 'ran' };
            } catch (error) {
                console.error(error);
                hostBridge.notify('plugin.failure', { pluginIdentifier: editorSuggest.pluginIdentifier || null, message: 'A suggestion failed: ' + (error && error.message ? error.message : String(error)) });
                return { outcome: 'failed', message: error && error.message ? error.message : String(error) };
            }
        },
        /// A file or folder's context menu (`file-menu`), or several files' (`files-menu`).
        async 'menu.file'(message) {
            const app = runtime.app;
            const files = (message.paths || []).map((path) => app.vault.getAbstractFileByPath(normalizePath(path))).filter(Boolean);
            const menu = new exportedApi.Menu();
            const source = message.source || 'file-explorer-context-menu';
            if (files.length === 1) app.workspace.trigger('file-menu', menu, files[0], source, null);
            else if (files.length > 1) app.workspace.trigger('files-menu', menu, files, source, null);
            return offerMenu(message.menuIdentifier, menu);
        },
        /// The note editor's menu at the cursor (`editor-menu`).
        async 'menu.editor'(message) {
            const app = runtime.app;
            if (message.activeDocument) app.workspace.setActiveDocument(message.activeDocument);
            const view = app.workspace.getActiveViewOfType(MarkdownView);
            if (!view || !view.editor) return { items: [] };
            const menu = new exportedApi.Menu();
            app.workspace.trigger('editor-menu', menu, view.editor, view);
            return offerMenu(message.menuIdentifier, menu);
        },
        async 'menu.choose'(message) {
            const openMenu = closeMenu(message.menuIdentifier);
            if (!openMenu) return { outcome: 'missing' };
            const chosen = openMenu.choices[message.position];
            const reportFailure = (error) => {
                console.error(error);
                hostBridge.notify('plugin.failure', { pluginIdentifier: null, message: '“' + (chosen ? chosen.title : '') + '” failed: ' + (error && error.message ? error.message : String(error)) });
            };
            try {
                // Not waited for: an item may open a window that waits for the person.
                const outcome = chosen && !chosen.isDisabled && chosen.item.clickCallback ? chosen.item.clickCallback(new globalScope.MouseEvent('click')) : null;
                if (outcome && typeof outcome.catch === 'function') outcome.catch(reportFailure);
                return { outcome: chosen ? 'ran' : 'missing' };
            } catch (error) {
                reportFailure(error);
                return { outcome: 'failed', message: error && error.message ? error.message : String(error) };
            } finally {
                openMenu.menu.hide();
            }
        },
        async 'menu.dismiss'(message) {
            const openMenu = closeMenu(message.menuIdentifier);
            if (openMenu) openMenu.menu.hide();
            return {};
        },
        async 'protocol.open'(message) {
            const handler = runtime.protocolHandlers.get(message.action);
            if (!handler) return { isHandled: false };
            await handler(Object.assign({ action: message.action }, message.parameters || {}));
            return { isHandled: true };
        },
    };

    /// A plugin whose `data.json` another app or device changed hears of it, as in Obsidian.
    function notifyPluginsOfSettingsChanges(changes) {
        const app = runtime.app;
        for (const change of changes) {
            const match = new RegExp('^' + app.vault.configDir.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '/plugins/([^/]+)/data\\.json$').exec(normalizePath(change.path));
            if (!match) continue;
            const plugin = Object.values(app.plugins.plugins).find((candidate) => candidate.pluginFolderPath() === normalizePath(app.vault.configDir + '/plugins/' + match[1]));
            if (plugin) {
                try { plugin.onExternalSettingsChange(); } catch (error) { console.error(error); }
            }
        }
    }

    /// Later runtime files add their own messages here.
    runtime.messageHandlers = messageHandlers;

    /// The one entry point Graphite calls. Answers with a value the bridge can carry.
    runtime.receive = async function receive(message) {
        const handler = messageHandlers[message.operation];
        if (!handler) return { failure: { kind: 'unknownOperation', message: 'The plugin runtime does not know “' + message.operation + '”.' } };
        try {
            return await handler(message);
        } catch (error) {
            console.error(error);
            return { failure: { kind: 'runtime', message: error && error.message ? error.message : String(error) } };
        }
    };

    Object.assign(exportedApi, { App, Plugin, Notice });
    runtime.missingModuleExplanation = missingModuleExplanation;
})(globalThis);

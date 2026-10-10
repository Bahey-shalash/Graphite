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

    function createPluginRequire(pluginIdentifier) {
        return function require(moduleName) {
            if (moduleName === 'obsidian') return exportedApi;
            if (Object.prototype.hasOwnProperty.call(codeMirrorModules, moduleName)) return codeMirrorModules[moduleName];
            const explanation = missingModuleExplanation(moduleName);
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

        /// Obsidian mobile has no status bar, so the item exists but is not shown.
        addStatusBarItem() {
            const element = createDiv({ cls: 'status-bar-item plugin-' + this.manifest.id.replace(/[^A-Za-z0-9_-]/g, '-') });
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
            runtime.reportUnsupportedFeature('Changing how notes look in reading view', this.manifest.id);
            this.register(() => { runtime.markdownPostProcessors = runtime.markdownPostProcessors.filter((candidate) => candidate !== registered); });
            return postProcessor;
        }

        registerMarkdownCodeBlockProcessor(language, handler, sortOrder) {
            const registered = { handler, sortOrder: sortOrder || 0, pluginIdentifier: this.manifest.id };
            runtime.codeBlockProcessors.set(language, registered);
            runtime.reportUnsupportedFeature('Drawing “' + language + '” code blocks in notes', this.manifest.id);
            this.register(() => { if (runtime.codeBlockProcessors.get(language) === registered) runtime.codeBlockProcessors.delete(language); });
            return handler;
        }

        registerEditorExtension() {
            runtime.reportUnsupportedFeature('CodeMirror editor extensions', this.manifest.id);
        }

        registerEditorSuggest() {
            runtime.reportUnsupportedFeature('Suggestions while typing in a note', this.manifest.id);
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
                const source = '(function anonymous(require, module, exports) {\n' + description.mainSource + '\n})\n//# sourceURL=plugin:' + pluginIdentifier + '/main.js';
                const moduleFactory = (0, globalScope.eval)(source);
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
        /// Assigns a type as Obsidian's Properties view does, keeping the rest of the file.
        async setType(name, type) {
            await this.app.vault.adapter.process(this.typesPath(), (existingText) => {
                const configuration = existingText.trim() ? JSON.parse(existingText) : {};
                const types = configuration.types && typeof configuration.types === 'object' ? configuration.types : {};
                if (types[name] === type) return existingText;
                types[name] = type;
                configuration.types = types;
                this.types = types;
                return JSON.stringify(configuration, null, 2);
            }).catch(async (error) => {
                if (await this.app.vault.adapter.exists(this.typesPath())) throw error;
                this.types = { [name]: type };
                await this.app.vault.adapter.write(this.typesPath(), JSON.stringify({ types: this.types }, null, 2));
            });
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
            this.lastEvent = null;
            this.isMobile = true;
            this.appId = '';
            this.setting = {
                open: () => hostBridge.notify('settings.open', { pluginIdentifier: null }),
                openTabById: (tabIdentifier) => hostBridge.notify('settings.open', { pluginIdentifier: tabIdentifier }),
                close: () => runtime.pluginSurface.handleClosedByPerson(),
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
    }

    runtime.ribbon = new RibbonRegistry();

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

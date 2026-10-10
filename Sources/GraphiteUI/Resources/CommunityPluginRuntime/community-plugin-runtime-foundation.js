// The base of Graphite's runtime for Obsidian community plugins: the channel to the
// native app, Obsidian's `Events` and `Component`, and the utility functions the
// `obsidian` module exports. Later files add the vault, workspace, interface and plugins.
(function installRuntimeFoundation(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime = globalScope.GraphitePluginRuntime || {};
    const exportedApi = runtime.obsidianModule = runtime.obsidianModule || {};

    // The Obsidian API version plugins see (`apiVersion`, `requireApiVersion`). It is the
    // version whose public API this runtime follows; parts it does not implement report
    // themselves as unsupported when a plugin calls them.
    runtime.compatibleApiVersion = '1.14.4';

    // MARK: Channel to the native app

    /// A failure the native side reported, with Obsidian's wording where Obsidian has one.
    class HostOperationError extends Error {
        constructor(kind, message) {
            super(message);
            this.name = 'HostOperationError';
            this.kind = kind;
        }
    }
    runtime.HostOperationError = HostOperationError;

    /// Calls Graphite. `transport` is set by the page: in the app it posts to the web
    /// view's message handler, in tests it answers from a folder on disk.
    runtime.hostBridge = {
        transport: null,
        async send(operation, parameters) {
            if (!this.transport) throw new HostOperationError('unavailable', 'Graphite is not connected to this plugin runtime.');
            const response = await this.transport(Object.assign({ operation }, parameters || {}));
            if (response && response.failure) throw new HostOperationError(response.failure.kind, response.failure.message);
            return response || {};
        },
        /// A message that needs no answer, such as a changed command list.
        notify(operation, parameters) {
            this.send(operation, parameters).catch((error) => console.error('Graphite could not deliver “' + operation + '”.', error));
        },
    };

    // MARK: Unsupported features

    /// Thrown when a plugin uses part of Obsidian's API or runtime that Graphite does not
    /// provide, so the plugin fails visibly instead of appearing to work.
    class UnsupportedFeatureError extends Error {
        constructor(featureName, explanation) {
            super(featureName + ' is not supported in Graphite yet.' + (explanation ? ' ' + explanation : ''));
            this.name = 'UnsupportedFeatureError';
            this.featureName = featureName;
        }
    }
    runtime.UnsupportedFeatureError = UnsupportedFeatureError;

    /// The plugin whose code is running, read from the call stack: each plugin's code is
    /// evaluated with the source name `plugin:<id>`, so its frames carry its identifier.
    runtime.callingPluginIdentifier = function callingPluginIdentifier() {
        const stack = new Error().stack || '';
        const match = /plugin:([^/\s:)]+)\//.exec(stack);
        return match ? match[1] : null;
    };

    const reportedUnsupportedFeatures = new Set();
    /// Records that a plugin reached a feature Graphite lacks, once per plugin and feature,
    /// so its settings page can say which parts of it do not work.
    runtime.reportUnsupportedFeature = function reportUnsupportedFeature(featureName, pluginIdentifier) {
        const identifier = pluginIdentifier || runtime.callingPluginIdentifier() || 'unknown';
        const key = identifier + '\u0000' + featureName;
        if (reportedUnsupportedFeatures.has(key)) return;
        reportedUnsupportedFeatures.add(key);
        runtime.hostBridge.notify('plugin.unsupportedFeature', { pluginIdentifier: identifier, featureName });
    };

    /// Reports the feature and throws, for calls that cannot do anything meaningful.
    runtime.unsupported = function unsupported(featureName, explanation) {
        runtime.reportUnsupportedFeature(featureName);
        throw new UnsupportedFeatureError(featureName, explanation);
    };

    // MARK: Events and Component

    class Events {
        constructor() {
            this.eventReferencesByName = {};
        }
        on(name, callback, context) {
            const references = this.eventReferencesByName[name] || (this.eventReferencesByName[name] = []);
            const eventReference = { events: this, name, callback, context };
            references.push(eventReference);
            return eventReference;
        }
        off(name, callback) {
            const references = this.eventReferencesByName[name];
            if (!references) return;
            this.eventReferencesByName[name] = references.filter((eventReference) => eventReference.callback !== callback);
        }
        offref(eventReference) {
            if (!eventReference) return;
            const references = this.eventReferencesByName[eventReference.name];
            if (!references) return;
            const position = references.indexOf(eventReference);
            if (position !== -1) references.splice(position, 1);
        }
        trigger(name, ...eventArguments) {
            const references = this.eventReferencesByName[name];
            if (!references) return;
            for (const eventReference of references.slice()) this.tryTrigger(eventReference, eventArguments);
        }
        tryTrigger(eventReference, eventArguments) {
            try {
                eventReference.callback.apply(eventReference.context, eventArguments);
            } catch (error) {
                console.error(error);
            }
        }
    }

    class Component {
        constructor() {
            this.isComponentLoaded = false;
            this.cleanupCallbacks = [];
            this.childComponents = [];
        }
        load() {
            if (this.isComponentLoaded) return;
            this.isComponentLoaded = true;
            this.onload();
            for (const child of this.childComponents.slice()) child.load();
        }
        onload() {}
        unload() {
            if (!this.isComponentLoaded) return;
            this.isComponentLoaded = false;
            for (const child of this.childComponents.splice(0)) child.unload();
            for (const cleanup of this.cleanupCallbacks.splice(0)) {
                try { cleanup(); } catch (error) { console.error(error); }
            }
            this.onunload();
        }
        onunload() {}
        addChild(component) {
            this.childComponents.push(component);
            if (this.isComponentLoaded) component.load();
            return component;
        }
        removeChild(component) {
            const position = this.childComponents.indexOf(component);
            if (position !== -1) {
                this.childComponents.splice(position, 1);
                component.unload();
            }
            return component;
        }
        register(callback) {
            this.cleanupCallbacks.push(callback);
        }
        registerEvent(eventReference) {
            this.register(() => eventReference.events.offref(eventReference));
        }
        registerDomEvent(target, eventType, callback, options) {
            target.addEventListener(eventType, callback, options);
            this.register(() => target.removeEventListener(eventType, callback, options));
        }
        registerScopeEvent(keymapEventHandler) {
            this.register(() => keymapEventHandler.scope.unregister(keymapEventHandler));
        }
        registerInterval(intervalIdentifier) {
            this.register(() => globalScope.clearInterval(intervalIdentifier));
            return intervalIdentifier;
        }
    }

    // MARK: Paths and links

    function normalizePath(path) {
        let normalized = String(path).replace(/([\\/])+/g, '/').replace(/(^\/+|\/+$)/g, '');
        if (normalized === '') normalized = '/';
        return normalized.replace(/ | /g, ' ').normalize('NFC');
    }

    function parseLinktext(linktext) {
        const hashPosition = linktext.indexOf('#');
        if (hashPosition === -1) return { path: linktext, subpath: '' };
        return { path: linktext.slice(0, hashPosition), subpath: linktext.slice(hashPosition) };
    }

    function getLinkpath(linktext) {
        return parseLinktext(linktext).path;
    }

    function stripHeading(heading) {
        return heading.replace(/[!"#$%&()*+,.:;<=>?@^`{|}~/[\]\\]/g, ' ').replace(/\s+/g, ' ').trim();
    }

    function stripHeadingForLink(heading) {
        return heading.replace(/[#|^\\%[\]:]/g, ' ').replace(/\s+/g, ' ').trim();
    }

    // MARK: Frontmatter

    function frontmatterValue(frontmatter, keyPattern) {
        if (!frontmatter) return null;
        for (const key of Object.keys(frontmatter)) {
            const matches = keyPattern instanceof RegExp ? keyPattern.test(key) : key === keyPattern;
            if (matches && frontmatter[key] !== null && frontmatter[key] !== undefined) return frontmatter[key];
        }
        return null;
    }

    function parseFrontMatterEntry(frontmatter, keyPattern) {
        return frontmatterValue(frontmatter, keyPattern);
    }

    function parseFrontMatterStringArray(frontmatter, keyPattern, isSplittingAtSpaces) {
        const value = frontmatterValue(frontmatter, keyPattern);
        if (value === null) return null;
        const values = Array.isArray(value) ? value : String(value).split(isSplittingAtSpaces ? /[,\s]+/ : /,/);
        const strings = values.filter((entry) => entry !== null && entry !== undefined).map((entry) => String(entry).trim()).filter((entry) => entry.length > 0);
        return strings.length > 0 ? strings : null;
    }

    function parseFrontMatterAliases(frontmatter) {
        if (!frontmatter) return null;
        return parseFrontMatterStringArray(frontmatter, /^alias(es)?$/i, false);
    }

    function parseFrontMatterTags(frontmatter) {
        if (!frontmatter) return null;
        const tags = parseFrontMatterStringArray(frontmatter, /^tags?$/i, true);
        return tags ? tags.map((tag) => (tag.startsWith('#') ? tag : '#' + tag)) : null;
    }

    function getAllTags(cache) {
        if (!cache) return null;
        const tags = [];
        const frontmatterTags = parseFrontMatterTags(cache.frontmatter);
        if (frontmatterTags) tags.push(...frontmatterTags);
        if (cache.tags) tags.push(...cache.tags.map((tagCache) => tagCache.tag));
        return tags;
    }

    /// Where a note's frontmatter is: Obsidian's `getFrontMatterInfo`.
    function getFrontMatterInfo(content) {
        const opening = /^---[ \t]*\r?\n/.exec(content);
        if (!opening) return { exists: false, frontmatter: '', from: 0, to: 0, contentStart: 0 };
        const closing = /(^|\r?\n)(---|\.\.\.)[ \t]*(\r?\n|$)/g;
        closing.lastIndex = opening[0].length - 1;
        let match;
        while ((match = closing.exec(content)) !== null) {
            const closingStart = match.index + match[1].length;
            if (closingStart < opening[0].length) continue;
            return {
                exists: true,
                frontmatter: content.slice(opening[0].length, closingStart),
                from: opening[0].length,
                to: closingStart,
                contentStart: match.index + match[0].length,
            };
        }
        return { exists: false, frontmatter: '', from: 0, to: 0, contentStart: 0 };
    }

    // MARK: YAML

    function yamlLibrary() {
        if (!globalScope.jsyaml) throw new UnsupportedFeatureError('YAML', 'The YAML library did not load.');
        return globalScope.jsyaml;
    }

    // The core schema keeps dates as the text written, as Obsidian's properties do,
    // rather than turning `2024-05-01` into a Date.
    function parseYaml(text) {
        const value = yamlLibrary().load(text, { schema: yamlLibrary().CORE_SCHEMA });
        return value === undefined ? null : value;
    }

    function stringifyYaml(value) {
        return yamlLibrary().dump(value, { lineWidth: -1 });
    }

    // MARK: Binary data

    function arrayBufferToBase64(buffer) {
        const bytes = new Uint8Array(buffer);
        let binary = '';
        const chunkLength = 0x8000;
        for (let offset = 0; offset < bytes.length; offset += chunkLength) {
            binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + chunkLength));
        }
        return globalScope.btoa(binary);
    }

    function base64ToArrayBuffer(base64) {
        const binary = globalScope.atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let offset = 0; offset < binary.length; offset += 1) bytes[offset] = binary.charCodeAt(offset);
        return bytes.buffer;
    }

    function arrayBufferToHex(buffer) {
        return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, '0')).join('');
    }

    function hexToArrayBuffer(hex) {
        const bytes = new Uint8Array(Math.floor(hex.length / 2));
        for (let offset = 0; offset < bytes.length; offset += 1) bytes[offset] = parseInt(hex.substr(offset * 2, 2), 16);
        return bytes.buffer;
    }

    async function getBlobArrayBuffer(blob) {
        return blob.arrayBuffer();
    }

    function bufferFromBody(body) {
        if (body === undefined || body === null) return null;
        if (typeof body === 'string') return new TextEncoder().encode(body).buffer;
        if (body instanceof ArrayBuffer) return body;
        if (ArrayBuffer.isView(body)) return body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
        return new TextEncoder().encode(String(body)).buffer;
    }

    // MARK: Timing

    function debounce(callback, timeoutMilliseconds, isResettingTimer) {
        const delay = timeoutMilliseconds || 0;
        let timerIdentifier = null;
        let pendingArguments = null;
        let pendingContext = null;
        function runPending() {
            timerIdentifier = null;
            const callArguments = pendingArguments;
            pendingArguments = null;
            if (callArguments) callback.apply(pendingContext, callArguments);
        }
        const debounced = function debounced(...callArguments) {
            pendingArguments = callArguments;
            pendingContext = this;
            if (timerIdentifier !== null) {
                if (!isResettingTimer) return debounced;
                globalScope.clearTimeout(timerIdentifier);
            }
            timerIdentifier = globalScope.setTimeout(runPending, delay);
            return debounced;
        };
        debounced.cancel = function cancel() {
            if (timerIdentifier !== null) globalScope.clearTimeout(timerIdentifier);
            timerIdentifier = null;
            pendingArguments = null;
            return debounced;
        };
        debounced.run = function run() {
            if (timerIdentifier === null) return undefined;
            globalScope.clearTimeout(timerIdentifier);
            const callArguments = pendingArguments;
            timerIdentifier = null;
            pendingArguments = null;
            return callArguments ? callback.apply(pendingContext, callArguments) : undefined;
        };
        return debounced;
    }

    // MARK: Search

    /// Obsidian's fuzzy search: every character of the query in order, scored higher for
    /// matches at word starts and runs of consecutive characters.
    function prepareFuzzySearch(query) {
        const queryCharacters = Array.from(query.toLowerCase().replace(/\s+/g, ''));
        return function fuzzySearch(text) {
            if (queryCharacters.length === 0) return { score: 0, matches: [] };
            const lowercasedText = text.toLowerCase();
            const matches = [];
            let score = 0;
            let textPosition = 0;
            let previousMatchEnd = -2;
            for (const queryCharacter of queryCharacters) {
                const foundPosition = lowercasedText.indexOf(queryCharacter, textPosition);
                if (foundPosition === -1) return null;
                const isWordStart = foundPosition === 0 || /[\s\-_/.()[\]]/.test(lowercasedText[foundPosition - 1]);
                if (foundPosition === previousMatchEnd) {
                    matches[matches.length - 1][1] = foundPosition + queryCharacter.length;
                    score += 1;
                } else {
                    matches.push([foundPosition, foundPosition + queryCharacter.length]);
                    score -= isWordStart ? 0.5 : 1 + (foundPosition - textPosition) * 0.01;
                }
                previousMatchEnd = foundPosition + queryCharacter.length;
                textPosition = previousMatchEnd;
            }
            score -= (text.length - query.length) * 0.001;
            return { score, matches };
        };
    }

    /// Obsidian's simple search: every word of the query somewhere in the text.
    function prepareSimpleSearch(query) {
        const words = query.toLowerCase().split(/\s+/).filter((word) => word.length > 0);
        return function simpleSearch(text) {
            const lowercasedText = text.toLowerCase();
            const matches = [];
            for (const word of words) {
                const foundPosition = lowercasedText.indexOf(word);
                if (foundPosition === -1) return null;
                matches.push([foundPosition, foundPosition + word.length]);
            }
            matches.sort((firstMatch, secondMatch) => firstMatch[0] - secondMatch[0]);
            return { score: -matches.length, matches };
        };
    }

    function renderMatches(element, text, matches, characterOffset) {
        const offset = characterOffset || 0;
        let position = 0;
        for (const match of matches || []) {
            const start = match[0] + offset;
            const end = match[1] + offset;
            if (start < 0 || end > text.length || start < position) continue;
            if (start > position) element.appendText(text.slice(position, start));
            element.createSpan({ cls: 'suggestion-highlight', text: text.slice(start, end) });
            position = end;
        }
        if (position < text.length) element.appendText(text.slice(position));
    }

    function renderResults(element, text, searchResult, characterOffset) {
        renderMatches(element, text, searchResult ? searchResult.matches : [], characterOffset);
    }

    function sortSearchResults(results) {
        results.sort((firstResult, secondResult) => secondResult.match.score - firstResult.match.score);
    }

    // MARK: HTML

    const unsafeElementNames = new Set(['script', 'style', 'iframe', 'object', 'embed', 'link', 'meta', 'base', 'form']);

    function sanitizeHTMLToDom(html) {
        const parsedDocument = new globalScope.DOMParser().parseFromString('<body>' + html + '</body>', 'text/html');
        const walker = parsedDocument.createTreeWalker(parsedDocument.body, 1);
        const elementsToRemove = [];
        while (walker.nextNode()) {
            const element = walker.currentNode;
            if (unsafeElementNames.has(element.localName)) { elementsToRemove.push(element); continue; }
            for (const attribute of Array.from(element.attributes)) {
                const attributeName = attribute.name.toLowerCase();
                const isScriptAddress = /^\s*javascript:/i.test(attribute.value);
                if (attributeName.startsWith('on') || isScriptAddress) element.removeAttribute(attribute.name);
            }
        }
        for (const element of elementsToRemove) element.remove();
        const fragment = globalScope.document.createDocumentFragment();
        while (parsedDocument.body.firstChild) fragment.appendChild(globalScope.document.adoptNode(parsedDocument.body.firstChild));
        return fragment;
    }

    /// Obsidian's `htmlToMarkdown` for the HTML plugins usually pass: headings, paragraphs,
    /// emphasis, links, images, lists, quotes, code and line breaks.
    function htmlToMarkdown(html) {
        const container = typeof html === 'string' ? new globalScope.DOMParser().parseFromString(html, 'text/html').body : html;
        function convertChildren(node, listDepth) {
            return Array.from(node.childNodes).map((child) => convertNode(child, listDepth)).join('');
        }
        function convertNode(node, listDepth) {
            if (node.nodeType === 3) return node.textContent.replace(/\s+/g, ' ');
            if (node.nodeType !== 1) return '';
            const name = node.localName;
            const inner = () => convertChildren(node, listDepth);
            switch (name) {
            case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6':
                return '\n\n' + '#'.repeat(Number(name[1])) + ' ' + inner().trim() + '\n\n';
            case 'p': case 'div': return '\n\n' + inner().trim() + '\n\n';
            case 'br': return '\n';
            case 'hr': return '\n\n---\n\n';
            case 'strong': case 'b': return '**' + inner() + '**';
            case 'em': case 'i': return '*' + inner() + '*';
            case 's': case 'del': case 'strike': return '~~' + inner() + '~~';
            case 'mark': return '==' + inner() + '==';
            case 'code': return node.parentElement && node.parentElement.localName === 'pre' ? node.textContent : '`' + node.textContent + '`';
            case 'pre': return '\n\n```\n' + node.textContent.replace(/\n$/, '') + '\n```\n\n';
            case 'a': {
                const address = node.getAttribute('href');
                return address ? '[' + inner() + '](' + address + ')' : inner();
            }
            case 'img': return '![' + (node.getAttribute('alt') || '') + '](' + (node.getAttribute('src') || '') + ')';
            case 'blockquote': return '\n\n' + inner().trim().split('\n').map((line) => '> ' + line).join('\n') + '\n\n';
            case 'ul': case 'ol': {
                const items = Array.from(node.children).filter((child) => child.localName === 'li');
                const lines = items.map((item, itemPosition) => {
                    const marker = name === 'ol' ? (itemPosition + 1) + '. ' : '- ';
                    const content = convertChildren(item, listDepth + 1).trim().replace(/\n{2,}/g, '\n');
                    return '    '.repeat(listDepth) + marker + content.split('\n').join('\n' + '    '.repeat(listDepth + 1));
                });
                return (listDepth === 0 ? '\n\n' : '\n') + lines.join('\n') + (listDepth === 0 ? '\n\n' : '');
            }
            case 'script': case 'style': return '';
            default: return inner();
            }
        }
        return convertChildren(container, 0).replace(/\n{3,}/g, '\n\n').trim();
    }

    // MARK: Network

    /// Obsidian's `requestUrl`: an HTTP request made by Graphite rather than the page, so
    /// it is not bound by the page's cross-origin rules, as on Obsidian mobile.
    function requestUrl(requestParameters) {
        const parameters = typeof requestParameters === 'string' ? { url: requestParameters } : requestParameters;
        const responsePromise = (async () => {
            const body = bufferFromBody(parameters.body);
            const response = await runtime.hostBridge.send('network.request', {
                url: parameters.url,
                method: parameters.method || 'GET',
                contentType: parameters.contentType || null,
                headers: parameters.headers || {},
                bodyBase64: body ? arrayBufferToBase64(body) : null,
            });
            const arrayBuffer = base64ToArrayBuffer(response.bodyBase64 || '');
            const headers = {};
            for (const headerName of Object.keys(response.headers || {})) headers[headerName.toLowerCase()] = response.headers[headerName];
            const result = {
                status: response.status,
                headers,
                arrayBuffer,
                get text() { return new TextDecoder().decode(arrayBuffer); },
                get json() { return JSON.parse(new TextDecoder().decode(arrayBuffer)); },
            };
            if (response.status >= 400 && parameters.throw !== false) {
                const error = new Error('Request failed, status ' + response.status);
                error.status = response.status;
                error.headers = headers;
                throw error;
            }
            return result;
        })();
        responsePromise.arrayBuffer = responsePromise.then((response) => response.arrayBuffer);
        responsePromise.json = responsePromise.then((response) => response.json);
        responsePromise.text = responsePromise.then((response) => response.text);
        return responsePromise;
    }

    async function request(requestParameters) {
        const response = await requestUrl(requestParameters);
        return response.text;
    }

    // MARK: Platform

    const Platform = {
        isDesktop: false,
        isMobile: true,
        isDesktopApp: false,
        isMobileApp: true,
        isIosApp: true,
        isAndroidApp: false,
        isPhone: false,
        isTablet: true,
        isMacOS: false,
        isWin: false,
        isLinux: false,
        isSafari: true,
        resourcePathPrefix: 'graphite-vault://resource/',
    };

    /// Called once by the page with what Graphite knows about the device.
    runtime.configurePlatform = function configurePlatform(deviceDescription) {
        Platform.isPhone = Boolean(deviceDescription && deviceDescription.isPhone);
        Platform.isTablet = !Platform.isPhone;
        if (deviceDescription && typeof deviceDescription.resourcePathPrefix === 'string') Platform.resourcePathPrefix = deviceDescription.resourcePathPrefix;
        const body = globalScope.document && globalScope.document.body;
        if (body) {
            body.toggleClass('is-phone', Platform.isPhone);
            body.toggleClass('is-tablet', Platform.isTablet);
        }
    };

    function compareVersions(firstVersion, secondVersion) {
        const firstParts = String(firstVersion).split('.').map((part) => parseInt(part, 10) || 0);
        const secondParts = String(secondVersion).split('.').map((part) => parseInt(part, 10) || 0);
        for (let partPosition = 0; partPosition < Math.max(firstParts.length, secondParts.length); partPosition += 1) {
            const difference = (firstParts[partPosition] || 0) - (secondParts[partPosition] || 0);
            if (difference !== 0) return difference;
        }
        return 0;
    }
    runtime.compareVersions = compareVersions;

    function requireApiVersion(version) {
        return compareVersions(runtime.compatibleApiVersion, version) >= 0;
    }

    // MARK: Language, background tasks and bundled libraries

    function getLanguage() {
        const language = (globalScope.navigator && globalScope.navigator.language) || 'en';
        return language.split('-')[0] || 'en';
    }

    /// Obsidian's `Tasks`: promises a caller waits for together.
    class Tasks {
        constructor() { this.promises = []; }
        add(callback) { this.promises.push(Promise.resolve().then(callback)); }
        addPromise(promise) { this.promises.push(promise); }
        isEmpty() { return this.promises.length === 0; }
        promise() { return Promise.all(this.promises); }
    }

    /// Libraries Obsidian ships for plugins to load on demand. Graphite renders math,
    /// diagrams and PDFs natively and does not bundle these copies.
    function bundledLibraryLoader(libraryName) {
        return async function loadBundledLibrary() {
            runtime.unsupported(libraryName, 'Graphite does not provide Obsidian\'s copy of it to plugins.');
        };
    }

    function renderMath() {
        runtime.unsupported('renderMath', 'Graphite renders math natively in notes, not in plugin views yet.');
    }

    /// Obsidian's per-vault secrets (`app.secretStorage`). Graphite keeps them in the
    /// device's keychain, outside the vault, and gives them to the runtime when it starts.
    class SecretStorage extends Events {
        constructor() {
            super();
            this.secretsByIdentifier = new Map();
        }
        adoptSecrets(secrets) {
            this.secretsByIdentifier = new Map(Object.entries(secrets || {}));
        }
        setSecret(identifier, secret) {
            this.secretsByIdentifier.set(identifier, secret);
            runtime.hostBridge.notify('secrets.set', { secretIdentifier: identifier, secret });
            this.trigger('change', identifier);
        }
        getSecret(identifier) {
            return this.secretsByIdentifier.has(identifier) ? this.secretsByIdentifier.get(identifier) : null;
        }
        listSecrets() {
            return Array.from(this.secretsByIdentifier.keys());
        }
    }

    // MARK: Export

    Object.assign(exportedApi, {
        Events,
        Component,
        normalizePath,
        parseLinktext,
        getLinkpath,
        stripHeading,
        stripHeadingForLink,
        parseFrontMatterEntry,
        parseFrontMatterStringArray,
        parseFrontMatterAliases,
        parseFrontMatterTags,
        getAllTags,
        getFrontMatterInfo,
        parseYaml,
        stringifyYaml,
        arrayBufferToBase64,
        base64ToArrayBuffer,
        arrayBufferToHex,
        hexToArrayBuffer,
        getBlobArrayBuffer,
        debounce,
        prepareFuzzySearch,
        prepareSimpleSearch,
        renderMatches,
        renderResults,
        sortSearchResults,
        sanitizeHTMLToDom,
        htmlToMarkdown,
        requestUrl,
        request,
        Platform,
        requireApiVersion,
        getLanguage,
        Tasks,
        SecretStorage,
        loadMathJax: bundledLibraryLoader('loadMathJax'),
        loadMermaid: bundledLibraryLoader('loadMermaid'),
        loadPdfJs: bundledLibraryLoader('loadPdfJs'),
        loadPrism: bundledLibraryLoader('loadPrism'),
        renderMath,
        finishRenderMath: async () => {},
    });
    Object.defineProperty(exportedApi, 'apiVersion', { get: () => runtime.compatibleApiVersion, enumerable: true });
    if (globalScope.moment) exportedApi.moment = globalScope.moment;
})(globalThis);

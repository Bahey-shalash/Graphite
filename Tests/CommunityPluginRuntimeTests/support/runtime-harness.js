// Loads Graphite's plugin runtime into jsdom, in the order `index.html` lists its scripts,
// connected to a `TestVaultHost`. jsdom lacks a few browser features WebKit has
// (`TextEncoder`, `CSS.escape`, `requestAnimationFrame`); only those are filled in here.
'use strict';

const fileSystem = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { JSDOM, VirtualConsole } = require('jsdom');
const { TestVaultHost } = require('./test-vault-host');

const runtimeFolder = path.resolve(__dirname, '../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime');

function runtimeScriptPaths() {
    const indexPage = fileSystem.readFileSync(path.join(runtimeFolder, 'index.html'), 'utf8');
    return Array.from(indexPage.matchAll(/<script src="([^"]+)"><\/script>/g), (match) => path.join(runtimeFolder, match[1]));
}

function makeTemporaryVault(files) {
    const vaultFolder = fileSystem.mkdtempSync(path.join(os.tmpdir(), 'graphite-plugin-vault-'));
    for (const vaultPath of Object.keys(files || {})) {
        const location = path.join(vaultFolder, vaultPath);
        fileSystem.mkdirSync(path.dirname(location), { recursive: true });
        fileSystem.writeFileSync(location, files[vaultPath]);
    }
    return vaultFolder;
}

/// A page with the runtime loaded and connected to a vault folder holding `files`.
async function startRuntime(options) {
    const settings = Object.assign({ files: {}, configuration: {}, vaultName: 'Test Vault', isStarting: true }, options || {});
    const vaultFolder = settings.vaultFolder || makeTemporaryVault(settings.files);
    // jsdom's own problems (it cannot parse CSS nesting, which WebKit can) are recorded
    // apart from the page's console, so they never pass for plugin errors.
    const jsdomProblems = [];
    const virtualConsole = new VirtualConsole();
    virtualConsole.on('jsdomError', (error) => jsdomProblems.push(error.message));
    const dom = new JSDOM('<!doctype html><html><head></head><body class="graphite-plugin-runtime theme-light is-mobile is-ios"><div class="app-container"><div class="graphite-plugin-surface"></div></div></body></html>', {
        runScripts: 'outside-only',
        pretendToBeVisual: true,
        url: 'https://graphite-plugins.test/',
        virtualConsole,
    });
    const window = dom.window;
    if (!window.TextEncoder) window.TextEncoder = TextEncoder;
    if (!window.TextDecoder) window.TextDecoder = TextDecoder;
    if (!window.CSS) window.CSS = {};
    if (!window.CSS.escape) window.CSS.escape = (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, (character) => '\\' + character);
    const consoleMessages = [];
    for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        window.console[level] = (...messageParts) => consoleMessages.push({ level, text: messageParts.map((part) => (part && part.stack) || String(part)).join(' ') });
    }
    // WebKit's message handler, as Graphite installs it: the page's connection script finds
    // it and posts every message to it. Like CommunityPluginHost, the host answers vault
    // operations as JSON text and everything else as objects.
    const host = new TestVaultHost(vaultFolder);
    const hostTransport = host.transport();
    window.webkit = { messageHandlers: { graphitePlugins: {
        postMessage: (message) => hostTransport(JSON.parse(JSON.stringify(message))).then((answer) => (
            String(message.operation).startsWith('vault.') ? JSON.stringify(answer) : answer)),
    } } };
    for (const scriptPath of runtimeScriptPaths()) {
        window.eval(fileSystem.readFileSync(scriptPath, 'utf8') + '\n//# sourceURL=' + path.basename(scriptPath));
    }
    const runtime = window.GraphitePluginRuntime;
    const harness = { dom, window, runtime, host, vaultFolder, consoleMessages, jsdomProblems, obsidian: runtime.obsidianModule };
    harness.send = (message) => runtime.receive(message);
    if (settings.isStarting) {
        const answer = await harness.send({
            operation: 'runtime.start',
            vault: { name: settings.vaultName, identifier: 'test-vault', configurationDirectory: '.obsidian', configuration: settings.configuration, corePlugins: settings.corePlugins || [] },
            device: { isPhone: false },
            appearance: 'light',
            recentFiles: [],
        });
        if (answer.failure) throw new Error(answer.failure.message);
        harness.app = runtime.app;
    }
    harness.readVaultFile = (vaultPath) => fileSystem.readFileSync(path.join(vaultFolder, vaultPath), 'utf8');
    harness.vaultFileExists = (vaultPath) => fileSystem.existsSync(path.join(vaultFolder, vaultPath));
    harness.writeVaultFile = (vaultPath, contents) => {
        const location = path.join(vaultFolder, vaultPath);
        fileSystem.mkdirSync(path.dirname(location), { recursive: true });
        fileSystem.writeFileSync(location, contents);
    };
    harness.waitForMetadata = () => waitUntil(() => harness.app.metadataCache.isInitialReadComplete);
    harness.close = () => {
        window.close();
        fileSystem.rmSync(vaultFolder, { recursive: true, force: true });
    };
    return harness;
}

/// Installs a plugin package into the vault's configuration folder and loads it.
async function installAndLoadPlugin(harness, pluginPackage) {
    const manifest = pluginPackage.manifest;
    const folder = '.obsidian/plugins/' + manifest.id;
    harness.writeVaultFile(folder + '/manifest.json', JSON.stringify(manifest, null, 2));
    harness.writeVaultFile(folder + '/main.js', pluginPackage.mainSource);
    if (pluginPackage.styles) harness.writeVaultFile(folder + '/styles.css', pluginPackage.styles);
    if (pluginPackage.data !== undefined) harness.writeVaultFile(folder + '/data.json', JSON.stringify(pluginPackage.data, null, 2));
    return harness.send({ operation: 'plugin.load', manifest: Object.assign({ dir: folder }, manifest), mainSource: pluginPackage.mainSource, styles: pluginPackage.styles || '' });
}

async function waitUntil(condition, timeoutMilliseconds) {
    const deadline = Date.now() + (timeoutMilliseconds || 5000);
    while (!condition()) {
        if (Date.now() > deadline) throw new Error('Timed out waiting.');
        await new Promise((resolve) => setTimeout(resolve, 5));
    }
}

/// A value from the page as a plain Node value, so assertions compare contents rather
/// than which JavaScript realm made the arrays and objects.
function plain(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

/// Lets queued promise callbacks and zero-delay timers run.
function settle() {
    return new Promise((resolve) => setTimeout(resolve, 20));
}

module.exports = { startRuntime, installAndLoadPlugin, makeTemporaryVault, waitUntil, settle, plain, runtimeFolder };

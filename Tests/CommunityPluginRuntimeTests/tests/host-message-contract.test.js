// The messages the plugin runtime and Graphite's Swift host exchange, as the two sides spell
// them: the web view's message handler, the operations in each direction, how a failure
// is reported, which scripts the page loads in which order, and the API version plugins see.
// A renamed operation breaks the other side without any compiler noticing, so the names
// are written out here, and the Swift host's tests (GraphiteUITests) write out the same.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');
const { startRuntime, plain, runtimeFolder } = require('../support/runtime-harness');

function runtimeScriptNames() {
    const indexPage = fileSystem.readFileSync(path.join(runtimeFolder, 'index.html'), 'utf8');
    return Array.from(indexPage.matchAll(/<script src="([^"]+)"><\/script>/g), (match) => match[1]);
}

/// The operations Swift sends to the runtime (JavaScript handles them).
const operationsFromGraphite = [
    'appearance.changed', 'appearance.styles', 'basesView.open', 'basesView.update', 'codeBlock.event', 'codeBlock.release',
    'codeBlock.render', 'command.run', 'editor.chooseSuggestion', 'editor.closeSuggestions', 'editor.drop', 'editor.paste',
    'editor.update', 'file.openInView', 'menu.choose', 'menu.dismiss', 'menu.editor', 'menu.file', 'notice.tap', 'plugin.load',
    'plugin.unload', 'plugins.layoutReady', 'protocol.open', 'ribbon.run', 'runtime.start', 'runtime.stop', 'settings.show',
    'surface.closed', 'vault.changes', 'vault.configuration', 'view.attach', 'view.close', 'view.live', 'view.resize',
    'view.restore', 'view.show', 'view.unlive', 'views.saveFiles', 'workspace.activeDocument',
];

/// The operations the runtime sends to Swift: those answered, and those that only notify.
const operationsToGraphite = [
    'appearance.setConfig', 'basesViews.changed', 'clipboard.readText', 'clipboard.writeText', 'codeBlock.changed',
    'codeBlocks.changed', 'commands.changed', 'editor.apply', 'editor.listenersChanged', 'fileViews.changed', 'markdown.render',
    'menu.show', 'menus.changed', 'network.request', 'notice.hide', 'notice.show', 'notice.update', 'plugin.failure',
    'plugin.settingTabChanged', 'plugin.unsupportedFeature', 'plugin.writeConflict', 'plugins.setEnabled', 'postProcessors.changed',
    'ribbon.changed', 'secrets.set', 'settings.open', 'styles.changed', 'surface.dismiss', 'surface.present', 'vault.copy',
    'vault.createFolder', 'vault.list', 'vault.listFolder', 'vault.read', 'vault.remove', 'vault.rename', 'vault.stat',
    'vault.write', 'view.reveal', 'views.changed', 'workspace.openExternalLink', 'workspace.openFile', 'workspace.openLinkText',
    'workspace.renameFile',
];

test('the operations Graphite can send to the runtime are exactly the 39 the runtime handles', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(Object.keys(harness.runtime.messageHandlers).sort(), operationsFromGraphite.slice().sort());
        assert.equal(operationsFromGraphite.length, 39);
    } finally {
        harness.close();
    }
});

test('the operations the runtime sends to Graphite are exactly the 44 written out here, each named by a literal', () => {
    const sendNames = new Set();
    let callCount = 0;
    let literalCallCount = 0;
    for (const scriptName of runtimeScriptNames().filter((name) => !name.startsWith('Vendor/'))) {
        const source = fileSystem.readFileSync(path.join(runtimeFolder, scriptName), 'utf8');
        callCount += Array.from(source.matchAll(/hostBridge\.(?:send|notify)\(/g)).length;
        for (const match of source.matchAll(/hostBridge\.(?:send|notify)\(\s*'([A-Za-z.]+)'/g)) {
            sendNames.add(match[1]);
            literalCallCount += 1;
        }
    }
    assert.equal(literalCallCount, callCount, 'every call names its operation with a string literal, so this list is complete');
    assert.deepEqual(Array.from(sendNames).sort(), operationsToGraphite.slice().sort());
    assert.equal(operationsToGraphite.length, 44);
    assert.equal(operationsFromGraphite.length + operationsToGraphite.length, 83);
});

test('an operation the runtime does not know is answered as unknownOperation, and an error in a handler as runtime', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await harness.send({ operation: 'no.such.operation' })),
            { failure: { kind: 'unknownOperation', message: 'The plugin runtime does not know “no.such.operation”.' } });
        assert.deepEqual(plain(await harness.send({})), { failure: { kind: 'unknownOperation', message: 'The plugin runtime does not know “undefined”.' } });

        harness.runtime.messageHandlers['test.throws'] = async () => { throw new Error('The handler broke.'); };
        assert.deepEqual(plain(await harness.send({ operation: 'test.throws' })), { failure: { kind: 'runtime', message: 'The handler broke.' } });
        delete harness.runtime.messageHandlers['test.throws'];
    } finally {
        harness.close();
    }
});

test('a handler that fails on the runtime\'s own state is answered as runtime with the engine\'s message', async () => {
    const harness = await startRuntime({ files: {}, isStarting: false });
    try {
        const answer = plain(await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'anything' }));
        assert.equal(answer.failure.kind, 'runtime', 'unloading before runtime.start has no plugin list to work on');
        assert.equal(typeof answer.failure.message, 'string');
        assert.deepEqual(Object.keys(answer), ['failure']);
        assert.deepEqual(Object.keys(answer.failure).sort(), ['kind', 'message']);
    } finally {
        harness.close();
    }
});

test('a failure from Graphite becomes a HostOperationError with its kind, and a missing file has the code ENOENT', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        harness.runtime.hostBridge.transport = async () => ({ failure: { kind: 'conflict', message: 'The file changed.' }, snapshot: { path: 'A.md' } });
        await assert.rejects(harness.runtime.hostBridge.send('vault.write', {}), (error) => {
            assert.equal(error.name, 'HostOperationError');
            assert.equal(error.kind, 'conflict');
            assert.equal(error.message, 'The file changed.');
            assert.equal(error.code, undefined);
            assert.deepEqual(plain(error.snapshot), { path: 'A.md' }, 'a refused editor change brings the note as it is now');
            return true;
        });
        harness.runtime.hostBridge.transport = async () => ({ failure: { kind: 'missing', message: 'Not there.' } });
        await assert.rejects(harness.runtime.hostBridge.send('vault.read', {}), (error) => {
            assert.equal(error.kind, 'missing');
            assert.equal(error.code, 'ENOENT');
            return true;
        });
        harness.runtime.hostBridge.transport = null;
        await assert.rejects(harness.runtime.hostBridge.send('vault.read', {}), (error) => error.kind === 'unavailable');
    } finally {
        harness.close();
    }
});

test('the runtime talks to Graphite through the message handler named graphitePlugins, and answers in JSON text are parsed', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text' } });
    try {
        assert.ok(harness.host.requests.some((message) => message.operation === 'vault.list'), 'the runtime read the vault through window.webkit.messageHandlers.graphitePlugins');
        assert.equal(typeof harness.runtime.receive, 'function', 'Graphite calls GraphitePluginRuntime.receive(message)');
        assert.equal(typeof harness.runtime.hostBridge.transport, 'function');

        // The connection script installs its transport only for a handler of that exact name.
        const connectionSource = fileSystem.readFileSync(path.join(runtimeFolder, 'community-plugin-runtime-host-connection.js'), 'utf8');
        const window = harness.window;
        const posted = [];
        harness.runtime.hostBridge.transport = null;
        window.webkit = { messageHandlers: { graphiteOther: { postMessage: (message) => { posted.push(message); return Promise.resolve({}); } } } };
        window.eval(connectionSource);
        assert.equal(harness.runtime.hostBridge.transport, null, 'a handler with another name is not used');

        window.webkit = { messageHandlers: { graphitePlugins: { postMessage: (message) => {
            posted.push(message);
            return Promise.resolve(message.operation === 'vault.stat' ? JSON.stringify({ stat: null }) : { isObject: true });
        } } } };
        window.eval(connectionSource);
        assert.deepEqual(plain(await harness.runtime.hostBridge.send('vault.stat', { path: 'X.md' })), { stat: null }, 'a JSON text answer is parsed');
        assert.deepEqual(plain(await harness.runtime.hostBridge.send('commands.changed', {})), { isObject: true }, 'an object answer is passed on');
        assert.deepEqual(plain(posted), [{ operation: 'vault.stat', path: 'X.md' }, { operation: 'commands.changed' }]);
    } finally {
        harness.close();
    }
});

test('the runtime page loads its scripts in the order index.html lists them, and some depend on the ones before', async () => {
    assert.deepEqual(runtimeScriptNames(), [
        'Vendor/moment.min.js', 'Vendor/js-yaml.min.js', 'Vendor/lucide.min.js', 'Vendor/codemirror-modules.min.js',
        'community-plugin-dom-extensions.js', 'community-plugin-runtime-foundation.js', 'community-plugin-runtime-vault.js',
        'community-plugin-runtime-metadata.js', 'community-plugin-runtime-workspace.js', 'community-plugin-runtime-interface.js',
        'community-plugin-runtime-settings.js', 'community-plugin-runtime-bases.js', 'community-plugin-runtime-plugins.js',
        'community-plugin-runtime-reading.js', 'community-plugin-runtime-host-connection.js',
    ]);

    const ordered = runtimeScriptNames();
    function loadScripts(scriptNames) {
        const virtualConsole = new VirtualConsole();
        const dom = new JSDOM('<!doctype html><html><head></head><body class="graphite-plugin-runtime"></body></html>', { runScripts: 'outside-only', url: 'https://graphite-plugins.test/', virtualConsole });
        const window = dom.window;
        if (!window.TextEncoder) window.TextEncoder = TextEncoder;
        if (!window.TextDecoder) window.TextDecoder = TextDecoder;
        if (!window.CSS) window.CSS = {};
        if (!window.CSS.escape) window.CSS.escape = (value) => String(value);
        try {
            for (const scriptName of scriptNames) window.eval(fileSystem.readFileSync(path.join(runtimeFolder, scriptName), 'utf8'));
            return null;
        } catch (error) {
            return { name: error.name, message: error.message };
        } finally {
            window.close();
        }
    }
    assert.equal(loadScripts(ordered), null, 'in the listed order, every script loads');
    const withoutFoundation = loadScripts(ordered.filter((name) => name !== 'community-plugin-runtime-foundation.js'));
    assert.equal(withoutFoundation.name, 'TypeError');
    assert.match(withoutFoundation.message, /obsidianModule/, 'the vault script reads what the foundation script creates');
    const withoutWorkspace = loadScripts(ordered.filter((name) => name !== 'community-plugin-runtime-workspace.js'));
    assert.equal(withoutWorkspace.name, 'TypeError');
    assert.match(withoutWorkspace.message, /Class extends value undefined/, 'the bases script extends a class the workspace script defines');
    const withoutInterface = loadScripts(ordered.filter((name) => name !== 'community-plugin-runtime-interface.js'));
    assert.equal(withoutInterface.name, 'TypeError');
    assert.match(withoutInterface.message, /Class extends value undefined/, 'the settings script extends a class the interface script defines');
    const withoutPlugins = loadScripts(ordered.filter((name) => name !== 'community-plugin-runtime-plugins.js'));
    assert.equal(withoutPlugins.name, 'TypeError', 'the reading script adds to what the plugins script creates');
});

test('plugins see API version 1.14.4, the host may override it at start, and requireApiVersion compares numerically by part', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { requireApiVersion } = harness.obsidian;
        assert.equal(harness.obsidian.apiVersion, '1.14.4');
        assert.equal(harness.runtime.compatibleApiVersion, '1.14.4');
        assert.equal(requireApiVersion('1.9.10'), true, '9 is less than 14 as numbers, though "9" sorts after "14" as text');
        assert.equal(requireApiVersion('1.15'), false);
        assert.equal(requireApiVersion('1.14.4'), true);
        assert.equal(requireApiVersion('1.14.5'), false);
        assert.equal(requireApiVersion('1.14'), true);
        assert.equal(requireApiVersion('1.14.4.1'), false);
        assert.equal(requireApiVersion('0.15.9'), true);
        assert.equal(requireApiVersion('2'), false);

        await harness.send({
            operation: 'runtime.start', compatibleApiVersion: '1.15.2',
            vault: { name: 'Test Vault', identifier: 'test-vault', configurationDirectory: '.obsidian', configuration: {}, corePlugins: [] },
            device: { isPhone: false }, appearance: 'light', recentFiles: [],
        });
        assert.equal(harness.obsidian.apiVersion, '1.15.2', 'the host\'s version replaces the default');
        assert.equal(requireApiVersion('1.15'), true);
        assert.equal(requireApiVersion('1.15.3'), false);
    } finally {
        harness.close();
    }
});

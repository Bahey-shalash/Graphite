// How the runtime names what a plugin registers and which plugin it blames: command
// identifiers and names, Obsidian protocol handlers, and the plugin an unsupported feature
// is reported for.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

function pluginSource(body) {
    return `"use strict";
var obsidian = require("obsidian");
${body}
module.exports = ExamplePlugin;`;
}

test('commands are identified as <plugin id>:<command id> and named <plugin name>: <command name> in commands.changed, with their declared hotkeys', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const manifest = { id: 'quick-add', name: 'QuickAdd', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };
        await installAndLoadPlugin(harness, { manifest, mainSource: pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.addCommand({ id: 'run', name: 'Run choice', icon: 'zap', callback: () => {}, hotkeys: [{ modifiers: ['Mod', 'Shift'], key: 'Q' }, { modifiers: ['Mod'] }] });
        this.addCommand({ id: 'insert', name: 'Insert here', editorCallback: () => {} });
        this.addCommand({ id: 'maybe', name: 'Maybe', editorCheckCallback: () => false });
    }
}`) });
        await settle();
        const lists = harness.host.notificationsOf('commands.changed');
        assert.deepEqual(plain(lists.at(-1)), {
            operation: 'commands.changed',
            commands: [
                // Declared hotkeys pass to Graphite's shortcut list; one without a key is left out.
                { commandIdentifier: 'quick-add:run', name: 'QuickAdd: Run choice', icon: 'zap', needsEditor: false, pluginIdentifier: 'quick-add',
                    hotkeys: [{ modifiers: ['Mod', 'Shift'], key: 'Q' }] },
                { commandIdentifier: 'quick-add:insert', name: 'QuickAdd: Insert here', icon: null, needsEditor: true, pluginIdentifier: 'quick-add', hotkeys: [] },
                { commandIdentifier: 'quick-add:maybe', name: 'QuickAdd: Maybe', icon: null, needsEditor: true, pluginIdentifier: 'quick-add', hotkeys: [] },
            ],
        });
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'quick-add:run' })), { outcome: 'ran' });
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'run' })), { outcome: 'missing' }, 'the plugin\'s own command identifier is not enough');
    } finally {
        harness.close();
    }
});

test('an Obsidian protocol handler receives its action and the link\'s parameters with their original names', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const manifest = { id: 'advanced-uri', name: 'Advanced URI', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };
        await installAndLoadPlugin(harness, { manifest, mainSource: pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.received = [];
        this.registerObsidianProtocolHandler('advanced-uri', async (parameters) => { this.received.push(parameters); });
    }
}`) });
        const answer = plain(await harness.send({ operation: 'protocol.open', action: 'advanced-uri', parameters: { vault: 'V', Key: '1', filepath: 'A b.md' } }));
        assert.deepEqual(answer, { isHandled: true });
        assert.deepEqual(plain(harness.app.plugins.getPlugin('advanced-uri').received), [{ action: 'advanced-uri', vault: 'V', Key: '1', filepath: 'A b.md' }]);
        assert.deepEqual(plain(await harness.send({ operation: 'protocol.open', action: 'unregistered', parameters: {} })), { isHandled: false });
        assert.deepEqual(plain(await harness.send({ operation: 'protocol.open', action: 'Advanced-URI', parameters: {} })), { isHandled: false }, 'Graphite lowercases the action before sending, so the runtime compares exactly');
        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'advanced-uri' });
        assert.deepEqual(plain(await harness.send({ operation: 'protocol.open', action: 'advanced-uri', parameters: {} })), { isHandled: false }, 'unloading the plugin removes its handler');
    } finally {
        harness.close();
    }
});

test('a feature Graphite lacks is reported once for each plugin and feature, naming the plugin from its source name', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.addCommand({ id: 'duplicate', name: 'Duplicate', callback: () => {
            for (let attempt = 0; attempt < 2; attempt += 1) {
                try { this.app.workspace.duplicateLeaf(); } catch (error) { this.lastError = error; }
            }
        } });
    }
}`);
        const manifestOf = (identifier, name) => ({ id: identifier, name, version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' });
        await installAndLoadPlugin(harness, { manifest: manifestOf('first-plugin', 'First'), mainSource: source });
        await installAndLoadPlugin(harness, { manifest: manifestOf('second-plugin', 'Second'), mainSource: source });
        for (const commandIdentifier of ['first-plugin:duplicate', 'first-plugin:duplicate', 'second-plugin:duplicate']) {
            await harness.send({ operation: 'command.run', commandIdentifier });
        }
        await settle();
        const reports = plain(harness.host.notificationsOf('plugin.unsupportedFeature')).filter((report) => report.featureName === 'Workspace.duplicateLeaf');
        assert.deepEqual(reports, [
            { operation: 'plugin.unsupportedFeature', pluginIdentifier: 'first-plugin', featureName: 'Workspace.duplicateLeaf' },
            { operation: 'plugin.unsupportedFeature', pluginIdentifier: 'second-plugin', featureName: 'Workspace.duplicateLeaf' },
        ]);
        const thrown = harness.app.plugins.getPlugin('first-plugin').lastError;
        assert.equal(thrown.name, 'UnsupportedFeatureError');
        assert.equal(thrown.featureName, 'Workspace.duplicateLeaf');
        assert.equal(thrown.message, 'Workspace.duplicateLeaf is not supported in Graphite yet.');
    } finally {
        harness.close();
    }
});

test('code is attributed to a plugin by the source name plugin:<id>/main.js or by a blob address Graphite registered', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const runtime = harness.runtime;
        assert.equal(runtime.pluginIdentifierOfSource('plugin:my-plugin/main.js'), 'my-plugin');
        assert.equal(runtime.pluginIdentifierInStack('Error\n    at run (plugin:my-plugin/main.js:3:9)\n    at other (somewhere.js:1:1)'), 'my-plugin');
        assert.equal(runtime.pluginIdentifierOfSource('community-plugin-runtime-vault.js'), null);
        assert.equal(runtime.pluginIdentifierInStack('Error\n    at run (community-plugin-runtime-vault.js:3:9)'), null);

        runtime.pluginIdentifiersBySourceAddress.set('blob:graphite-plugins://runtime/abc-123', 'blob-plugin');
        assert.equal(runtime.pluginIdentifierOfSource('blob:graphite-plugins://runtime/abc-123'), 'blob-plugin');
        assert.equal(runtime.pluginIdentifierOfSource('blob:graphite-plugins://runtime/other'), null);
        assert.equal(runtime.pluginIdentifierInStack('Error\n    at run (blob:graphite-plugins://runtime/abc-123:5:7)\n    at x (y.js:1:1)'), 'blob-plugin');
        assert.equal(runtime.pluginIdentifierInStack('run@blob:graphite-plugins://runtime/abc-123:5:7\nx@y.js:1:1'), 'blob-plugin', 'WebKit\'s stack format');
    } finally {
        harness.close();
    }
});

// Conventions of Obsidian's app that plugins rely on without the API declaring them, found
// by trying a sample of community plugins in Graphite (Docs/Community-plugins.md, "A sweep
// of the directory"). Each test names the plugins that needed it.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle, waitUntil } = require('../support/runtime-harness');

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

test('a plugin compiled to ES5 extends Obsidian\'s classes with _super.call(this, …) || this', async () => {
    // TypeScript's ES5 output, as Mind Map and Contextual Typography ship it.
    const source = `"use strict";
var __extends = (this && this.__extends) || (function () {
    var extendStatics = function (d, b) { extendStatics = Object.setPrototypeOf || function (d, b) { for (var p in b) if (Object.prototype.hasOwnProperty.call(b, p)) d[p] = b[p]; }; return extendStatics(d, b); };
    return function (d, b) { extendStatics(d, b); function __() { this.constructor = d; } d.prototype = b === null ? Object.create(b) : (__.prototype = b.prototype, new __()); };
})();
var obsidian = require("obsidian");
var ExampleChild = (function (_super) {
    __extends(ExampleChild, _super);
    function ExampleChild(containerEl, label) { var _this = _super.call(this, containerEl) || this; _this.label = label; return _this; }
    ExampleChild.prototype.onload = function () { this.containerEl.setText(this.label); };
    return ExampleChild;
}(obsidian.MarkdownRenderChild));
var ExamplePlugin = (function (_super) {
    __extends(ExamplePlugin, _super);
    function ExamplePlugin() { return _super !== null && _super.apply(this, arguments) || this; }
    ExamplePlugin.prototype.onload = function () {
        this.child = new ExampleChild(document.createElement('div'), 'drawn');
        this.addChild(this.child);
        this.addCommand({ id: 'say', name: 'Say', callback: function () {} });
    };
    return ExamplePlugin;
}(obsidian.Plugin));
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        const answer = plain(await installAndLoadPlugin(harness, { manifest, mainSource: source }));
        assert.deepEqual(answer, { isLoaded: true });
        const plugin = harness.app.plugins.plugins.example;
        assert.equal(plugin.manifest.id, 'example', 'the plugin was constructed with the app and its manifest');
        assert.equal(plugin.child.containerEl.textContent, 'drawn', 'the child was loaded with its parent');
        assert.equal(plugin.child.label, 'drawn');
        assert.ok(plugin instanceof harness.window.GraphitePluginRuntime.obsidianModule.Plugin);
        assert.equal(plain(harness.host.notificationsOf('commands.changed').at(-1).commands.map((command) => command.name))[0], 'Example: Say');
    } finally {
        harness.close();
    }
});

test('workspace containers give their window and document, and plugin setting tabs their name', async () => {
    const source = `"use strict";
var obsidian = require("obsidian");
class ExampleTab extends obsidian.PluginSettingTab { display() {} }
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        const leaves = [];
        this.app.workspace.iterateAllLeaves((leaf) => leaves.push(leaf));
        // Colored Tags styles each container's document.
        this.containerDocument = this.app.workspace.rootSplit.getContainer().doc;
        this.containerWindow = this.app.workspace.rootSplit.win;
        this.tab = new ExampleTab(this.app, this);
        this.hotkeys = this.app.hotkeyManager.getHotkeys('example:say');
        this.theme = this.app.getTheme();
        window.CodeMirrorAdapter.commands.save = () => {};
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        const plugin = harness.app.plugins.plugins.example;
        assert.equal(plugin.containerDocument, harness.window.document);
        assert.equal(plugin.containerWindow, harness.window);
        assert.equal(plugin.tab.name, 'Example', 'Obsidian names a plugin\'s tab after the plugin; Smart Connections renames it');
        assert.equal(plugin.tab.id, 'example');
        assert.deepEqual(plain(plugin.hotkeys), [], 'Editing Toolbar reads the hotkeys of its commands');
        assert.ok(['obsidian', 'moonstone'].includes(plugin.theme));
    } finally {
        harness.close();
    }
});

test('a view opened before its type is registered appears once the plugin registers it', async () => {
    // Spaced Repetition opens its review queue in the sidebar, then registers the view.
    const source = `"use strict";
var obsidian = require("obsidian");
class QueueView extends obsidian.ItemView {
    getViewType() { return 'example-queue'; }
    getDisplayText() { return 'Queue'; }
    async onOpen() { this.contentEl.setText('the queue'); }
}
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.app.workspace.onLayoutReady(async () => {
            const leaf = this.app.workspace.getRightLeaf(false);
            await leaf.setViewState({ type: 'example-queue', active: true });
            this.leafBeforeRegistering = leaf.view.getViewType();
            this.registerView('example-queue', (viewLeaf) => new QueueView(viewLeaf));
            this.registeredCreator = this.app.viewRegistry.viewByType['example-queue'];
        });
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await harness.send({ operation: 'plugins.layoutReady' });
        const plugin = harness.app.plugins.plugins.example;
        await waitUntil(() => harness.app.workspace.getLeavesOfType('example-queue').length === 1);
        assert.equal(plugin.leafBeforeRegistering, 'empty');
        assert.equal(typeof plugin.registeredCreator, 'function', 'the view registry lists the registered type');
        assert.equal(harness.app.workspace.getLeavesOfType('example-queue')[0].view.contentEl.textContent, 'the queue');
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), []);
    } finally {
        harness.close();
    }
});

test('two quick saves of a plugin\'s settings both succeed and the last one stays', async () => {
    // Day Planner saves its settings again before the first save is done.
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        await this.saveData({ round: 0 });
        const first = this.saveData({ round: 1 });
        const second = this.saveData({ round: 2 });
        await Promise.all([first, second]);
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await settle();
        assert.deepEqual(JSON.parse(harness.readVaultFile('.obsidian/plugins/example/data.json')), { round: 2 });
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.writeConflict')), []);
    } finally {
        harness.close();
    }
});

test('Obsidian\'s own settings files read as empty settings in a vault Obsidian never opened', async () => {
    // Make.md reads app.json as it loads.
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.appSettings = JSON.parse(await this.app.vault.adapter.read(this.app.vault.configDir + '/app.json'));
        try { await this.app.vault.adapter.read(this.app.vault.configDir + '/missing.json'); } catch (error) { this.missingKind = error.kind; }
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        const plugin = harness.app.plugins.plugins.example;
        assert.deepEqual(plain(plugin.appSettings), {});
        assert.equal(plugin.missingKind, 'missing', 'other missing files still fail');
        assert.equal(harness.vaultFileExists('.obsidian/app.json'), false, 'reading writes nothing');
    } finally {
        harness.close();
    }
});

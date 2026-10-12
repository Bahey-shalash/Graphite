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

test('a code block that puts its own element in the block\'s place is shown as drawn', async () => {
    // Admonition replaces the element it is given (`el.replaceWith(admonition)`).
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.registerMarkdownCodeBlockProcessor('example-callout', (text, el) => {
            const callout = createDiv({ cls: 'callout', attr: { 'data-callout': 'note' } });
            callout.createDiv({ cls: 'callout-title', text: 'Title' });
            callout.createDiv({ cls: 'callout-content', text });
            el.replaceWith(callout);
        });
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: { 'Note.md': '```example-callout\nBody\n```\n' } });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        const answer = plain(await harness.send({ operation: 'codeBlock.render', width: 700, blockIdentifier: 'replaced', language: 'example-callout', source: 'Body', sourcePath: 'Note.md' }));
        assert.equal(answer.isDrawn, true);
        assert.match(answer.html, /^<div class="callout" data-callout="note"><div class="callout-title">Title<\/div><div class="callout-content">Body<\/div><\/div>$/);
    } finally {
        harness.close();
    }
});

test('a notice\'s links and buttons are offered with it, and a tap on one clicks it', async () => {
    // Smart Connections asks to "Load Smart Environment" from a notice on mobile.
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        const message = document.createDocumentFragment();
        message.append('Loading deferred on mobile.');
        const button = document.createElement('button');
        button.textContent = 'Load now';
        button.addEventListener('click', () => { this.loadedFromNotice = true; });
        message.append(button);
        new obsidian.Notice(message, 0);
        const plain = new obsidian.Notice('Click me', 0);
        plain.noticeEl.addEventListener('click', () => { this.noticeClicked = true; });
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await settle();
        const shown = plain(harness.host.notificationsOf('notice.show'));
        assert.deepEqual(shown.map((notice) => [notice.message, notice.actions]), [['Loading deferred on mobile.Load now', ['Load now']], ['Click me', []]]);
        assert.deepEqual(plain(await harness.send({ operation: 'notice.tap', noticeIdentifier: shown[0].noticeIdentifier, actionIndex: 0 })), { isHandled: true });
        assert.deepEqual(plain(await harness.send({ operation: 'notice.tap', noticeIdentifier: shown[1].noticeIdentifier })), { isHandled: true });
        const plugin = harness.app.plugins.plugins.example;
        assert.equal(plugin.loadedFromNotice, true);
        assert.equal(plugin.noticeClicked, true);
        assert.deepEqual(plain(harness.host.notificationsOf('notice.hide').map((notice) => notice.noticeIdentifier)), shown.map((notice) => notice.noticeIdentifier));
    } finally {
        harness.close();
    }
});

test('the adapter takes "/" for the vault\'s root, and menus have Obsidian\'s element', async () => {
    // isomorphic-git (Git on mobile) asks for "/"; Highlightr styles its menu's element.
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.rootExists = await this.app.vault.adapter.exists('/');
        this.rootStat = await this.app.vault.adapter.stat('/');
        const menu = new obsidian.Menu();
        menu.dom.addClass('example-menu');
        this.menuClass = menu.dom.className;
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: { 'Note.md': 'x\n' } });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        const plugin = harness.app.plugins.plugins.example;
        assert.equal(plugin.rootExists, true);
        assert.equal(plugin.rootStat && plugin.rootStat.type, 'folder');
        assert.match(plugin.menuClass, /example-menu/);
    } finally {
        harness.close();
    }
});

test('Obsidian 1.13\'s setting pages and its undocumented Setting rows work on the plugin panel', async () => {
    // Obsidian's own Importer walks its steps with setting pages and lists formats with them.
    const source = `"use strict";
var obsidian = require("obsidian");
class StepPage extends obsidian.SettingPage {
    display() { this.containerEl.empty(); new obsidian.Setting(this.containerEl).setName('Choose files').setIcon('lucide-plus').setAction(() => { this.plugin.chose = true; }); }
}
class ExampleTab extends obsidian.PluginSettingTab {
    display() {
        this.containerEl.empty();
        const group = new obsidian.SettingGroup(this.containerEl).addClass('mod-list');
        for (const format of ['Markdown', 'Notion']) {
            new obsidian.Setting(group.listEl).setName(format).setNavigable(() => {
                const page = new StepPage(); page.plugin = this.plugin; page.title = 'Import from ' + format;
                this.app.setting.openPage(page);
            });
        }
    }
}
class ExamplePlugin extends obsidian.Plugin { onload() { this.addSettingTab(new ExampleTab(this.app, this)); } }
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'example' });
        const document = harness.window.document;
        const rows = Array.from(document.querySelectorAll('.setting-group.mod-list .setting-item.mod-navigable'));
        assert.deepEqual(rows.map((row) => row.querySelector('.setting-item-name').textContent), ['Markdown', 'Notion']);
        rows[0].click();
        const page = document.querySelector('.setting-page');
        assert.ok(page, 'the step page is shown');
        assert.equal(page.querySelector('.setting-page-title').textContent, 'Import from Markdown');
        page.querySelector('.setting-item.mod-clickable').click();
        assert.equal(harness.app.plugins.plugins.example.chose, true);
        assert.ok(page.querySelector('.setting-item-icon svg'), 'the row has its icon');
        page.querySelector('.setting-page-back').click();
        assert.equal(document.querySelector('.setting-page'), null, 'Back closes the page');
        assert.equal(rows[0].isConnected && getComputedDisplay(rows[0].closest('.vertical-tab-content')), '', 'the tab is shown again');
    } finally {
        harness.close();
    }
    function getComputedDisplay(element) { return element ? element.style.display : 'missing'; }
});

test('a note opened in a leaf goes through setViewState, which plugins patch, and paths have a full form', async () => {
    // Excalidraw patches WorkspaceLeaf.prototype.setViewState; ReadItLater measures getFullPath.
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        const original = obsidian.WorkspaceLeaf.prototype.setViewState;
        const plugin = this;
        obsidian.WorkspaceLeaf.prototype.setViewState = function (state, eState) { plugin.seen = state; return original.call(this, state, eState); };
        this.register(() => { obsidian.WorkspaceLeaf.prototype.setViewState = original; });
        await this.app.workspace.getLeaf(false).openFile(this.app.vault.getFileByPath('Note.md'));
        this.fullPath = this.app.vault.adapter.getFullPath('Folder/Note.md');
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: { 'Note.md': 'x\n' } });
    try {
        await harness.waitForMetadata();
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        const plugin = harness.app.plugins.plugins.example;
        assert.deepEqual(plain(plugin.seen), { type: 'markdown', state: { file: 'Note.md' } });
        assert.equal(plain(harness.host.openedFiles).at(-1).path, 'Note.md');
        assert.match(plugin.fullPath, /\/Folder\/Note\.md$/);
    } finally {
        harness.close();
    }
});

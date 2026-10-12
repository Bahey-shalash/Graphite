'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

/// A plugin as a bundler leaves it: CommonJS, with `obsidian` left to `require`.
function pluginSource(body) {
    return `"use strict";
var obsidian = require("obsidian");
${body}
module.exports = ExamplePlugin;`;
}

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

test('a plugin loads, keeps its settings in data.json and registers commands', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        const stored = await this.loadData();
        this.loadedGreeting = stored.greeting;
        this.settings = Object.assign({ greeting: 'hello' }, stored);
        this.addCommand({ id: 'say', name: 'Say hello', callback: () => new obsidian.Notice(this.settings.greeting) });
        this.addCommand({ id: 'never', name: 'Never available', checkCallback: (checking) => false });
        this.settings.greeting = 'saved';
        await this.saveData(this.settings);
    }
}`);
        const answer = await installAndLoadPlugin(harness, { manifest, mainSource: source, data: { greeting: 'from disk' } });
        assert.deepEqual(plain(answer), { isLoaded: true });
        assert.deepEqual(JSON.parse(harness.readVaultFile('.obsidian/plugins/example/data.json')), { greeting: 'saved' });
        assert.equal(harness.readVaultFile('.obsidian/plugins/example/data.json'), '{\n  "greeting": "saved"\n}', 'data.json is written as Obsidian writes it');
        await settle();
        const commandLists = harness.host.notificationsOf('commands.changed');
        assert.deepEqual(plain(commandLists.at(-1).commands.map((command) => [command.commandIdentifier, command.name, command.needsEditor])), [
            ['example:say', 'Example: Say hello', false], ['example:never', 'Example: Never available', false],
        ]);
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'example:say' })), { outcome: 'ran' });
        assert.equal(harness.app.plugins.getPlugin('example').loadedGreeting, 'from disk');
        assert.equal(harness.host.notificationsOf('notice.show').at(-1).message, 'saved');
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'example:never' })), { outcome: 'unavailable' });
    } finally {
        harness.close();
    }
});

test('unloading a plugin removes its commands, ribbon actions, views and styles', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = pluginSource(`
class ExampleView extends obsidian.ItemView {
    getViewType() { return 'example-view'; }
    getDisplayText() { return 'Example view'; }
    async onOpen() { this.contentEl.createEl('p', { text: 'inside the view' }); }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerView('example-view', (leaf) => new ExampleView(leaf));
        this.addRibbonIcon('dice', 'Open example view', async () => {
            const leaf = this.app.workspace.getRightLeaf(false);
            await leaf.setViewState({ type: 'example-view', active: true });
        });
        this.addCommand({ id: 'go', name: 'Go', callback: () => {} });
    }
}`);
        await installAndLoadPlugin(harness, { manifest, mainSource: source, styles: '.example { color: red; }' });
        await settle();
        assert.ok(harness.window.document.querySelector('style[data-graphite-plugin="example"]'));
        const ribbon = harness.host.notificationsOf('ribbon.changed').at(-1).items;
        assert.deepEqual(plain(ribbon.map((item) => [item.title, item.icon])), [['Open example view', 'dice']]);
        assert.deepEqual(plain(await harness.send({ operation: 'ribbon.run', ribbonIdentifier: ribbon[0].ribbonIdentifier })), { outcome: 'ran' });
        await settle();
        assert.equal(harness.window.document.querySelector('.graphite-plugin-surface p').textContent, 'inside the view');
        assert.equal(harness.host.notificationsOf('surface.present').at(-1).title, 'Example view');
        assert.deepEqual(plain(harness.host.notificationsOf('views.changed').at(-1).views.map((view) => view.title)), ['Example view']);
        assert.ok(harness.runtime.ribbon.items[0].element.querySelector('svg.lucide-dice-5'), 'the ribbon action has Obsidian\'s “dice” icon from Lucide');

        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'example' });
        await settle();
        assert.equal(harness.window.document.querySelector('style[data-graphite-plugin="example"]'), null);
        assert.deepEqual(plain(harness.host.notificationsOf('commands.changed').at(-1).commands), []);
        assert.deepEqual(plain(harness.host.notificationsOf('ribbon.changed').at(-1).items), []);
        assert.equal(harness.window.document.querySelector('.graphite-plugin-surface p'), null);
        assert.equal(harness.app.workspace.viewCreatorsByType.has('example-view'), false);
    } finally {
        harness.close();
    }
});

test('a plugin that needs Node.js fails to load and says why', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const nodeSource = `var fs = require("fs"); class ExamplePlugin extends require("obsidian").Plugin {}; module.exports = ExamplePlugin;`;
        const nodeAnswer = plain(await installAndLoadPlugin(harness, { manifest, mainSource: nodeSource }));
        assert.equal(nodeAnswer.isLoaded, false);
        assert.equal(nodeAnswer.missingModule, 'fs');
        assert.match(nodeAnswer.errorMessage, /only Obsidian's desktop app provides/);
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature').map((notification) => [notification.pluginIdentifier, notification.featureName])), [['example', 'Module “fs”']]);
    } finally {
        harness.close();
    }
});

test('CodeMirror is the real library, and editor extensions are reported as not running', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
var state = require("@codemirror/state");
var view = require("@codemirror/view");
var language = require("@codemirror/language");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        const field = state.StateField.define({ create: () => 0, update: (value) => value + 1 });
        this.registerEditorExtension([field, view.ViewPlugin.fromClass(class { update() {} })]);
        this.documentLength = state.EditorState.create({ doc: 'hello', extensions: [field] }).doc.length;
        this.hasLanguageSupport = typeof language.syntaxTree === 'function';
    }
}
module.exports = ExamplePlugin;`;
        const answer = plain(await installAndLoadPlugin(harness, { manifest: Object.assign({}, manifest, { id: 'editor-example' }), mainSource: source }));
        assert.deepEqual(answer, { isLoaded: true });
        const plugin = harness.app.plugins.getPlugin('editor-example');
        assert.equal(plugin.documentLength, 5);
        assert.equal(plugin.hasLanguageSupport, true);
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature').map((notification) => [notification.pluginIdentifier, notification.featureName])), [['editor-example', 'CodeMirror editor extensions']]);
        const unknownSource = `var legacy = require("@codemirror/legacy-modes"); module.exports = class extends require("obsidian").Plugin {};`;
        const unknownAnswer = plain(await installAndLoadPlugin(harness, { manifest: Object.assign({}, manifest, { id: 'legacy' }), mainSource: unknownSource }));
        assert.equal(unknownAnswer.isLoaded, false);
        assert.match(unknownAnswer.errorMessage, /does not provide to plugins/);
    } finally {
        harness.close();
    }
});

test('a plugin whose onload throws is unloaded and reported', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.addCommand({ id: 'leftover', name: 'Leftover', callback: () => {} });
        throw new Error('setup failed');
    }
}`);
        const answer = plain(await installAndLoadPlugin(harness, { manifest, mainSource: source }));
        assert.equal(answer.isLoaded, false);
        assert.equal(answer.errorMessage, 'setup failed');
        assert.match(answer.stack, /plugin:example\/main\.js/);
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('commands.changed').at(-1).commands), []);
        assert.equal(harness.app.plugins.getPlugin('example'), null);
    } finally {
        harness.close();
    }
});

test('a plugin\'s settings tab is drawn on the plugin panel with Obsidian\'s controls', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = pluginSource(`
class ExampleSettingTab extends obsidian.PluginSettingTab {
    display() {
        const { containerEl } = this;
        containerEl.empty();
        new obsidian.Setting(containerEl).setName('Greeting').setDesc('What to say').addText((text) => text.setValue(this.plugin.settings.greeting).onChange(async (value) => {
            this.plugin.settings.greeting = value;
            await this.plugin.saveData(this.plugin.settings);
        }));
        new obsidian.Setting(containerEl).setName('Loud').addToggle((toggle) => toggle.setValue(false).onChange((value) => { this.plugin.settings.isLoud = value; }));
        new obsidian.Setting(containerEl).setName('Style').addDropdown((dropdown) => dropdown.addOptions({ plain: 'Plain', fancy: 'Fancy' }).setValue('fancy'));
        new obsidian.Setting(containerEl).setName('Volume').addSlider((slider) => slider.setLimits(0, 10, 1).setValue(3).setDynamicTooltip());
        new obsidian.Setting(containerEl).addButton((button) => button.setButtonText('Reset').setCta().onClick(() => { this.plugin.settings.greeting = 'reset'; }));
    }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.settings = { greeting: 'hello', isLoud: false };
        this.addSettingTab(new ExampleSettingTab(this.app, this));
    }
}`);
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        assert.deepEqual(plain(await harness.send({ operation: 'settings.show', pluginIdentifier: 'example' })), { hasSettingTab: true });
        const document = harness.window.document;
        const names = Array.from(document.querySelectorAll('.graphite-plugin-surface .setting-item-name'), (element) => element.textContent);
        assert.deepEqual(names, ['Greeting', 'Loud', 'Style', 'Volume', '']);
        const textInput = document.querySelector('.graphite-plugin-surface input[type="text"]');
        assert.equal(textInput.value, 'hello');
        textInput.value = 'typed';
        textInput.dispatchEvent(new harness.window.Event('input'));
        await settle();
        assert.deepEqual(JSON.parse(harness.readVaultFile('.obsidian/plugins/example/data.json')), { greeting: 'typed', isLoud: false });
        document.querySelector('.graphite-plugin-surface .checkbox-container').dispatchEvent(new harness.window.MouseEvent('click', { bubbles: true }));
        assert.equal(harness.app.plugins.getPlugin('example').settings.isLoud, true);
        assert.equal(document.querySelector('.graphite-plugin-surface select').value, 'fancy');
        assert.equal(document.querySelector('.graphite-plugin-surface .slider-value').textContent, '3');
        document.querySelector('.graphite-plugin-surface button.mod-cta').click();
        assert.equal(harness.app.plugins.getPlugin('example').settings.greeting, 'reset');
        await harness.send({ operation: 'surface.closed' });
        assert.equal(document.querySelector('.graphite-plugin-surface .setting-item'), null);
    } finally {
        harness.close();
    }
});

test('modals and suggestion lists open on the plugin panel and close it again', async () => {
    const harness = await startRuntime({ files: { 'Alpha.md': '', 'Beta.md': '' } });
    try {
        const source = pluginSource(`
class FilePicker extends obsidian.FuzzySuggestModal {
    getItems() { return this.app.vault.getMarkdownFiles(); }
    getItemText(file) { return file.basename; }
    onChooseItem(file) { this.app.chosenFileForTest = file.path; }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.addCommand({ id: 'pick', name: 'Pick a file', callback: () => new FilePicker(this.app).open() });
        this.addCommand({ id: 'confirm', name: 'Confirm', callback: () => {
            const modal = new obsidian.Modal(this.app);
            modal.setTitle('Are you sure?');
            modal.contentEl.createEl('p', { text: 'Body' });
            modal.open();
        } });
    }
}`);
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        await harness.send({ operation: 'command.run', commandIdentifier: 'example:confirm' });
        const document = harness.window.document;
        assert.equal(document.querySelector('.modal .modal-title').textContent, 'Are you sure?');
        assert.equal(harness.host.notificationsOf('surface.present').at(-1).title, 'Are you sure?');
        document.querySelector('.modal-close-button').click();
        assert.equal(document.querySelector('.modal'), null);
        assert.equal(harness.host.notificationsOf('surface.dismiss').length, 1);

        await harness.send({ operation: 'command.run', commandIdentifier: 'example:pick' });
        await settle();
        const input = document.querySelector('.prompt-input');
        input.value = 'bet';
        input.dispatchEvent(new harness.window.Event('input'));
        await settle();
        const suggestions = Array.from(document.querySelectorAll('.suggestion-item'), (element) => element.textContent);
        assert.deepEqual(suggestions, ['Beta']);
        document.dispatchEvent(new harness.window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        assert.equal(harness.app.chosenFileForTest, 'Beta.md');
        assert.equal(document.querySelector('.prompt'), null);
    } finally {
        harness.close();
    }
});

test('a plugin menu is shown by Graphite and runs the chosen item', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.addCommand({ id: 'menu', name: 'Menu', callback: () => {
            const menu = new obsidian.Menu();
            menu.addItem((item) => item.setTitle('First').setIcon('pencil').onClick(() => { this.app.chosenForTest = 'first'; }));
            menu.addSeparator();
            menu.addItem((item) => item.setTitle('Second').onClick(() => { this.app.chosenForTest = 'second'; }));
            menu.showAtPosition({ x: 0, y: 0 });
        } });
    }
}`);
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        harness.host.menuChoice = 1;
        await harness.send({ operation: 'command.run', commandIdentifier: 'example:menu' });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('menu.show').at(-1).items.map((item) => item.title)), ['First', 'Second']);
        assert.equal(harness.app.chosenForTest, 'second');
    } finally {
        harness.close();
    }
});

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'utility', name: 'Utility', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

test('Obsidian\'s helper functions behave as plugins expect', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const obsidian = harness.obsidian;
        assert.equal(obsidian.normalizePath('//Folder\\\\Sub//Note.md/'), 'Folder/Sub/Note.md');
        assert.equal(obsidian.normalizePath(''), '/');
        assert.equal(obsidian.normalizePath('A\u00A0B'), 'A B');
        assert.deepEqual(plain(obsidian.parseLinktext('Note#Heading#Sub')), { path: 'Note', subpath: '#Heading#Sub' });
        assert.equal(obsidian.getLinkpath('Folder/Note#^block'), 'Folder/Note');
        assert.deepEqual(plain(obsidian.parseFrontMatterAliases({ alias: 'One, Two' })), ['One', 'Two']);
        assert.deepEqual(plain(obsidian.parseFrontMatterTags({ tags: 'a b,c' })), ['#a', '#b', '#c']);
        assert.equal(obsidian.parseFrontMatterEntry({ Title: 'x' }, /title/i), 'x');
        assert.deepEqual(plain(obsidian.getFrontMatterInfo('---\na: 1\n---\nBody')), { exists: true, frontmatter: 'a: 1\n', from: 4, to: 9, contentStart: 13 });
        assert.deepEqual(plain(obsidian.parseYaml('date: 2024-05-01\nflag: true\nlist: [1, two]')), { date: '2024-05-01', flag: true, list: [1, 'two'] }, 'dates stay text, as in Obsidian\'s properties');
        assert.equal(obsidian.stringifyYaml({ a: [1] }), 'a:\n  - 1\n');
        const buffer = obsidian.base64ToArrayBuffer(obsidian.arrayBufferToBase64(new Uint8Array([0, 255, 16]).buffer));
        assert.deepEqual(Array.from(new Uint8Array(buffer)), [0, 255, 16]);
        assert.equal(obsidian.arrayBufferToHex(new Uint8Array([1, 171]).buffer), '01ab');
        assert.deepEqual(Array.from(new Uint8Array(obsidian.hexToArrayBuffer('01ab'))), [1, 171]);
        const fuzzy = obsidian.prepareFuzzySearch('lct');
        assert.ok(fuzzy('Lecture'));
        assert.equal(fuzzy('Notes'), null);
        assert.deepEqual(plain(obsidian.prepareSimpleSearch('fourier transform')('The Fourier transform').matches), [[4, 11], [12, 21]]);
        assert.equal(obsidian.htmlToMarkdown('<h2>Title</h2><p>Some <strong>bold</strong> and <a href="https://x.org">a link</a>.</p><ul><li>one</li><li>two</li></ul>'),
            '## Title\n\nSome **bold** and [a link](https://x.org).\n\n- one\n- two');
        const fragment = obsidian.sanitizeHTMLToDom('<p onclick="steal()">Hi<script>steal()</script><a href="javascript:steal()">x</a></p>');
        const container = harness.window.document.createElement('div');
        container.appendChild(fragment);
        assert.equal(container.innerHTML, '<p>Hi<a>x</a></p>');
        assert.equal(obsidian.Platform.isMobile, true);
        assert.equal(obsidian.Platform.isIosApp, true);
        assert.equal(obsidian.Platform.isDesktopApp, false);
        assert.equal(obsidian.requireApiVersion('1.4.0'), true);
        assert.equal(obsidian.requireApiVersion('99.0.0'), false);
        assert.equal(typeof obsidian.moment, 'function');
        assert.equal(obsidian.moment('2024-05-01').format('dddd'), 'Wednesday');
        let calls = 0;
        const debounced = obsidian.debounce(() => { calls += 1; }, 10);
        debounced(); debounced(); debounced();
        await new Promise((resolve) => setTimeout(resolve, 40));
        assert.equal(calls, 1);
    } finally {
        harness.close();
    }
});

test('requestUrl goes through Graphite and gives text, JSON and status', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        harness.host.networkResponder = (message) => {
            assert.equal(message.method, 'POST');
            assert.equal(Buffer.from(message.bodyBase64, 'base64').toString(), '{"q":1}');
            return { status: message.url.endsWith('/missing') ? 404 : 200, headers: { 'Content-Type': 'application/json' }, bodyBase64: Buffer.from('{"answer":42}').toString('base64') };
        };
        const response = await harness.obsidian.requestUrl({ url: 'https://api.example.com/ask', method: 'POST', body: '{"q":1}', contentType: 'application/json' });
        assert.equal(response.status, 200);
        assert.equal(response.text, '{"answer":42}');
        assert.deepEqual(plain(response.json), { answer: 42 });
        assert.equal(response.headers['content-type'], 'application/json');
        await assert.rejects(harness.obsidian.requestUrl({ url: 'https://api.example.com/missing', method: 'POST', body: '{"q":1}' }), /status 404/);
        const tolerated = await harness.obsidian.requestUrl({ url: 'https://api.example.com/missing', method: 'POST', body: '{"q":1}', throw: false });
        assert.equal(tolerated.status, 404);
    } finally {
        harness.close();
    }
});

test('unloading removes a plugin\'s events, intervals, DOM listeners and setting tab', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'x' } });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.app.counts = { modify: 0, interval: 0, click: 0 };
        this.registerEvent(this.app.vault.on('modify', () => { this.app.counts.modify += 1; }));
        this.registerInterval(window.setInterval(() => { this.app.counts.interval += 1; }, 5));
        this.registerDomEvent(document, 'click', () => { this.app.counts.click += 1; });
        this.addSettingTab(new (class extends obsidian.PluginSettingTab { display() { this.containerEl.createEl('p', { text: 'options' }); } })(this.app, this));
    }
}
module.exports = ExamplePlugin;`;
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        const app = harness.app;
        await app.vault.modify(app.vault.getFileByPath('Note.md'), 'y');
        harness.window.document.dispatchEvent(new harness.window.MouseEvent('click'));
        await new Promise((resolve) => setTimeout(resolve, 30));
        assert.equal(app.counts.modify, 1);
        assert.equal(app.counts.click, 1);
        assert.ok(app.counts.interval > 0);
        await settle();
        assert.equal(harness.host.notificationsOf('plugin.settingTabChanged').at(-1).hasSettingTab, true);

        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'utility' });
        const intervalsAtUnload = app.counts.interval;
        await app.vault.modify(app.vault.getFileByPath('Note.md'), 'z');
        harness.window.document.dispatchEvent(new harness.window.MouseEvent('click'));
        await new Promise((resolve) => setTimeout(resolve, 30));
        assert.deepEqual(plain(app.counts), { modify: 1, interval: intervalsAtUnload, click: 1 });
        await settle();
        assert.equal(harness.host.notificationsOf('plugin.settingTabChanged').at(-1).hasSettingTab, false);
        assert.deepEqual(plain(await harness.send({ operation: 'settings.show', pluginIdentifier: 'utility' })), { hasSettingTab: false });
    } finally {
        harness.close();
    }
});

test('file manager renames through Graphite and trashes as the vault says', async () => {
    const harness = await startRuntime({ files: { 'Folder/Note.md': 'x', 'Other.md': 'y' }, configuration: { newFileLocation: 'folder', newFileFolderPath: 'Folder' } });
    try {
        const app = harness.app;
        const note = app.vault.getFileByPath('Folder/Note.md');
        await app.fileManager.renameFile(note, 'Folder/Renamed.md');
        assert.equal(note.path, 'Folder/Renamed.md');
        assert.ok(harness.vaultFileExists('Folder/Renamed.md'));
        assert.equal(harness.host.notificationsOf('workspace.renameFile').length, 1, 'Graphite renames it, so links to it are updated');
        await app.fileManager.trashFile(app.vault.getFileByPath('Other.md'));
        assert.equal(app.vault.getFileByPath('Other.md'), null);
        assert.equal(harness.host.requests.filter((request) => request.operation === 'vault.remove').at(-1).method, 'vaultSetting');
        assert.equal(app.fileManager.getNewFileParent('Other.md').path, 'Folder');
    } finally {
        harness.close();
    }
});

test('declarative settings validate, persist and re-evaluate what is visible', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
class Tab extends obsidian.PluginSettingTab {
    getSettingDefinitions() {
        return [
            { name: 'Enabled', control: { type: 'toggle', key: 'isOn', defaultValue: false } },
            { name: 'Name', desc: 'Only when enabled', visible: () => this.plugin.settings.isOn === true,
              control: { type: 'text', key: 'name', validate: (value) => (value.length > 3 ? 'Too long' : undefined) } },
            { type: 'group', heading: 'More', items: [ { name: 'Count', control: { type: 'number', key: 'count', min: 0 } } ] },
        ];
    }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.settings = { isOn: false, name: 'abc', count: 1 };
        this.addSettingTab(new Tab(this.app, this));
    }
}
module.exports = ExamplePlugin;`;
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'utility' });
        const document = harness.window.document;
        const rows = Array.from(document.querySelectorAll('.graphite-plugin-surface .setting-item'));
        assert.deepEqual(rows.map((row) => row.querySelector('.setting-item-name').textContent), ['Enabled', 'Name', 'Count']);
        assert.equal(rows[1].style.display, 'none', 'hidden until enabled');
        assert.equal(document.querySelector('.setting-group-heading-text').textContent, 'More');
        rows[0].querySelector('.checkbox-container').dispatchEvent(new harness.window.MouseEvent('click', { bubbles: true }));
        await settle();
        assert.equal(rows[1].style.display, '', 'shown once the toggle is on');
        assert.deepEqual(JSON.parse(harness.readVaultFile('.obsidian/plugins/utility/data.json')), { isOn: true, name: 'abc', count: 1 });
        const nameInput = rows[1].querySelector('input');
        nameInput.value = 'longer';
        nameInput.dispatchEvent(new harness.window.Event('input'));
        await settle();
        assert.equal(rows[1].querySelector('.setting-item-error').textContent, 'Too long');
        assert.equal(JSON.parse(harness.readVaultFile('.obsidian/plugins/utility/data.json')).name, 'abc', 'an invalid value is not saved');
        const countInput = rows[2].querySelector('input');
        assert.equal(countInput.type, 'number');
        countInput.value = '5';
        countInput.dispatchEvent(new harness.window.Event('input'));
        await settle();
        assert.equal(JSON.parse(harness.readVaultFile('.obsidian/plugins/utility/data.json')).count, 5);
    } finally {
        harness.close();
    }
});

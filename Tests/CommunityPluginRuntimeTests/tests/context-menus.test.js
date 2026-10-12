// Plugins' items in Graphite's file and editor menus: Graphite asks for the items of a
// file's menu (`file-menu`, `files-menu`) or of the editor's menu at the cursor
// (`editor-menu`), shows them, and has the chosen one run.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'menus', name: 'Menus', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

const menuPlugin = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.chosen = [];
        this.registerEvent(this.app.workspace.on('file-menu', (menu, file, source) => {
            if (file instanceof obsidian.TFolder) {
                menu.addItem((item) => item.setTitle('New note in ' + file.name).setIcon('file-plus').onClick(() => this.chosen.push('folder:' + file.path)));
                return;
            }
            menu.addItem((item) => item.setTitle('Star ' + file.basename).setIcon('star').onClick(() => this.chosen.push('star:' + file.path + ':' + source)));
            menu.addItem((item) => item.setTitle('Disabled').setDisabled(true));
            menu.addSeparator();
            menu.addItem((item) => { item.setTitle('More'); const submenu = item.setSubmenu(); submenu.addItem((subitem) => subitem.setTitle('Inside').onClick(() => this.chosen.push('inside'))); });
        }));
        this.registerEvent(this.app.workspace.on('files-menu', (menu, files) => {
            menu.addItem((item) => item.setTitle('Star ' + files.length + ' files').onClick(() => this.chosen.push('files:' + files.map((file) => file.path).join(','))));
        }));
        this.registerEvent(this.app.workspace.on('editor-menu', (menu, editor, view) => {
            const token = editor.getClickableTokenAt(editor.getCursor());
            if (token && token.type === 'tag') menu.addItem((item) => item.setTitle('Rename ' + token.text).onClick(() => editor.replaceRange('#renamed', token.start, token.end)));
            menu.addItem((item) => item.setTitle('Uppercase selection').onClick(() => editor.replaceSelection(editor.getSelection().toUpperCase())));
        }));
    }
}
module.exports = ExamplePlugin;`;

test('a file\'s and a folder\'s menus get the items plugins add, and the chosen one runs', async () => {
    const harness = await startRuntime({ files: { 'Notes/Lecture.md': 'Text', 'Notes/Other.md': 'More' } });
    try {
        assert.deepEqual(plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'm0', paths: ['Notes/Lecture.md'] })), { items: [] }, 'no plugin, no items');
        await installAndLoadPlugin(harness, { manifest, mainSource: menuPlugin });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('menus.changed').at(-1)), { operation: 'menus.changed', hasFileMenuItems: true, hasEditorMenuItems: true });

        const fileMenu = plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'm1', paths: ['Notes/Lecture.md'] }));
        assert.deepEqual(fileMenu.items.map((item) => [item.position, item.title, item.isDisabled]), [[0, 'Star Lecture', false], [1, 'Disabled', true], [2, 'More › Inside', false]]);
        assert.equal(fileMenu.items[0].icon, 'star');
        assert.deepEqual(plain(await harness.send({ operation: 'menu.choose', menuIdentifier: 'm1', position: 0 })), { outcome: 'ran' });
        assert.deepEqual(plain(harness.app.plugins.getPlugin('menus').chosen), ['star:Notes/Lecture.md:file-explorer-context-menu']);
        assert.deepEqual(plain(await harness.send({ operation: 'menu.choose', menuIdentifier: 'm1', position: 0 })), { outcome: 'missing' }, 'a menu runs one item once');

        const folderMenu = plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'm2', paths: ['Notes'], source: 'file-explorer-context-menu' }));
        assert.deepEqual(folderMenu.items.map((item) => item.title), ['New note in Notes']);
        await harness.send({ operation: 'menu.dismiss', menuIdentifier: 'm2' });
        assert.deepEqual(plain(await harness.send({ operation: 'menu.choose', menuIdentifier: 'm2', position: 0 })), { outcome: 'missing' }, 'a dismissed menu runs nothing');

        const severalFiles = plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'm3', paths: ['Notes/Lecture.md', 'Notes/Other.md'] }));
        assert.deepEqual(severalFiles.items.map((item) => item.title), ['Star 2 files']);
        await harness.send({ operation: 'menu.choose', menuIdentifier: 'm3', position: 0 });
        assert.deepEqual(plain(harness.app.plugins.getPlugin('menus').chosen).at(-1), 'files:Notes/Lecture.md,Notes/Other.md');
    } finally {
        harness.close();
    }
});

test('the editor\'s menu gets items for the cursor, and a chosen item changes the note through Graphite', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'Study #physics today\n' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: menuPlugin });
        const onTag = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'e1', activeDocument: { path: 'Note.md', mode: 'source', editorSnapshot: harness.host.openNote('Note.md', 9) } }));
        assert.deepEqual(onTag.items.map((item) => item.title), ['Rename #physics', 'Uppercase selection']);
        assert.deepEqual(plain(await harness.send({ operation: 'menu.choose', menuIdentifier: 'e1', position: 0 })), { outcome: 'ran' });
        await settle();
        assert.equal(harness.host.editorSessions.get('Note.md').text, 'Study #renamed today\n');

        // The note as the editor now holds it, as Graphite saves it.
        harness.writeVaultFile('Note.md', harness.host.editorSessions.get('Note.md').text);
        const offTag = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'e2', activeDocument: { path: 'Note.md', mode: 'source', editorSnapshot: harness.host.openNote('Note.md', 0, 5) } }));
        assert.deepEqual(offTag.items.map((item) => item.title), ['Uppercase selection']);
        await harness.send({ operation: 'menu.choose', menuIdentifier: 'e2', position: 0 });
        await settle();
        assert.equal(harness.host.editorSessions.get('Note.md').text, 'STUDY #renamed today\n');

        harness.writeVaultFile('Slides.pdf', '%PDF-1.4');
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Slides.pdf', isReloadNeeded: true }] });
        const onPDF = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'e3', activeDocument: { path: 'Slides.pdf', mode: 'file' } }));
        assert.deepEqual(onPDF, { items: [] }, 'without a note\'s editor there is no editor menu');
    } finally {
        harness.close();
    }
});

test('getClickableTokenAt finds tags, internal links and web addresses as Obsidian does', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const editor = new harness.runtime.SnapshotEditor({ path: 'Note.md', snapshotIdentifier: 's', text: 'See [[Physics#Waves|waves]], #study/exam and https://example.com/a.\n', selectionAnchor: 0, selectionHead: 0 });
        assert.deepEqual(plain(editor.getClickableTokenAt({ line: 0, ch: 8 })), { type: 'internal-link', text: 'Physics#Waves', start: { line: 0, ch: 4 }, end: { line: 0, ch: 27 } });
        assert.equal(plain(editor.getClickableTokenAt({ line: 0, ch: 32 })).text, '#study/exam');
        assert.equal(plain(editor.getClickableTokenAt({ line: 0, ch: 50 })).text, 'https://example.com/a.');
        assert.equal(editor.getClickableTokenAt({ line: 0, ch: 1 }), null);
    } finally {
        harness.close();
    }
});

test('on a web address the editor\'s menu gets the plugins\' items for links (`url-menu`)', async () => {
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerEvent(this.app.workspace.on('url-menu', (menu, url) => menu.addItem((item) => item.setTitle('Archive ' + url))));
    }
}
module.exports = ExamplePlugin;`;
    const text = 'See [the docs](https://example.com/docs) or https://example.org/page. Or nothing.\n';
    const harness = await startRuntime({ files: { 'Note.md': text } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        await settle();
        assert.equal(plain(harness.host.notificationsOf('menus.changed').at(-1)).hasEditorMenuItems, true);
        const onMarkdownLink = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'u1', activeDocument: { path: 'Note.md', mode: 'source', editorSnapshot: harness.host.openNote('Note.md', 8) } }));
        assert.deepEqual(onMarkdownLink.items.map((item) => item.title), ['Archive https://example.com/docs']);
        const onBareAddress = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'u2', activeDocument: { path: 'Note.md', mode: 'source', editorSnapshot: harness.host.openNote('Note.md', 50) } }));
        assert.deepEqual(onBareAddress.items.map((item) => item.title), ['Archive https://example.org/page'], 'the full stop ends the sentence, not the address');
        const offAddress = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'u3', activeDocument: { path: 'Note.md', mode: 'source', editorSnapshot: harness.host.openNote('Note.md', 75) } }));
        assert.deepEqual(offAddress.items, []);
    } finally {
        harness.close();
    }
});

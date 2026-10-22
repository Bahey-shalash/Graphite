// Where a plugin's view goes when the plugin opens it "in the current tab" of the focused note.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

const counterPlugin = `"use strict";
var obsidian = require("obsidian");
class CounterView extends obsidian.ItemView {
    getViewType() { return 'counter'; }
    getDisplayText() { return 'Counter'; }
    async onOpen() { this.contentEl.setText('Counter'); }
}
class ExamplePlugin extends obsidian.Plugin {
    onload() { this.registerView('counter', (leaf) => new CounterView(leaf)); }
}
module.exports = ExamplePlugin;`;

async function focusNote(harness, path) {
    await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path, mode: 'livePreview', editorSnapshot: harness.host.openNote(path, 0) } });
}

test('a view opened in the current tab of a focused note gets a tab leaf that replaces the note\'s tab', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: counterPlugin });
        await focusNote(harness, 'Note.md');
        const workspace = harness.app.workspace;

        const currentLeaf = workspace.getLeaf(false);
        await currentLeaf.setViewState({ type: 'counter', active: true });
        await settle();

        const counterLeaves = workspace.getLeavesOfType('counter');
        assert.equal(counterLeaves.length, 1, 'the view opens in a leaf of its own');
        assert.equal(counterLeaves[0].view.contentEl.textContent, 'Counter');
        const listed = plain(harness.host.notificationsOf('views.changed').at(-1).views).find((view) => view.viewType === 'counter');
        assert.equal(listed.placement, 'tab');
        const reveal = plain(harness.host.notificationsOf('view.reveal').at(-1));
        assert.equal(reveal.leafIdentifier, counterLeaves[0].id);
        assert.equal(reveal.replacesCurrentTab, true, 'Graphite shows it in the note\'s tab, not in a new one');

        // Graphite's tab no longer shows the note; the view stays.
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: null });
        assert.equal(workspace.getLeavesOfType('counter').length, 1);
        assert.equal(workspace.getActiveViewOfType(harness.obsidian.ItemView), counterLeaves[0].view);
    } finally {
        harness.close();
    }
});

test('a view opened in a new tab does not replace the note\'s tab', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: counterPlugin });
        await focusNote(harness, 'Note.md');

        await harness.app.workspace.getLeaf('tab').setViewState({ type: 'counter', active: true });
        await settle();

        const reveal = plain(harness.host.notificationsOf('view.reveal').at(-1));
        assert.equal(reveal.placement, 'tab');
        assert.ok(!reveal.replacesCurrentTab);
    } finally {
        harness.close();
    }
});

test('a note a plugin opens is the active note, with its editor, when the opening returns', async () => {
    const harness = await startRuntime({ files: { 'Welcome.md': '# Welcome\n', 'Log.md': '# Log\n\nFirst entry.\n' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: counterPlugin });
        await focusNote(harness, 'Welcome.md');
        const workspace = harness.app.workspace;
        const MarkdownView = harness.obsidian.MarkdownView;

        await workspace.openLinkText('Log', 'Welcome.md', false);
        let view = workspace.getActiveViewOfType(MarkdownView);
        assert.equal(view.file.path, 'Log.md', 'the link opened Log.md, not the note open before');
        assert.equal(view.editor.getValue(), '# Log\n\nFirst entry.\n');

        // Re-opening its view state, as Advanced URI does next, opens that note again.
        await view.leaf.setViewState(view.leaf.getViewState());
        assert.deepEqual(harness.host.openedFiles.map((message) => message.resolvedPath || message.path), ['Log.md', 'Log.md']);

        await workspace.getLeaf(false).openFile(harness.app.vault.getFileByPath('Welcome.md'));
        view = workspace.getActiveViewOfType(MarkdownView);
        assert.equal(view.editor.getValue(), '# Welcome\n');
    } finally {
        harness.close();
    }
});

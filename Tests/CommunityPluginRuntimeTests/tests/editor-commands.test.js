'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'editing', name: 'Editing', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

function editingPlugin(commands) {
    return `"use strict";
var obsidian = require("obsidian");
class EditingPlugin extends obsidian.Plugin {
    async onload() {
${commands}
    }
}
module.exports = EditingPlugin;`;
}

async function runCommand(harness, commandIdentifier, notePath, selectionAnchor, selectionHead, mode) {
    return plain(await harness.send({
        operation: 'command.run',
        commandIdentifier,
        activeDocument: { path: notePath, mode: mode || 'livePreview', editorSnapshot: harness.host.openNote(notePath, selectionAnchor, selectionHead) },
    }));
}

test('an editor command changes the note through one change Graphite applies', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'alpha beta\ngamma' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: editingPlugin(`
        this.addCommand({ id: 'wrap', name: 'Wrap selection', editorCallback: (editor, view) => {
            const selected = editor.getSelection();
            editor.replaceSelection('**' + selected + '**');
            editor.replaceRange('# ', { line: 0, ch: 0 });
            this.lastFile = view.file.path;
        } });`) });
        const outcome = await runCommand(harness, 'editing:wrap', 'Note.md', 6, 10);
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        const session = harness.host.editorSessions.get('Note.md');
        assert.equal(session.appliedChanges.length, 1, 'edits made together reach Graphite as one change');
        assert.equal(session.text, '# alpha **beta**\ngamma');
        const change = session.appliedChanges[0];
        assert.equal(change.pluginIdentifier, 'editing');
        assert.equal(change.selectionAnchor, change.selectionHead);
        assert.equal(change.selectionHead, '# alpha **beta**'.length, 'the cursor follows the replaced selection');
        assert.equal(harness.app.plugins.getPlugin('editing').lastFile, 'Note.md');
    } finally {
        harness.close();
    }
});

test('editor positions use lines and UTF-16 columns, as CodeMirror and NSString do', async () => {
    const harness = await startRuntime({ files: { 'Emoji.md': 'a😀b\nsecond line' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: editingPlugin(`
        this.addCommand({ id: 'inspect', name: 'Inspect', editorCallback: (editor) => {
            this.report = {
                cursor: editor.getCursor(),
                lineCount: editor.lineCount(),
                secondLine: editor.getLine(1),
                offset: editor.posToOffset({ line: 1, ch: 3 }),
                position: editor.offsetToPos(4),
                word: editor.getRange(editor.wordAt({ line: 1, ch: 2 }).from, editor.wordAt({ line: 1, ch: 2 }).to),
            };
        } });`) });
        await runCommand(harness, 'editing:inspect', 'Emoji.md', 4);
        assert.deepEqual(plain(harness.app.plugins.getPlugin('editing').report), {
            cursor: { line: 0, ch: 4 }, lineCount: 2, secondLine: 'second line', offset: 8, position: { line: 0, ch: 4 }, word: 'second',
        });
    } finally {
        harness.close();
    }
});

test('editor commands are unavailable without a note, and check callbacks decide availability', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: editingPlugin(`
        this.addCommand({ id: 'needs-editor', name: 'Needs editor', editorCallback: (editor) => editor.setValue('changed') });
        this.addCommand({ id: 'only-selection', name: 'Only with selection', editorCheckCallback: (checking, editor) => {
            if (!editor.somethingSelected()) return false;
            if (!checking) editor.replaceSelection(editor.getSelection().toUpperCase());
            return true;
        } });`) });
        const withoutNote = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'editing:needs-editor', activeDocument: null }));
        assert.deepEqual(withoutNote, { outcome: 'unavailable' });
        assert.deepEqual(await runCommand(harness, 'editing:only-selection', 'Note.md', 1, 1), { outcome: 'unavailable' });
        assert.deepEqual(await runCommand(harness, 'editing:only-selection', 'Note.md', 0, 4), { outcome: 'ran' });
        await settle();
        assert.equal(harness.host.editorSessions.get('Note.md').text, 'TEXT');
    } finally {
        harness.close();
    }
});

test('transactions apply every change against the text before them', async () => {
    const harness = await startRuntime({ files: { 'List.md': 'one\ntwo\nthree' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: editingPlugin(`
        this.addCommand({ id: 'bullets', name: 'Bullets', editorCallback: (editor) => {
            const changes = [];
            for (let line = 0; line < editor.lineCount(); line += 1) changes.push({ from: { line, ch: 0 }, text: '- ' });
            editor.transaction({ changes });
        } });
        this.addCommand({ id: 'swap', name: 'Swap down', editorCallback: (editor) => editor.exec('swapLineDown') });`) });
        await runCommand(harness, 'editing:bullets', 'List.md', 0);
        await settle();
        assert.equal(harness.host.editorSessions.get('List.md').text, '- one\n- two\n- three');
        await runCommand(harness, 'editing:swap', 'List.md', 0);
        await settle();
        assert.equal(harness.host.editorSessions.get('List.md').text, 'two\none\nthree');
    } finally {
        harness.close();
    }
});

test('a note in reading view cannot be edited by a plugin', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: editingPlugin(`
        this.addCommand({ id: 'edit', name: 'Edit', editorCallback: (editor) => editor.setValue('changed') });`) });
        const snapshot = Object.assign(harness.host.openNote('Note.md', 0), { isReadOnly: true });
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'editing:edit', activeDocument: { path: 'Note.md', mode: 'reading', editorSnapshot: snapshot } }));
        assert.equal(outcome.outcome, 'failed');
        assert.match(outcome.message, /reading view/);
        await settle();
        assert.equal(harness.host.editorSessions.get('Note.md').appliedChanges.length, 0);
    } finally {
        harness.close();
    }
});

test('workspace reports the active file and its view to plugins', async () => {
    const harness = await startRuntime({ files: { 'First.md': 'one', 'Second.md': 'two' } });
    try {
        const opened = [];
        harness.app.workspace.on('file-open', (file) => opened.push(file ? file.path : null));
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'First.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('First.md', 0) } });
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'Second.md', mode: 'reading' } });
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: null });
        assert.deepEqual(opened, ['First.md', 'Second.md', null]);
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'First.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('First.md', 0) } });
        const view = harness.app.workspace.getActiveViewOfType(harness.obsidian.MarkdownView);
        assert.equal(view.file.path, 'First.md');
        assert.equal(view.getMode(), 'source');
        assert.equal(view.editor.getValue(), 'one');
        assert.equal(harness.app.workspace.getActiveFile().path, 'First.md');
        await harness.app.workspace.openLinkText('Second', 'First.md', true);
        assert.deepEqual(plain(harness.host.openedFiles.at(-1)), { operation: 'workspace.openLinkText', linktext: 'Second', sourcePath: 'First.md', resolvedPath: 'Second.md', subpath: null, placement: 'newTab' });
    } finally {
        harness.close();
    }
});

// Typing in a note: plugins that listen for `editor-change` hear each change Graphite's
// editor sends, and `EditorSuggest` suggestions are found at the cursor, shown by
// Graphite and inserted by the plugin when chosen.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'emoji', name: 'Emoji', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

/// Suggests emoji after `:`, as emoji plugins do, and counts the changes it hears.
const emojiPlugin = `"use strict";
var obsidian = require("obsidian");
const emoji = { smile: '😄', smirk: '😏', sun: '☀️' };
class EmojiSuggest extends obsidian.EditorSuggest {
    onTrigger(cursor, editor) {
        const before = editor.getLine(cursor.line).slice(0, cursor.ch);
        const match = /:(\\w*)$/.exec(before);
        if (!match) return null;
        return { start: { line: cursor.line, ch: cursor.ch - match[0].length }, end: cursor, query: match[1] };
    }
    getSuggestions(context) {
        return Object.keys(emoji).filter((name) => name.startsWith(context.query));
    }
    renderSuggestion(name, element) {
        const content = element.createDiv({ cls: 'suggestion-content' });
        content.createDiv({ cls: 'suggestion-title', text: emoji[name] + ' ' + name });
        content.createDiv({ cls: 'suggestion-note', text: 'Emoji' });
    }
    selectSuggestion(name) {
        this.context.editor.replaceRange(emoji[name], this.context.start, this.context.end);
        this.close();
    }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.changes = [];
        this.registerEditorSuggest(new EmojiSuggest(this.app));
        this.registerEvent(this.app.workspace.on('editor-change', (editor, view) => this.changes.push(view.file.path + ':' + editor.getValue())));
    }
}
module.exports = ExamplePlugin;`;

function editorUpdate(harness, text, cursor, wantsSuggestions, requestIdentifier) {
    harness.writeVaultFile('Note.md', text);
    return harness.send({
        operation: 'editor.update', wantsSuggestions, requestIdentifier,
        activeDocument: { path: 'Note.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Note.md', cursor) },
    });
}

test('suggestions at the cursor come from the plugin that triggers, and the chosen one is inserted by it', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'Hi\n' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: emojiPlugin });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('editor.listenersChanged').at(-1)), { operation: 'editor.listenersChanged', hasEditorChangeListeners: true, hasPasteListeners: false, hasDropListeners: false, hasEditorSuggestions: true });
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), []);

        await editorUpdate(harness, 'Hi\n', 2, false);
        assert.deepEqual(plain(await editorUpdate(harness, 'Hi :\n', 4, true, 'r1')).suggestion.items.map((item) => item.title), ['😄 smile', '😏 smirk', '☀️ sun']);
        const typed = plain(await editorUpdate(harness, 'Hi :sm\n', 6, true, 'r2'));
        assert.deepEqual(typed.suggestion, {
            requestIdentifier: 'r2', pluginIdentifier: 'emoji',
            items: [{ position: 0, title: '😄 smile', subtitle: 'Emoji' }, { position: 1, title: '😏 smirk', subtitle: 'Emoji' }],
        });
        assert.deepEqual(plain(await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'r1', position: 0 })), { outcome: 'missing' }, 'only the latest suggestions can be chosen');
        assert.deepEqual(plain(await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'r2', position: 1 })), { outcome: 'ran' });
        await settle();
        assert.equal(harness.host.editorSessions.get('Note.md').text, 'Hi 😏\n');
        assert.deepEqual(plain(await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'r2', position: 0 })), { outcome: 'missing' }, 'a suggestion is inserted once');

        assert.deepEqual(plain(await editorUpdate(harness, 'Hi there\n', 8, true, 'r3')), { suggestion: null }, 'no suggest triggers outside `:`');
        assert.deepEqual(plain(await editorUpdate(harness, 'Hi :xyz\n', 7, true, 'r4')), { suggestion: null }, 'a trigger without suggestions shows nothing');

        // A suggest that stops answering is closed, as Obsidian closes it; Escape closes it too.
        const emojiSuggest = harness.runtime.editorSuggests[0];
        assert.equal(emojiSuggest.isOpen, false);
        await editorUpdate(harness, 'Hi :s\n', 5, true, 'r5');
        assert.equal(emojiSuggest.isOpen, true);
        await harness.send({ operation: 'editor.closeSuggestions' });
        assert.equal(emojiSuggest.isOpen, false);
        assert.deepEqual(plain(await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'r5', position: 0 })), { outcome: 'missing' });

        // Each changed text was heard once; an update with the same text is not a change.
        await editorUpdate(harness, 'Hi :s\n', 5, false);
        assert.deepEqual(plain(harness.app.plugins.getPlugin('emoji').changes), ['Note.md:Hi :\n', 'Note.md:Hi :sm\n', 'Note.md:Hi there\n', 'Note.md:Hi :xyz\n', 'Note.md:Hi :s\n']);
    } finally {
        harness.close();
    }
});

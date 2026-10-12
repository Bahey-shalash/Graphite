// Plugin views for files (`registerExtensions`, and notes a plugin shows in its own view),
// views split beside the note, live views, paste and drop events, and plugins' Bases views:
// the gaps the community plugin sweep found (Docs/Community-plugins.md).
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle, waitUntil } = require('../support/runtime-harness');

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

/// A plugin with a text file view for `.sketch` files, which also shows notes whose
/// frontmatter says `sketch: true` in that view, as Excalidraw does for its drawings.
const sketchPlugin = `"use strict";
var obsidian = require("obsidian");
class SketchView extends obsidian.TextFileView {
    getViewType() { return 'sketch'; }
    getDisplayText() { return this.file ? this.file.basename : 'Sketch'; }
    setViewData(data) { this.data = data; this.contentEl.setText('Sketch: ' + data.trim()); }
    getViewData() { return this.data; }
    clear() {}
}
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.registerView('sketch', (leaf) => new SketchView(leaf));
        this.registerExtensions(['sketch'], 'sketch');
        const plugin = this;
        const original = obsidian.WorkspaceLeaf.prototype.setViewState;
        obsidian.WorkspaceLeaf.prototype.setViewState = function (state, eState) {
            const file = state && state.state && state.state.file ? plugin.app.vault.getFileByPath(state.state.file) : null;
            const cache = file ? plugin.app.metadataCache.getFileCache(file) : null;
            if (state.type === 'markdown' && cache && cache.frontmatter && cache.frontmatter.sketch) return original.call(this, Object.assign({}, state, { type: 'sketch' }), eState);
            return original.call(this, state, eState);
        };
        this.register(() => { obsidian.WorkspaceLeaf.prototype.setViewState = original; });
    }
}
module.exports = ExamplePlugin;`;

test('a file of a registered extension opens in the plugin\'s view, live, and a note it takes over too', async () => {
    const harness = await startRuntime({ files: { 'Drawing.sketch': 'circle\n', 'Sketched.md': '---\nsketch: true\n---\nsquare\n', 'Plain.md': 'text\n' } });
    try {
        await harness.waitForMetadata();
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: sketchPlugin })), { isLoaded: true });
        await settle();
        const fileViews = plain(harness.host.notificationsOf('fileViews.changed').at(-1));
        assert.deepEqual(fileViews.extensions, { sketch: 'sketch' });
        assert.equal(fileViews.takesOverNotes, true);

        const opened = plain(await harness.send({ operation: 'file.openInView', path: 'Drawing.sketch' }));
        assert.equal(opened.isOpened, true);
        const leaf = harness.app.workspace.getLeafById(opened.leafIdentifier);
        assert.equal(leaf.view.getViewType(), 'sketch');
        assert.equal(leaf.view.contentEl.textContent, 'Sketch: circle');
        const listed = plain(harness.host.notificationsOf('views.changed').at(-1).views).find((view) => view.leafIdentifier === opened.leafIdentifier);
        assert.equal(listed.isLive, true);
        assert.equal(listed.filePath, 'Drawing.sketch');
        assert.equal(plain(harness.host.notificationsOf('view.reveal')).length, 0, 'Graphite opens the tab itself');

        const takenOver = plain(await harness.send({ operation: 'file.openInView', path: 'Sketched.md' }));
        assert.equal(takenOver.isOpened, true);
        assert.match(harness.app.workspace.getLeafById(takenOver.leafIdentifier).view.contentEl.textContent, /^Sketch: [\s\S]*square$/);
        const before = harness.app.workspace.pluginLeaves.length;
        assert.deepEqual(plain(await harness.send({ operation: 'file.openInView', path: 'Plain.md' })), { isOpened: false });
        assert.equal(harness.app.workspace.pluginLeaves.length, before, 'the probe leaf goes away');
        assert.equal(plain(harness.host.openedFiles).length, 0, 'asking does not open the note');

        // Shown live: the leaf fills the page until Graphite stops showing it there.
        assert.deepEqual(plain(await harness.send({ operation: 'view.live', leafIdentifier: opened.leafIdentifier })), { isShown: true });
        const document = harness.window.document;
        assert.ok(document.body.classList.contains('graphite-live'));
        assert.equal(document.querySelector('.graphite-live-view > .workspace-leaf'), leaf.containerEl);
        await harness.send({ operation: 'view.unlive', leafIdentifier: opened.leafIdentifier });
        assert.ok(!document.body.classList.contains('graphite-live'));
        assert.ok(leaf.containerEl.isConnected, 'the leaf waits in the page again');

        // Unloading forgets the extension.
        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'example' });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('fileViews.changed').at(-1)), { operation: 'fileViews.changed', extensions: {}, takesOverNotes: false });
    } finally {
        harness.close();
    }
});

test('a view split beside the note says so, and the note stays the active leaf', async () => {
    // Mind Map opens its map with `splitActiveLeaf`.
    const source = `"use strict";
var obsidian = require("obsidian");
class MapView extends obsidian.ItemView { getViewType() { return 'map'; } getDisplayText() { return 'Map'; } }
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerView('map', (leaf) => new MapView(leaf));
        this.addCommand({ id: 'open', name: 'Open', callback: async () => { const leaf = this.app.workspace.splitActiveLeaf(); await leaf.open(new MapView(leaf)); } });
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: { 'Note.md': 'x\n' } });
    try {
        await harness.waitForMetadata();
        const activeDocument = { path: 'Note.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Note.md', 0) };
        await harness.send({ operation: 'workspace.activeDocument', activeDocument });
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await harness.send({ operation: 'command.run', commandIdentifier: 'example:open', activeDocument });
        await settle();
        const map = plain(harness.host.notificationsOf('views.changed').at(-1).views).find((view) => view.viewType === 'map');
        assert.equal(map.placement, 'split');
        assert.equal(map.isLive, false);
        assert.equal(plain(harness.host.notificationsOf('view.reveal').at(-1)).placement, 'split');
        assert.equal(harness.app.workspace.activeLeaf, harness.app.workspace.markdownLeaf);
    } finally {
        harness.close();
    }
});

test('a plugin hears a paste or a drop, and one that prevents it takes it over', async () => {
    // Link or Card offers a card for a pasted address; Linter pastes plain text.
    const source = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    onload() {
        this.registerEvent(this.app.workspace.on('editor-paste', (event, editor) => {
            const text = event.clipboardData.getData('text/plain');
            if (!/^https?:/.test(text)) return;
            event.preventDefault();
            editor.replaceSelection('[card](' + text + ')');
        }));
        this.registerEvent(this.app.workspace.on('editor-drop', (event) => { this.dropped = event.dataTransfer.files.map((file) => file.name); }));
    }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: { 'Note.md': 'Start\n' } });
    try {
        await harness.waitForMetadata();
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await settle();
        const listeners = plain(harness.host.notificationsOf('editor.listenersChanged').at(-1));
        assert.equal(listeners.hasPasteListeners, true);
        assert.equal(listeners.hasDropListeners, true);
        const activeDocument = () => ({ path: 'Note.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Note.md', 5) });
        assert.deepEqual(plain(await harness.send({ operation: 'editor.paste', activeDocument: activeDocument(), text: 'plain words' })), { isHandled: false });
        assert.deepEqual(plain(await harness.send({ operation: 'editor.paste', activeDocument: activeDocument(), text: 'https://obsidian.md', html: '<a>x</a>' })), { isHandled: true });
        const session = harness.host.editorSessions.get('Note.md');
        await waitUntil(() => session.appliedChanges.length > 0);
        assert.equal(session.text, 'Start[card](https://obsidian.md)\n', 'the plugin\'s edit comes back as one editor change');
        assert.deepEqual(plain(await harness.send({ operation: 'editor.drop', activeDocument: activeDocument(), files: [{ name: 'photo.png', type: 'image/png', size: 10 }] })), { isHandled: false });
        assert.deepEqual(plain(harness.app.plugins.plugins.example.dropped), ['photo.png']);
    } finally {
        harness.close();
    }
});

test('a base shows a view of a plugin\'s type over the base\'s results, with the view\'s settings from the file', async () => {
    // TaskNotes registers its calendars and boards as Bases views.
    const source = `"use strict";
var obsidian = require("obsidian");
class ListView extends obsidian.BasesView {
    constructor(controller, containerEl) { super(controller); this.containerEl = containerEl; this.type = 'example-list'; }
    onDataUpdated() {
        this.containerEl.empty();
        this.containerEl.createDiv({ cls: 'heading', text: String(this.config.get('heading')) });
        for (const entry of this.data.data) this.containerEl.createDiv({ cls: 'row', text: entry.file.basename + ': ' + entry.getValue('note.status').toString() });
    }
}
class ExamplePlugin extends obsidian.Plugin {
    onload() { this.registered = this.registerBasesView('example-list', { name: 'Example list', icon: 'list', factory: (controller, containerEl) => new ListView(controller, containerEl) }); }
}
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {
        'Tasks.base': 'views:\n  - type: example-list\n    name: Open\n    heading: Open tasks\n',
        'First.md': '---\nstatus: open\n---\n', 'Second.md': '---\nstatus: done\n---\n',
    } });
    try {
        await harness.waitForMetadata();
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await settle();
        assert.equal(harness.app.plugins.plugins.example.registered, true);
        assert.deepEqual(plain(harness.host.notificationsOf('basesViews.changed').at(-1).views), [{ viewType: 'example-list', name: 'Example list', pluginIdentifier: 'example' }]);
        const opened = plain(await harness.send({ operation: 'basesView.open', viewType: 'example-list', viewName: 'Open', viewIndex: 0, baseFilePath: 'Tasks.base', groups: [{ key: null, paths: ['First.md'] }], properties: ['note.status'] }));
        assert.equal(opened.isOpened, true);
        const content = harness.app.workspace.getLeafById(opened.leafIdentifier).view.contentEl;
        assert.deepEqual(Array.from(content.children).map((element) => element.textContent), ['Open tasks', 'First: open']);
        assert.ok(!plain(harness.host.notificationsOf('views.changed').at(-1).views).some((view) => view.leafIdentifier === opened.leafIdentifier), 'not a tab or sidebar view of its own');
        await harness.send({ operation: 'basesView.update', leafIdentifier: opened.leafIdentifier, groups: [{ key: null, paths: ['First.md', 'Second.md'] }] });
        assert.deepEqual(Array.from(content.children).map((element) => element.textContent), ['Open tasks', 'First: open', 'Second: done']);
    } finally {
        harness.close();
    }
});

test('a view Graphite showed when it closed opens again from the type and state it saved', async () => {
    const harness = await startRuntime({ files: { 'Drawing.sketch': 'circle\n' } });
    try {
        await harness.waitForMetadata();
        await installAndLoadPlugin(harness, { manifest, mainSource: sketchPlugin });
        await settle();
        const opened = plain(await harness.send({ operation: 'file.openInView', path: 'Drawing.sketch' }));
        const listed = plain(harness.host.notificationsOf('views.changed').at(-1).views).find((view) => view.leafIdentifier === opened.leafIdentifier);
        assert.deepEqual(JSON.parse(listed.state), { file: 'Drawing.sketch' }, 'the state Graphite saves with the tab');

        const restored = plain(await harness.send({ operation: 'view.restore', viewType: 'sketch', state: listed.state, placement: 'tab' }));
        assert.equal(restored.isOpened, true);
        const leaf = harness.app.workspace.getLeafById(restored.leafIdentifier);
        assert.equal(leaf.view.contentEl.textContent, 'Sketch: circle');
        assert.equal(plain(harness.host.notificationsOf('view.reveal')).length, 0, 'Graphite puts the view back in its tab itself');

        const before = harness.app.workspace.pluginLeaves.length;
        assert.deepEqual(plain(await harness.send({ operation: 'view.restore', viewType: 'uninstalled-view', state: '{}', placement: 'right' })), { isOpened: false });
        assert.deepEqual(plain(await harness.send({ operation: 'view.restore', viewType: 'markdown', state: '{"file":"Drawing.sketch"}', placement: 'tab' })), { isOpened: false });
        assert.equal(harness.app.workspace.pluginLeaves.length, before, 'no leaf is left behind for a view no plugin shows');
    } finally {
        harness.close();
    }
});

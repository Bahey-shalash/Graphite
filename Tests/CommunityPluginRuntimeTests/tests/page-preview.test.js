// Hover previews of links (Obsidian's core plugin Page Preview): a plugin's `hover-link` and
// `link-hover` answered to the copy that forwarded the hover, or sent from a live view;
// Graphite's own hovers heard by plugins that listen; hover link sources kept per plugin.
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

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };
const pagePreviewOn = [{ identifier: 'page-preview', isEnabled: true }];

/// A `files` block lists notes; hovering a row asks for its preview as Recent Files does
/// (`hover-link`), and the day row only with ⌘ held, as Calendar does (`link-hover`).
const fileListPlugin = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerHoverLinkSource('example', { display: 'Example', defaultMod: true });
        this.registerMarkdownCodeBlockProcessor('files', (source, element) => {
            const row = element.createDiv({ cls: 'row' });
            const title = row.createSpan({ cls: 'title', text: 'Other' });
            row.addEventListener('mouseover', (event) => {
                globalThis.rowHovers = (globalThis.rowHovers || 0) + 1;
                this.app.workspace.trigger('hover-link', { event, source: 'example', hoverParent: this, targetEl: title, linktext: 'Folder/Other.md' });
            });
            const day = element.createDiv({ cls: 'day', text: '22' });
            day.addEventListener('mouseover', (event) => {
                if (event.metaKey) this.app.workspace.trigger('link-hover', this, day, '2026-10-22', 'Journal/2026-10-22.md');
            });
            element.createDiv({ cls: 'plain', text: 'no listener' });
        });
    }
}`);

async function drawFiles(harness) {
    await installAndLoadPlugin(harness, { manifest, mainSource: fileListPlugin });
    await settle();
    const drawn = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'files-1', language: 'files', source: '', sourcePath: 'Note.md', width: 600 }));
    assert.equal(drawn.isDrawn, true, drawn.message);
    return drawn;
}

test('a link a plugin asks to preview while the pointer moves in a copy is the answer to that hover, with the keys held', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '```files\n```\n' }, corePlugins: pagePreviewOn });
    try {
        const drawn = await drawFiles(harness);
        assert.match(drawn.html, /<div class="row" data-graphite-listens="hover">/, 'the copy forwards hovering on the row');

        const onRow = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'files-1', eventType: 'hover', elementPath: [0, 0], x: 4, y: 4 }));
        assert.deepEqual(onRow, { isHandled: true, linkHover: { linktext: 'Folder/Other.md', sourcePath: '', source: 'example' } });

        const onDayWithoutCommand = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'files-1', eventType: 'hover', elementPath: [1], x: 4, y: 30 }));
        assert.deepEqual(onDayWithoutCommand, { isHandled: true }, 'without ⌘ the plugin asks for nothing');
        await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'files-1', eventType: 'hover', elementPath: null, x: 0, y: 0 });
        const onDayWithCommand = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'files-1', eventType: 'hover', elementPath: [1], x: 4, y: 30, metaKey: true }));
        assert.deepEqual(onDayWithCommand, { isHandled: true, linkHover: { linktext: '2026-10-22', sourcePath: 'Journal/2026-10-22.md', source: '' } },
            'Obsidian\'s older `link-hover` names its link by position');

        const offTheRows = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'files-1', eventType: 'hover', elementPath: [2], x: 4, y: 60 }));
        assert.deepEqual(offTheRows, { isHandled: true });
        assert.deepEqual(plain(harness.host.notificationsOf('hoverLink.show')), [], 'a copy\'s link goes back with the hover, not as a message of its own');
    } finally {
        harness.close();
    }
});

test('while Page Preview is off, plugins still hear their own hover-link and no link is answered', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '```files\n```\n' }, corePlugins: [{ identifier: 'page-preview', isEnabled: false }] });
    try {
        await drawFiles(harness);
        const onRow = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'files-1', eventType: 'hover', elementPath: [0, 0], x: 4, y: 4 }));
        assert.deepEqual(onRow, { isHandled: true });
        assert.equal(harness.window.rowHovers, 1, 'the plugin\'s own listener ran');
        assert.equal(harness.app.internalPlugins.getEnabledPluginById('page-preview'), null);
    } finally {
        harness.close();
    }
});

/// A view whose rows ask for previews, shown live as Excalidraw's drawings are.
const liveViewPlugin = pluginSource(`
class RowsView extends obsidian.ItemView {
    getViewType() { return 'rows'; }
    getDisplayText() { return 'Rows'; }
    async onOpen() {
        const row = this.contentEl.createDiv({ cls: 'live-row', text: 'Other' });
        row.addEventListener('mouseover', (event) => {
            this.app.workspace.trigger('hover-link', { event, source: 'rows', hoverParent: this, targetEl: row, linktext: 'Other', sourcePath: 'Note.md' });
        });
    }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerView('rows', (leaf) => new RowsView(leaf));
        this.addCommand({ id: 'open', name: 'Open', callback: async () => {
            const leaf = this.app.workspace.getLeaf('tab');
            await leaf.setViewState({ type: 'rows' });
        } });
    }
}`);

test('a link a plugin asks to preview in a live view is sent with where its element is, and its end when the pointer leaves', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text\n', 'Other.md': 'other\n' }, corePlugins: pagePreviewOn });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: liveViewPlugin });
        await harness.send({ operation: 'plugins.layoutReady' });
        await settle();
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'example:open' })), { outcome: 'ran' });
        await settle();
        const leafIdentifier = plain(harness.host.notificationsOf('views.changed').at(-1).views)[0].leafIdentifier;
        const row = harness.window.document.querySelector('.live-row');

        // Not shown live, nor as a copy (a plugin view waiting in the page): no card.
        row.dispatchEvent(new harness.window.MouseEvent('mouseover', { bubbles: true }));
        assert.deepEqual(plain(harness.host.notificationsOf('hoverLink.show')), []);

        assert.deepEqual(plain(await harness.send({ operation: 'view.live', leafIdentifier })), { isShown: true });
        row.dispatchEvent(new harness.window.MouseEvent('mouseover', { bubbles: true }));
        const shown = plain(harness.host.notificationsOf('hoverLink.show'));
        assert.equal(shown.length, 1);
        assert.deepEqual(shown[0], {
            operation: 'hoverLink.show', hoverNumber: 1, leafIdentifier, rect: { x: 0, y: 0, width: 0, height: 0 },
            linktext: 'Other', sourcePath: 'Note.md', source: 'rows',
        }, 'jsdom lays nothing out, so the element measures nothing');

        row.dispatchEvent(new harness.window.MouseEvent('mouseleave'));
        row.dispatchEvent(new harness.window.MouseEvent('mouseleave'));
        assert.deepEqual(plain(harness.host.notificationsOf('hoverLink.end')), [{ operation: 'hoverLink.end', hoverNumber: 1 }], 'one end per hover');
    } finally {
        harness.close();
    }
});

/// A plugin that keeps the hovers it hears, as plugins that change their own previews do.
const listeningPlugin = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        globalThis.heardHovers = [];
        this.registerEvent(this.app.workspace.on('hover-link', (hover) => {
            globalThis.heardHovers.push({
                source: hover.source, linktext: hover.linktext, sourcePath: hover.sourcePath, eventType: hover.event.type,
                target: hover.targetEl.tagName + ' ' + hover.targetEl.className + ' ' + hover.targetEl.getAttribute('data-href'),
                hoverParent: hover.hoverParent instanceof obsidian.MarkdownView ? 'MarkdownView' : 'other',
            });
        }));
    }
}`);

test('plugins listening for hover-link hear Graphite\'s own hovers, with a stand-in link, while Graphite is told someone listens', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'See [[Other]].\n', 'Other.md': 'other\n' }, corePlugins: pagePreviewOn });
    try {
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'Note.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Note.md', 0) } });
        assert.equal(plain(harness.host.notificationsOf('editor.listenersChanged').at(-1) || { hasHoverLinkListeners: false }).hasHoverLinkListeners, false);
        await installAndLoadPlugin(harness, { manifest, mainSource: listeningPlugin });
        await settle();
        assert.equal(plain(harness.host.notificationsOf('editor.listenersChanged').at(-1)).hasHoverLinkListeners, true);

        assert.deepEqual(plain(await harness.send({ operation: 'hoverLink.hovered', linktext: 'Other', sourcePath: 'Note.md', source: 'editor' })), {});
        assert.deepEqual(plain(harness.window.heardHovers), [
            { source: 'editor', linktext: 'Other', sourcePath: 'Note.md', eventType: 'mouseover', target: 'A internal-link Other', hoverParent: 'MarkdownView' },
        ]);
        assert.deepEqual(plain(harness.host.notificationsOf('hoverLink.show')), [], 'Graphite already shows the card of its own hover');

        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'example' });
        await settle();
        assert.equal(plain(harness.host.notificationsOf('editor.listenersChanged').at(-1)).hasHoverLinkListeners, false);
    } finally {
        harness.close();
    }
});

test('hover link sources are kept while their plugin is loaded, and Page Preview is Obsidian\'s internal plugin with its entry point', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '```files\n```\n' }, corePlugins: pagePreviewOn });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: fileListPlugin });
        await settle();
        assert.deepEqual(plain(harness.app.workspace.hoverLinkSources), { example: { display: 'Example', defaultMod: true } });
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), [], 'hover previews are no longer reported unsupported');
        const pagePreview = harness.app.internalPlugins.getEnabledPluginById('page-preview');
        assert.equal(typeof pagePreview.onLinkHover, 'function', 'plugins that call Page Preview themselves find it');
        assert.equal(pagePreview.id, 'page-preview');

        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'example' });
        await settle();
        assert.deepEqual(plain(harness.app.workspace.hoverLinkSources), {});
    } finally {
        harness.close();
    }
});

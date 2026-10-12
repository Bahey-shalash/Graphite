// Plugins' code blocks drawn for Graphite's reading view: the copies Graphite shows,
// kept current, taps sent back to the plugin's block, and links followed through Graphite.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle, waitUntil } = require('../support/runtime-harness');

function pluginSource(body) {
    return `"use strict";
var obsidian = require("obsidian");
${body}
module.exports = ExamplePlugin;`;
}

const manifest = { id: 'counter', name: 'Counter', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

/// A plugin whose `counter` blocks show a number, a box that counts ticks, a link and a
/// part that keeps changing after the block is drawn, as Dataview's and Tasks' do.
const counterPlugin = pluginSource(`
class CounterChild extends obsidian.MarkdownRenderChild {
    onload() { this.loaded = true; globalThis.counterChildren = (globalThis.counterChildren || 0) + 1; }
    onunload() { globalThis.counterChildren -= 1; }
}
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownCodeBlockProcessor('counter', async (source, element, context) => {
            const start = Number(source.trim());
            const list = element.createEl('ul', { cls: 'contains-task-list' });
            const item = list.createEl('li', { cls: 'task-list-item' });
            const box = item.createEl('input', { type: 'checkbox', cls: 'task-list-item-checkbox' });
            const count = item.createSpan({ cls: 'count', text: String(start) });
            box.addEventListener('click', () => { count.setText(String(Number(count.getText()) + 1)); });
            element.createEl('a', { cls: 'internal-link', text: 'Other', attr: { 'data-href': 'Other', href: 'Other' } });
            element.createEl('a', { cls: 'external-link', text: 'Web', attr: { href: 'https://example.com/page' } });
            const filter = element.createEl('input', { type: 'text', cls: 'filter' });
            filter.addEventListener('input', () => count.setText('filtered by ' + filter.value));
            const section = context.getSectionInfo(element);
            element.createDiv({ cls: 'section', text: section ? section.lineStart + '-' + section.lineEnd : 'none' });
            context.addChild(new CounterChild(element));
            setTimeout(() => element.createDiv({ cls: 'later', text: 'drawn later' }), 30);
        });
    }
}`);

test('a plugin\'s code block is drawn for the reading view and kept current', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'Intro\n\n```counter\n4\n```\n', 'Other.md': 'Other' } });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: counterPlugin, styles: '.count { color: red; }' })), { isLoaded: true });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('codeBlocks.changed').at(-1)).languages, ['counter']);
        assert.deepEqual(plain(harness.host.notificationsOf('codeBlocks.changed').at(-1)).owners, { counter: 'counter' });
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), [], 'code blocks are no longer reported as unsupported');

        const answer = plain(await harness.send({
            operation: 'codeBlock.render', blockIdentifier: 'block-1', language: 'counter', source: '4', sourcePath: 'Note.md',
            firstLine: 2, lineCount: 3, noteText: 'Intro\n\n```counter\n4\n```\n', width: 600,
        }));
        assert.equal(answer.isDrawn, true);
        assert.match(answer.html, /^<div class="block-language-counter">/);
        assert.match(answer.html, /<span class="count">4<\/span>/);
        assert.match(answer.html, /<div class="section">2-4<\/div>/, 'getSectionInfo gives the block\'s lines in the note');
        assert.match(answer.styles, /\.count \{ color: red; \}/);
        assert.equal(harness.window.counterChildren, 1, 'children the plugin adds are loaded');

        await waitUntil(() => harness.host.notificationsOf('codeBlock.changed').length > 0);
        const change = plain(harness.host.notificationsOf('codeBlock.changed').at(-1));
        assert.equal(change.blockIdentifier, 'block-1');
        assert.match(change.html, /drawn later/, 'what the plugin draws afterwards reaches Graphite');

        // The box is the first element of the item, in the first element of the list.
        const tap = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'block-1', elementPath: [0, 0, 0] }));
        assert.equal(tap.isHandled, true);
        assert.match(tap.html, /<input [^>]*checked=""[^>]*>/, 'the copy shows the box ticked');
        assert.match(tap.html, /<span class="count">5<\/span>/, 'the plugin\'s own handler ran');

        // Text typed into the copy's field reaches the plugin's field, which hears it as typing.
        const typed = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'block-1', eventType: 'input', elementPath: [3], value: 'report' }));
        assert.match(typed.html, /<span class="count">filtered by report<\/span>/);
        assert.match(typed.html, /<input type="text" class="filter" value="report">|<input class="filter" type="text" value="report">/);

        await harness.send({ operation: 'codeBlock.release', blockIdentifier: 'block-1' });
        assert.equal(harness.window.counterChildren, 0, 'releasing the block unloads what the plugin added to it');
        assert.equal(harness.window.document.querySelectorAll('.graphite-reading-block').length, 0);
        assert.deepEqual(plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'block-1', elementPath: [0] })), { isHandled: false });
    } finally {
        harness.close();
    }
});

test('links in a plugin\'s block open through Graphite, and never replace the runtime\'s page', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '```counter\n1\n```\n', 'Other.md': 'Other' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: counterPlugin });
        await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block-2', language: 'counter', source: '1', sourcePath: 'Note.md', width: 600 });
        await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'block-2', elementPath: [1] });
        await settle();
        assert.deepEqual(plain(harness.host.openedFiles.map((request) => [request.operation, request.linktext, request.sourcePath])), [['workspace.openLinkText', 'Other', 'Note.md']]);
        await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'block-2', elementPath: [2] });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('workspace.openExternalLink').map((notification) => notification.address)), ['https://example.com/page']);
        assert.equal(harness.window.location.href, 'https://graphite-plugins.test/', 'the page stayed where it was');
    } finally {
        harness.close();
    }
});

test('a block in a language no plugin draws, or one whose processor throws, says so', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const failingPlugin = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownCodeBlockProcessor('broken', () => { throw new Error('The query has a typo.'); });
    }
}`);
        await installAndLoadPlugin(harness, { manifest: Object.assign({}, manifest, { id: 'broken', name: 'Broken' }), mainSource: failingPlugin });
        const missing = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block-3', language: 'nothing', source: '', sourcePath: 'Note.md' }));
        assert.deepEqual(missing, { isDrawn: false, message: 'No plugin draws “nothing” code blocks now.' });
        const failed = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block-4', language: 'broken', source: '', sourcePath: 'Note.md' }));
        assert.equal(failed.isDrawn, true);
        assert.match(failed.html, /The query has a typo\./);
        await settle();
        assert.match(plain(harness.host.notificationsOf('plugin.failure').at(-1)).message, /“broken” block failed: The query has a typo\./);
        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'broken' });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('codeBlocks.changed').at(-1)).languages, [], 'unloading the plugin withdraws its language');
    } finally {
        harness.close();
    }
});

test('a note\'s section is shown as a plugin changed it, and left to Graphite when no plugin changes it', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'Plain words.\n\nSay `shout:hello` here.\n' } });
    try {
        const shoutingPlugin = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownPostProcessor((element, context) => {
            for (const code of Array.from(element.querySelectorAll('code'))) {
                if (!code.textContent.startsWith('shout:')) continue;
                const loud = createEl('strong', { cls: 'shout', text: code.textContent.slice(6).toUpperCase() });
                code.replaceWith(loud);
                const section = context.getSectionInfo(element);
                loud.setAttribute('data-lines', section ? section.lineStart + '-' + section.lineEnd : 'none');
            }
        });
    }
}`);
        await installAndLoadPlugin(harness, { manifest: Object.assign({}, manifest, { id: 'shout', name: 'Shout' }), mainSource: shoutingPlugin });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('postProcessors.changed').at(-1)).pluginIdentifiers, ['shout']);
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), [], 'post-processors are no longer reported as unsupported');

        const plainSection = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'section-1', source: 'Plain words.', sourcePath: 'Note.md', firstLine: 0, lineCount: 1, noteText: 'Plain words.\n\nSay `shout:hello` here.\n' }));
        assert.deepEqual(plainSection, { isDrawn: true, isChanged: false });
        assert.equal(harness.window.document.querySelectorAll('.graphite-reading-block').length, 0, 'an unchanged section is not kept');

        const changed = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'section-2', source: 'Say `shout:hello` here.', sourcePath: 'Note.md', firstLine: 2, lineCount: 1, noteText: 'Plain words.\n\nSay `shout:hello` here.\n' }));
        assert.equal(changed.isChanged, true);
        assert.match(changed.html, /<strong class="shout" data-lines="2-2">HELLO<\/strong>/);
        assert.equal(harness.window.document.querySelectorAll('.graphite-reading-block').length, 1, 'a changed section stays alive');
        // A task of the section itself, tapped in the plugin's version, is left to Graphite to
        // tick in the note: the answer names its line in the section.
        const taskList = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'section-3', source: '- [ ] Call `shout:bob`\n- [x] Done', sourcePath: 'Note.md', firstLine: 4, lineCount: 2 }));
        assert.equal(taskList.isChanged, true);
        assert.match(taskList.html, /<input type="checkbox" data-graphite-task-line="1" checked="">|data-graphite-task-line="1"/);
        assert.doesNotMatch(taskList.html, /disabled/, 'the boxes can be ticked');
        const tick = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'section-3', elementPath: [0, 1, 0] }));
        assert.deepEqual(tick, { isHandled: true, taskLine: 1 });

        await harness.send({ operation: 'plugin.unload', pluginIdentifier: 'shout' });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('postProcessors.changed').at(-1)).pluginIdentifiers, []);
    } finally {
        harness.close();
    }
});

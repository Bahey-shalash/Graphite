// The attribute names the plugins' page writes on the copies of a plugin's blocks and
// Graphite's Swift page reads back: where a plugin listens, which line a task box is, and
// which note a block belongs to. Renaming one breaks taps, menus and drags without an error.
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

const manifest = { id: 'listeners', name: 'Listeners', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

/// A block whose elements each listen for the events of one kind, and one for several.
const listeningPlugin = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownCodeBlockProcessor('listeners', (source, element) => {
            const eventsByElement = {
                menu: ['contextmenu'],
                hover: ['mouseover', 'mouseenter', 'mouseout', 'mouseleave', 'pointerover', 'pointerenter', 'pointerout', 'pointerleave'],
                press: ['mousedown', 'pointerdown', 'touchstart'],
                drag: ['dragstart'],
                drop: ['dragenter', 'dragover', 'drop'],
            };
            for (const [name, types] of Object.entries(eventsByElement)) {
                const box = element.createDiv({ cls: 'listens-' + name, text: name });
                for (const type of types) box.addEventListener(type, () => {});
            }
            const several = element.createDiv({ cls: 'listens-several', text: 'several' });
            several.addEventListener('drop', () => {});
            several.addEventListener('contextmenu', () => {});
            several.addEventListener('mousedown', () => {});
            several.addEventListener('drop', () => {});
            element.createDiv({ cls: 'listens-nothing', text: 'nothing' }).addEventListener('click', () => {});
        });
    }
}`);

test('an element lists the kinds of event its plugin listens for in data-graphite-listens', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '```listeners\n```\n' } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: listeningPlugin });
        await settle();
        const drawn = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'listeners-1', language: 'listeners', source: '', sourcePath: 'Note.md', width: 600 }));
        assert.equal(drawn.isDrawn, true);
        const attributeOf = (className) => {
            const element = harness.window.document.querySelector('.' + className);
            return element ? element.getAttribute('data-graphite-listens') : undefined;
        };
        assert.equal(attributeOf('listens-menu'), 'menu');
        assert.equal(attributeOf('listens-hover'), 'hover');
        assert.equal(attributeOf('listens-press'), 'press');
        assert.equal(attributeOf('listens-drag'), 'drag');
        assert.equal(attributeOf('listens-drop'), 'drop');
        assert.equal(attributeOf('listens-several'), 'drop menu press', 'each kind once, in the order the plugin first listened');
        assert.equal(attributeOf('listens-nothing'), null, 'a click needs no attribute: a copy turns it into a tap');
        assert.match(drawn.html, /<div class="listens-menu" data-graphite-listens="menu">menu<\/div>/);
    } finally {
        harness.close();
    }
});

const shoutingPlugin = pluginSource(`
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownPostProcessor((element) => {
            for (const code of Array.from(element.querySelectorAll('code'))) {
                if (code.textContent.startsWith('shout:')) code.replaceWith(createEl('strong', { text: code.textContent.slice(6).toUpperCase() }));
            }
        });
    }
}`);

test('a block\'s copy names its note in data-graphite-source-path and each task box its line', async () => {
    const harness = await startRuntime({ files: { 'Folder/Note.md': '- [ ] Call `shout:bob`\n- [x] Done\n' } });
    try {
        await installAndLoadPlugin(harness, { manifest: Object.assign({}, manifest, { id: 'shout', name: 'Shout' }), mainSource: shoutingPlugin });
        await settle();
        const answer = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'section-1', source: '- [ ] Call `shout:bob`\n- [x] Done',
                                                  sourcePath: 'Folder/Note.md', firstLine: 0, lineCount: 2 }));
        assert.equal(answer.isChanged, true);
        const container = harness.window.document.querySelector('.graphite-reading-block');
        assert.equal(container.getAttribute('data-graphite-source-path'), 'Folder/Note.md');
        const boxes = Array.from(harness.window.document.querySelectorAll('input[data-graphite-task-line]'));
        assert.deepEqual(boxes.map((box) => box.getAttribute('data-graphite-task-line')), ['0', '1'], 'the line of the task inside the section, counted from 0');
        assert.deepEqual(boxes.map((box) => box.checked), [false, true]);
    } finally {
        harness.close();
    }
});

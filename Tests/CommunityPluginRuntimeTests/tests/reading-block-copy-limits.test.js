// The limits on the copies of plugin blocks that cross to Graphite: the largest block copy,
// the time changes are gathered, how long a processor is waited for, and the most style text
// sent with a copy. Each is a limit of the runtime's reading file.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, waitUntil } = require('../support/runtime-harness');

const manifest = { id: 'bulky', name: 'Bulky', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

const maximumBlockCopyCharacters = 4 * 1024 * 1024;
const maximumCopyStyleCharacters = 3 * 1024 * 1024;

/// A plugin whose `bulky` blocks hold as many characters as their source says, whose `stuck`
/// blocks never finish drawing, and whose `growing` blocks change after they are drawn.
const bulkyPlugin = `"use strict";
var obsidian = require("obsidian");
class ExamplePlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownCodeBlockProcessor('bulky', (source, element) => {
            element.createEl('p', { text: 'a'.repeat(Number(source)) });
        });
        this.registerMarkdownCodeBlockProcessor('stuck', () => new Promise(() => {}));
        this.registerMarkdownCodeBlockProcessor('growing', (source, element) => {
            const paragraph = element.createEl('p', { text: 'first' });
            globalThis.growingParagraph = paragraph;
        });
    }
}
module.exports = ExamplePlugin;`;

async function drawBulky(harness, characterCount, blockIdentifier) {
    return plain(await harness.send({
        operation: 'codeBlock.render', blockIdentifier, language: 'bulky', source: String(characterCount), sourcePath: 'Note.md', width: 600,
    }));
}

test('a block copy of exactly 4 MiB characters is sent whole and one character more is replaced by a too-large message', async () => {
    const harness = await startRuntime({});
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: bulkyPlugin });
        const empty = await drawBulky(harness, 0, 'block-empty');
        assert.equal(empty.isDrawn, true);
        const overheadCharacters = empty.html.length;

        const atTheLimit = await drawBulky(harness, maximumBlockCopyCharacters - overheadCharacters, 'block-at-limit');
        assert.equal(atTheLimit.html.length, maximumBlockCopyCharacters);
        assert.match(atTheLimit.html, /^<div class="block-language-bulky"><p>a+<\/p><\/div>$/);

        const overTheLimit = await drawBulky(harness, maximumBlockCopyCharacters - overheadCharacters + 1, 'block-over-limit');
        assert.equal(overTheLimit.html, '<div class="graphite-plugin-error">This block is too large for Graphite to show (4 MB).</div>');
    } finally {
        harness.close();
    }
});

test('a processor that writes 5 MiB gets the too-large message naming its size in whole megabytes', async () => {
    const harness = await startRuntime({});
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: bulkyPlugin });
        const answer = await drawBulky(harness, 5 * 1024 * 1024, 'block-huge');
        assert.equal(answer.isDrawn, true);
        assert.equal(answer.html, '<div class="graphite-plugin-error">This block is too large for Graphite to show (5 MB).</div>');
    } finally {
        harness.close();
    }
});

/// Replaces the page's timer with one that records each delay and runs the callback at once
/// when told to, so a wait of seconds is read from the delay asked for without waiting.
function recordTimers(harness, delaysRunAtOnce) {
    const recordedDelays = [];
    const realSetTimeout = harness.window.setTimeout.bind(harness.window);
    harness.window.setTimeout = (callback, delay, ...rest) => {
        recordedDelays.push(delay);
        return realSetTimeout(callback, delaysRunAtOnce.has(delay) ? 0 : delay, ...rest);
    };
    return recordedDelays;
}

test('a processor is waited for at most 15 seconds and then the block is sent as it is', async () => {
    const harness = await startRuntime({});
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: bulkyPlugin });
        const recordedDelays = recordTimers(harness, new Set([15000]));
        const answer = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block-stuck', language: 'stuck', source: '', sourcePath: 'Note.md', width: 600 }));
        assert.equal(answer.isDrawn, true, 'the block is drawn although the processor never finished');
        assert.equal(answer.html, '<div class="block-language-stuck"></div>');
        assert.ok(recordedDelays.includes(15000), 'the wait for the processor is 15000 milliseconds: ' + recordedDelays);
    } finally {
        harness.close();
    }
});

test('changes to a drawn block are gathered for 60 milliseconds before one new copy is sent', async () => {
    const harness = await startRuntime({});
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: bulkyPlugin });
        const recordedDelays = recordTimers(harness, new Set());
        await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block-growing', language: 'growing', source: '', sourcePath: 'Note.md', width: 600 });
        // The copy sent with the answer is the block as drawn: nothing more is sent for it.
        assert.equal(harness.host.notificationsOf('codeBlock.changed').length, 0);

        // The plugin's own drawing and these changes all fall inside one gathering delay.
        const paragraph = harness.window.growingParagraph;
        paragraph.textContent = 'second';
        paragraph.textContent = 'third';
        paragraph.setAttribute('data-step', 'last');
        await waitUntil(() => harness.host.notificationsOf('codeBlock.changed').length === 1);
        assert.deepEqual(recordedDelays.filter((delay) => delay === 60), [60], 'every change asks for the same one copy, after 60 milliseconds');
        assert.match(plain(harness.host.notificationsOf('codeBlock.changed').at(-1)).html, /<p data-step="last">third<\/p>/);
    } finally {
        harness.close();
    }
});

/// The characters of every style element in the page, which is what the limit counts.
function styleCharacterTotal(harness) {
    return Array.from(harness.window.document.querySelectorAll('style')).reduce((sum, element) => sum + element.textContent.length, 0);
}

async function applyTheme(harness, themeCharacterCount) {
    const css = 'body { --x: 1; }\n' + 'p'.repeat(Math.max(0, themeCharacterCount - 'body { --x: 1; }\n'.length));
    await harness.send({ operation: 'appearance.styles', styles: { theme: { name: 'Sized', css }, snippets: [{ name: 'boxes', css: 'blockquote { border: 1px solid; }' }] }, appearanceConfiguration: {} });
}

test('copies get the theme while the page\'s styles total 3 MiB and lose only the theme with one character more', async () => {
    const harness = await startRuntime({});
    try {
        await applyTheme(harness, 100);
        const otherCharacters = styleCharacterTotal(harness) - 100;
        const themeCharactersAtLimit = maximumCopyStyleCharacters - otherCharacters;

        await applyTheme(harness, themeCharactersAtLimit);
        assert.equal(styleCharacterTotal(harness), maximumCopyStyleCharacters);
        const atTheLimit = harness.runtime.pluginStyles();
        assert.ok(atTheLimit.includes('--x: 1'), 'the theme is kept at exactly 3 MiB');
        assert.ok(atTheLimit.includes('blockquote'));

        await applyTheme(harness, themeCharactersAtLimit + 1);
        assert.equal(styleCharacterTotal(harness), maximumCopyStyleCharacters + 1);
        const overTheLimit = harness.runtime.pluginStyles();
        assert.ok(!overTheLimit.includes('--x: 1'), 'the theme is dropped from copies');
        assert.ok(overTheLimit.includes('blockquote'), 'snippets are kept');
        assert.ok(harness.window.document.head.querySelector('style[data-graphite-theme="Sized"]'), 'the page keeps its theme');
    } finally {
        harness.close();
    }
});

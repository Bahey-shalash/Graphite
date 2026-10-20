'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, plain, waitUntil } = require('../support/runtime-harness');

const lectureNote = [
    '---',
    'aliases: [Signals]',
    'tags: [course, ee/signals]',
    'related: "[[Fourier]]"',
    '---',
    '# Lecture 3',
    '',
    'Sampling links to [[Fourier#Transform|the transform]] and ![[diagram.png]].',
    'See [notes](Notes/Extra%20notes.md) and https://example.com, plus #exam and `#notatag`.',
    '',
    '## Exercises',
    '- [ ] first task ^task-one',
    '    - nested item',
    '- [x] done',
    '',
    '```python',
    '# not a heading [[NotALink]] #nottag',
    '```',
    '',
    'Closing paragraph. ^closing',
    '',
    'Footnote reference[^1].',
    '',
    '[^1]: The footnote.',
].join('\n');

test('a note is read into Obsidian\'s cached metadata with positions', async () => {
    const harness = await startRuntime({ files: { 'Course/Lecture 3.md': lectureNote, 'Fourier.md': '# Transform', 'Notes/Extra notes.md': 'x', 'diagram.png': 'png' } });
    try {
        await harness.waitForMetadata();
        const cache = plain(harness.app.metadataCache.getCache('Course/Lecture 3.md'));
        assert.deepEqual(cache.frontmatter, { aliases: ['Signals'], tags: ['course', 'ee/signals'], related: '[[Fourier]]' });
        assert.deepEqual(cache.frontmatterPosition, { start: { line: 0, col: 0, offset: 0 }, end: { line: 4, col: 3, offset: lectureNote.indexOf('\n---', 4) + 4 } });
        assert.deepEqual(cache.frontmatterLinks, [{ key: 'related', link: 'Fourier', original: '[[Fourier]]', displayText: 'Fourier' }]);
        assert.deepEqual(cache.headings.map((heading) => [heading.heading, heading.level, heading.position.start.line]), [['Lecture 3', 1, 5], ['Exercises', 2, 10]]);
        assert.deepEqual(cache.links.map((link) => [link.link, link.displayText]), [['Fourier#Transform', 'the transform'], ['Notes/Extra notes.md', 'notes']]);
        const wikilink = cache.links[0];
        assert.deepEqual(wikilink.position.start, { line: 7, col: 18, offset: lectureNote.indexOf('[[Fourier#') });
        assert.deepEqual(cache.embeds.map((embed) => embed.link), ['diagram.png']);
        assert.deepEqual(cache.tags.map((tag) => tag.tag), ['#exam']);
        const examOffset = lectureNote.indexOf('#exam');
        assert.deepEqual(cache.tags[0].position, { start: { line: 8, col: examOffset - lectureNote.indexOf('See [notes]'), offset: examOffset }, end: { line: 8, col: examOffset - lectureNote.indexOf('See [notes]') + 5, offset: examOffset + 5 } });
        assert.deepEqual(cache.listItems.map((item) => [item.position.start.line, item.parent, item.task === undefined ? null : item.task, item.id || null]), [
            [11, -11, ' ', 'task-one'], [12, 11, null, null], [13, -11, 'x', null],
        ]);
        assert.deepEqual(Object.keys(cache.blocks).sort(), ['closing', 'task-one']);
        assert.equal(cache.blocks.closing.position.start.line, 19);
        assert.deepEqual(cache.sections.map((section) => section.type), ['yaml', 'heading', 'paragraph', 'heading', 'list', 'code', 'paragraph', 'paragraph', 'footnoteDefinition']);
        assert.deepEqual(cache.footnotes.map((footnote) => footnote.id), ['1']);
        assert.deepEqual(cache.footnoteRefs.map((reference) => reference.id), ['1']);
        assert.deepEqual(plain(harness.obsidian.getAllTags(harness.app.metadataCache.getCache('Course/Lecture 3.md'))), ['#course', '#ee/signals', '#exam']);
    } finally {
        harness.close();
    }
});

test('links resolve as in Obsidian: beside the note, from the root, then by name, ignoring case', async () => {
    const harness = await startRuntime({ files: {
        'A/Topic.md': 'beside',
        'Topic.md': 'root',
        'Deep/Nested/Unique Name.md': 'deep',
        'Images/Photo.PNG': 'png',
        'A/Source.md': '[[Topic]] [[unique name]] [[Nested/Unique Name]] [[photo.png]] [[Missing]] [[../Topic]]',
        'B/Source.md': '[[Topic]]',
    } });
    try {
        await harness.waitForMetadata();
        const metadataCache = harness.app.metadataCache;
        assert.equal(metadataCache.getFirstLinkpathDest('Topic', 'A/Source.md').path, 'A/Topic.md');
        assert.equal(metadataCache.getFirstLinkpathDest('Topic', 'B/Source.md').path, 'Topic.md');
        assert.equal(metadataCache.getFirstLinkpathDest('unique name', 'A/Source.md').path, 'Deep/Nested/Unique Name.md');
        assert.equal(metadataCache.getFirstLinkpathDest('Nested/Unique Name', 'A/Source.md').path, 'Deep/Nested/Unique Name.md');
        assert.equal(metadataCache.getFirstLinkpathDest('photo.png', 'A/Source.md').path, 'Images/Photo.PNG');
        assert.equal(metadataCache.getFirstLinkpathDest('../Topic', 'A/Source.md').path, 'Topic.md');
        assert.equal(metadataCache.getFirstLinkpathDest('Missing', 'A/Source.md'), null);
        assert.deepEqual(plain(metadataCache.resolvedLinks['A/Source.md']), { 'A/Topic.md': 1, 'Deep/Nested/Unique Name.md': 2, 'Images/Photo.PNG': 1, 'Topic.md': 1 });
        assert.deepEqual(plain(metadataCache.unresolvedLinks['A/Source.md']), { Missing: 1 });
        assert.equal(metadataCache.fileToLinktext(harness.app.vault.getFileByPath('Deep/Nested/Unique Name.md'), 'A/Source.md'), 'Unique Name');
        assert.equal(metadataCache.fileToLinktext(harness.app.vault.getFileByPath('A/Topic.md'), 'B/Source.md'), 'A/Topic', 'a name two files share is written as a path');
    } finally {
        harness.close();
    }
});

test('a changed note is read again, and plugins hear of it', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'Before [[Old]]', 'New.md': '' } });
    try {
        await harness.waitForMetadata();
        const changes = [];
        harness.app.metadataCache.on('changed', (file, text, cache) => changes.push([file.path, text, cache.links.map((link) => link.link)]));
        await harness.app.vault.modify(harness.app.vault.getFileByPath('Note.md'), 'After [[New]]');
        await waitUntil(() => changes.length === 1);
        assert.deepEqual(plain(changes), [['Note.md', 'After [[New]]', ['New']]]);
        assert.deepEqual(plain(harness.app.metadataCache.resolvedLinks['Note.md']), { 'New.md': 1 });
    } finally {
        harness.close();
    }
});

test('notes a file provider keeps only in the cloud are not downloaded for metadata', async () => {
    const harness = await startRuntime({ files: { 'Local.md': '# Here', 'Cloud.md': '# There' }, isStarting: false });
    try {
        harness.host.notDownloadedPaths.add('Cloud.md');
        await harness.send({ operation: 'runtime.start', vault: { name: 'Test', identifier: 'cloud', configuration: {} }, device: {}, recentFiles: [] });
        harness.app = harness.runtime.app;
        await harness.waitForMetadata();
        assert.ok(harness.app.metadataCache.getCache('Local.md'));
        assert.equal(harness.app.metadataCache.getCache('Cloud.md'), null);
        const cloudReads = harness.host.requests.filter((request) => request.operation === 'vault.read' && request.path === 'Cloud.md');
        assert.ok(cloudReads.every((request) => request.isSkippingCloudFiles === true));
    } finally {
        harness.close();
    }
});

test('resolveSubpath finds headings and blocks', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '# One\ntext\n## Two\nmore ^block\n# Three\n' } });
    try {
        await harness.waitForMetadata();
        const cache = harness.app.metadataCache.getCache('Note.md');
        const heading = harness.obsidian.resolveSubpath(cache, '#One#Two');
        assert.equal(heading.type, 'heading');
        assert.equal(heading.current.heading, 'Two');
        assert.equal(heading.next.heading, 'Three');
        const block = harness.obsidian.resolveSubpath(cache, '#^block');
        assert.equal(block.type, 'block');
        assert.equal(block.start.line, 3);
        assert.equal(harness.obsidian.resolveSubpath(cache, '#Nowhere'), null);
    } finally {
        harness.close();
    }
});

// BUG-RUNTIME-06: an older read that answered late replaced the text a plugin had just written.
test('a note\'s metadata is not replaced by an older read that answers after a plugin\'s write', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'Before [[Old]]', 'Old.md': '', 'New.md': '' } });
    try {
        await harness.waitForMetadata();
        // The next read of the note is answered with the text it found, but only once the
        // test releases it, as a large note's answer can arrive after a later small one.
        let releaseHeldRead = null;
        let isHoldingNextRead = true;
        const answerMessage = harness.host.handle.bind(harness.host);
        harness.host.handle = async (message) => {
            const answer = await answerMessage(message);
            if (message.operation !== 'vault.read' || message.path !== 'Note.md' || !isHoldingNextRead) return answer;
            isHoldingNextRead = false;
            await new Promise((resolve) => { releaseHeldRead = resolve; });
            return answer;
        };
        const changes = [];
        harness.app.metadataCache.on('changed', (file, text, cache) => changes.push(cache.links.map((link) => link.link)));
        // Graphite reports a change to the note: the cache reads it, and that read is held.
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Note.md', stat: null, isReloadNeeded: true }] });
        await waitUntil(() => releaseHeldRead !== null);
        // A plugin writes the note; its own read of the written text answers at once.
        await harness.app.vault.modify(harness.app.vault.getFileByPath('Note.md'), 'After [[New]]');
        await waitUntil(() => changes.length === 1);
        releaseHeldRead();
        // The held read's answer (the old text) arrives last.
        await waitUntil(() => harness.app.metadataCache.activeReadCount === 0);
        assert.deepEqual(plain(harness.app.metadataCache.getCache('Note.md').links.map((link) => link.link)), ['New']);
        assert.deepEqual(plain(changes), [['New']], 'plugins hear of the written text once, and never of the older text');
        assert.deepEqual(plain(harness.app.metadataCache.resolvedLinks['Note.md']), { 'New.md': 1 });
    } finally {
        harness.close();
    }
});

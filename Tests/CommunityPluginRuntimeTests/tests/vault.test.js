'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, settle, plain } = require('../support/runtime-harness');

test('the vault lists files and folders but not hidden ones', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'a', 'Course/Lecture 1.md': 'b', 'Course/Slides/deck.pdf': 'c', '.obsidian/app.json': '{}', '.trash/old.md': 'd' } });
    try {
        const vault = harness.app.vault;
        assert.deepEqual(plain(vault.getFiles().map((file) => file.path).sort()), ['Course/Lecture 1.md', 'Course/Slides/deck.pdf', 'Note.md']);
        assert.deepEqual(plain(vault.getMarkdownFiles().map((file) => file.basename).sort()), ['Lecture 1', 'Note']);
        const lecture = vault.getAbstractFileByPath('Course/Lecture 1.md');
        assert.ok(lecture instanceof harness.obsidian.TFile);
        assert.equal(lecture.extension, 'md');
        assert.equal(lecture.parent.path, 'Course');
        assert.ok(lecture.parent instanceof harness.obsidian.TFolder);
        assert.equal(vault.getRoot().path, '/');
        assert.ok(vault.getRoot().isRoot());
        assert.equal(vault.getAbstractFileByPath('.obsidian/app.json'), null);
        assert.equal(vault.getFolderByPath('Course/Slides').children.length, 1);
    } finally {
        harness.close();
    }
});

test('reading and modifying a note goes through the vault folder', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'first' } });
    try {
        const vault = harness.app.vault;
        const note = vault.getFileByPath('Note.md');
        const modified = [];
        vault.on('modify', (file) => modified.push(file.path));
        assert.equal(await vault.read(note), 'first');
        await vault.modify(note, 'second');
        assert.equal(harness.readVaultFile('Note.md'), 'second');
        assert.deepEqual(modified, ['Note.md']);
        assert.equal(note.stat.size, 6);
    } finally {
        harness.close();
    }
});

test('a write based on a stale read is refused instead of overwriting', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'original' } });
    try {
        const vault = harness.app.vault;
        const note = vault.getFileByPath('Note.md');
        await vault.read(note);
        harness.writeVaultFile('Note.md', 'changed in another app');
        await assert.rejects(vault.modify(note, 'plugin version'), /changed outside this plugin/);
        assert.equal(harness.readVaultFile('Note.md'), 'changed in another app');
        assert.equal(harness.host.notificationsOf('plugin.writeConflict').length, 1);
    } finally {
        harness.close();
    }
});

test('process reads again when the file changed and applies the change to the new text', async () => {
    const harness = await startRuntime({ files: { 'Log.md': 'one\n' } });
    try {
        const vault = harness.app.vault;
        const log = vault.getFileByPath('Log.md');
        let calls = 0;
        const result = await vault.process(log, (text) => {
            calls += 1;
            if (calls === 1) harness.writeVaultFile('Log.md', 'one\ntwo\n');
            return text + 'three\n';
        });
        assert.equal(result, 'one\ntwo\nthree\n');
        assert.equal(harness.readVaultFile('Log.md'), 'one\ntwo\nthree\n');
        assert.equal(harness.host.notificationsOf('plugin.writeConflict').length, 0);
    } finally {
        harness.close();
    }
});

test('process calls made at the same time each apply, one after another, as in Obsidian', async () => {
    const harness = await startRuntime({ files: { 'Log.md': '' } });
    try {
        const vault = harness.app.vault;
        const log = vault.getFileByPath('Log.md');
        const letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
        await Promise.all(letters.map((letter) => vault.process(log, (text) => text + letter + '\n')));
        assert.equal(harness.readVaultFile('Log.md'), letters.map((letter) => letter + '\n').join(''));
        assert.equal(harness.host.notificationsOf('plugin.writeConflict').length, 0);
    } finally {
        harness.close();
    }
});

test('property types a plugin sets without waiting are all written to types.json together', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'a', '.obsidian/types.json': '{\n  "types": {\n    "tags": "tags"\n  }\n}' } });
    try {
        const typeManager = harness.app.metadataTypeManager;
        const names = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth'];
        // As Tasks does at load: each call starts before the one before it has finished.
        const saves = names.map((name) => typeManager.setType(name, 'checkbox'));
        assert.equal(typeManager.getAssignedType('tenth'), 'checkbox', 'the type is known at once, as in Obsidian');
        await Promise.all(saves);
        const expectedTypes = { tags: 'tags' };
        for (const name of names) expectedTypes[name] = 'checkbox';
        assert.equal(harness.readVaultFile('.obsidian/types.json'), JSON.stringify({ types: expectedTypes }, null, 2));
        assert.equal(harness.host.notificationsOf('plugin.writeConflict').length, 0);
        assert.equal(harness.host.notificationsOf('plugin.failure').length, 0);
    } finally {
        harness.close();
    }
});

test('create, rename, copy and delete keep the tree and its events in step', async () => {
    const harness = await startRuntime({ files: { 'Existing.md': 'x' } });
    try {
        const vault = harness.app.vault;
        const events = [];
        for (const name of ['create', 'rename', 'delete']) vault.on(name, (file, oldPath) => events.push(name + ':' + file.path + (oldPath ? '<' + oldPath : '')));
        const created = await vault.create('Folder/New note.md', 'hello');
        assert.equal(created.path, 'Folder/New note.md');
        assert.equal(harness.readVaultFile('Folder/New note.md'), 'hello');
        await assert.rejects(vault.create('Existing.md', 'again'), /File already exists/);
        await vault.rename(created, 'Folder/Renamed.md');
        assert.ok(harness.vaultFileExists('Folder/Renamed.md'));
        assert.equal(created.path, 'Folder/Renamed.md');
        assert.equal(created.basename, 'Renamed');
        const copy = await vault.copy(created, 'Copy.md');
        assert.equal(copy.path, 'Copy.md');
        await vault.delete(copy);
        assert.equal(harness.vaultFileExists('Copy.md'), false);
        assert.deepEqual(events, [
            'create:Folder', 'create:Folder/New note.md', 'rename:Folder/Renamed.md<Folder/New note.md', 'create:Copy.md', 'delete:Copy.md',
        ]);
    } finally {
        harness.close();
    }
});

test('renaming a folder renames everything inside it', async () => {
    const harness = await startRuntime({ files: { 'A/one.md': '1', 'A/B/two.md': '2' } });
    try {
        const vault = harness.app.vault;
        const renamed = [];
        vault.on('rename', (file, oldPath) => renamed.push(oldPath + '>' + file.path));
        await vault.rename(vault.getFolderByPath('A'), 'C');
        assert.ok(vault.getFileByPath('C/B/two.md'));
        assert.equal(vault.getFileByPath('A/one.md'), null);
        assert.deepEqual(renamed.sort(), ['A/B/two.md>C/B/two.md', 'A/B>C/B', 'A/one.md>C/one.md', 'A>C']);
    } finally {
        harness.close();
    }
});

test('the adapter reaches hidden files and binary data', async () => {
    const harness = await startRuntime({ files: { '.obsidian/plugins/example/data.json': '{"count":1}' } });
    try {
        const adapter = harness.app.vault.adapter;
        assert.equal(await adapter.exists('.obsidian/plugins/example/data.json'), true);
        assert.equal(await adapter.exists('.obsidian/plugins/example/missing.json'), false);
        assert.deepEqual(plain(await adapter.list('.obsidian/plugins')), { files: [], folders: ['.obsidian/plugins/example'] });
        const bytes = new Uint8Array([0, 1, 2, 250]);
        await adapter.writeBinary('Images/raw.bin', bytes.buffer);
        const readBack = new Uint8Array(await adapter.readBinary('Images/raw.bin'));
        assert.deepEqual(Array.from(readBack), [0, 1, 2, 250]);
        assert.ok(harness.app.vault.getFileByPath('Images/raw.bin'), 'a visible file written through the adapter joins the tree');
        const stat = await adapter.stat('Images');
        assert.equal(stat.type, 'folder');
    } finally {
        harness.close();
    }
});

test('a note that starts with a byte order mark keeps it when a plugin rewrites it', async () => {
    const harness = await startRuntime({ files: { 'Marked.md': Buffer.concat([Buffer.from([0xEF, 0xBB, 0xBF]), Buffer.from('text')]) } });
    try {
        const vault = harness.app.vault;
        const note = vault.getFileByPath('Marked.md');
        assert.equal(await vault.read(note), 'text');
        await vault.modify(note, 'new text');
        const bytes = require('node:fs').readFileSync(require('node:path').join(harness.vaultFolder, 'Marked.md'));
        assert.deepEqual(Array.from(bytes.subarray(0, 3)), [0xEF, 0xBB, 0xBF]);
        assert.equal(bytes.subarray(3).toString('utf8'), 'new text');
    } finally {
        harness.close();
    }
});

test('changes Graphite reports reach the tree as Obsidian events', async () => {
    const harness = await startRuntime({ files: { 'Kept.md': 'a', 'Gone.md': 'b' } });
    try {
        const vault = harness.app.vault;
        const events = [];
        for (const name of ['create', 'modify', 'delete', 'rename']) vault.on(name, (file) => events.push(name + ':' + file.path));
        harness.writeVaultFile('Kept.md', 'edited elsewhere');
        harness.writeVaultFile('Arrived/New.md', 'synced');
        require('node:fs').rmSync(require('node:path').join(harness.vaultFolder, 'Gone.md'));
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Kept.md', stat: null, isReloadNeeded: true }, { path: 'Arrived', stat: null, isReloadNeeded: true }, { path: 'Gone.md', stat: null }] });
        assert.deepEqual(events, ['modify:Kept.md', 'create:Arrived', 'create:Arrived/New.md', 'delete:Gone.md']);
        await harness.send({ operation: 'vault.changes', moves: [{ path: 'Kept.md', destinationPath: 'Moved.md' }] });
        assert.ok(vault.getFileByPath('Moved.md'));
        assert.equal(events.at(-1), 'rename:Moved.md');
    } finally {
        harness.close();
    }
});

test('paths outside the vault are refused', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        await assert.rejects(harness.app.vault.adapter.read('../outside.txt'), /outside the selected vault|does not exist/);
    } finally {
        harness.close();
    }
});

test('file manager writes frontmatter and generates links with the vault settings', async () => {
    const harness = await startRuntime({ files: { 'Folder/Note.md': '---\ntitle: Old\n---\nBody\n', 'Other.md': 'x' }, configuration: { useMarkdownLinks: false } });
    try {
        const app = harness.app;
        const note = app.vault.getFileByPath('Folder/Note.md');
        await app.fileManager.processFrontMatter(note, (frontmatter) => { frontmatter.title = 'New'; frontmatter.tags = ['a']; });
        assert.equal(harness.readVaultFile('Folder/Note.md'), '---\ntitle: New\ntags:\n  - a\n---\nBody\n');
        await app.fileManager.processFrontMatter(note, () => {});
        assert.equal(harness.readVaultFile('Folder/Note.md'), '---\ntitle: New\ntags:\n  - a\n---\nBody\n');
        await harness.waitForMetadata();
        assert.equal(app.fileManager.generateMarkdownLink(app.vault.getFileByPath('Other.md'), 'Folder/Note.md'), '[[Other]]');
        app.vault.configuration.useMarkdownLinks = true;
        assert.equal(app.fileManager.generateMarkdownLink(app.vault.getFileByPath('Other.md'), 'Folder/Note.md', '#Part', 'Label'), '[Label](Other.md#Part)');
        app.vault.configuration.attachmentFolderPath = './attachments';
        assert.equal(await app.fileManager.getAvailablePathForAttachment('image.png', 'Folder/Note.md'), 'Folder/attachments/image.png');
        await settle();
    } finally {
        harness.close();
    }
});

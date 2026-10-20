// `Vault.process` and `FileManager.processFrontMatter`: how many times a changed file is read
// again, what is written, and how a note's line endings and dates come back.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime } = require('../support/runtime-harness');

function writesTo(harness, vaultPath) {
    return harness.host.requests.filter((message) => message.operation === 'vault.write' && message.path === vaultPath);
}

test('process reads again up to three times, applies the transform to the latest text, and writes on the third', async () => {
    const harness = await startRuntime({ files: { 'Log.md': 'one\n' } });
    try {
        const vault = harness.app.vault;
        const log = vault.getFileByPath('Log.md');
        const textsTransformed = [];
        const result = await vault.process(log, (text) => {
            textsTransformed.push(text);
            // Another app changes the note after each of the first two reads.
            if (textsTransformed.length === 1) harness.writeVaultFile('Log.md', 'one\ntwo\n');
            if (textsTransformed.length === 2) harness.writeVaultFile('Log.md', 'one\ntwo\nthree\n');
            return text + 'plugin\n';
        });
        assert.deepEqual(textsTransformed, ['one\n', 'one\ntwo\n', 'one\ntwo\nthree\n'], 'each attempt transforms the text just read');
        assert.equal(result, 'one\ntwo\nthree\nplugin\n');
        assert.equal(harness.readVaultFile('Log.md'), 'one\ntwo\nthree\nplugin\n');
        assert.equal(harness.host.notificationsOf('plugin.writeConflict').length, 0, 'the retried conflicts are not reported');
        assert.equal(writesTo(harness, 'Log.md').length, 3, 'two refused writes and the one that stayed');
    } finally {
        harness.close();
    }
});

test('process gives up after three reads and reports the conflict only for the last attempt', async () => {
    const harness = await startRuntime({ files: { 'Log.md': 'start\n' } });
    try {
        const vault = harness.app.vault;
        const log = vault.getFileByPath('Log.md');
        let attempts = 0;
        await assert.rejects(vault.process(log, (text) => {
            attempts += 1;
            harness.writeVaultFile('Log.md', 'changed ' + attempts + '\n');
            return text + 'plugin\n';
        }), /changed outside this plugin/);
        assert.equal(attempts, 3);
        assert.equal(harness.readVaultFile('Log.md'), 'changed 3\n', 'the plugin\'s text never overwrote the other app\'s');
        const conflicts = harness.host.notificationsOf('plugin.writeConflict');
        assert.equal(conflicts.length, 1, 'only the last attempt is reported');
        assert.equal(conflicts[0].path, 'Log.md');
    } finally {
        harness.close();
    }
});

test('process writes nothing when the transform returns the text it was given', async () => {
    const harness = await startRuntime({ files: { 'Log.md': 'same\n' } });
    try {
        const vault = harness.app.vault;
        const log = vault.getFileByPath('Log.md');
        assert.equal(await vault.process(log, (text) => text), 'same\n');
        assert.equal(writesTo(harness, 'Log.md').length, 0);
    } finally {
        harness.close();
    }
});

test('processFrontMatter writes nothing for an unchanged object', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '---\ntitle: A\n---\nBody\n' } });
    try {
        const note = harness.app.vault.getFileByPath('Note.md');
        await harness.app.fileManager.processFrontMatter(note, (frontmatter) => { frontmatter.title = 'A'; });
        assert.equal(writesTo(harness, 'Note.md').length, 0);
        assert.equal(harness.readVaultFile('Note.md'), '---\ntitle: A\n---\nBody\n');
    } finally {
        harness.close();
    }
});

test('processFrontMatter keeps the note\'s CRLF line endings, reads a date as text and writes it back quoted', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '---\r\ndate: 2024-05-01\r\ntags:\r\n  - a\r\n---\r\nBody\r\n' } });
    try {
        const note = harness.app.vault.getFileByPath('Note.md');
        await harness.app.fileManager.processFrontMatter(note, (frontmatter) => {
            assert.equal(frontmatter.date, '2024-05-01', 'the core schema reads a date as text, not as a Date');
            frontmatter.status = 'done';
        });
        // The text is read with the core schema, but written with js-yaml's default dump, which
        // quotes a string that would read as a date.
        assert.equal(harness.readVaultFile('Note.md'), "---\r\ndate: '2024-05-01'\r\ntags:\r\n  - a\r\nstatus: done\r\n---\r\nBody\r\n");
    } finally {
        harness.close();
    }
});

test('processFrontMatter dumps long values on one line and adds frontmatter to a note without any', async () => {
    const harness = await startRuntime({ files: { 'Plain.md': 'Body\n', 'Long.md': '---\ntitle: A\n---\nBody\n' } });
    try {
        const longValue = 'word '.repeat(40).trim();
        const long = harness.app.vault.getFileByPath('Long.md');
        await harness.app.fileManager.processFrontMatter(long, (frontmatter) => { frontmatter.summary = longValue; });
        assert.equal(harness.readVaultFile('Long.md'), '---\ntitle: A\nsummary: ' + longValue + '\n---\nBody\n', 'no line wrapping');

        const plain = harness.app.vault.getFileByPath('Plain.md');
        await harness.app.fileManager.processFrontMatter(plain, (frontmatter) => { frontmatter.status = 'new'; });
        assert.equal(harness.readVaultFile('Plain.md'), '---\nstatus: new\n---\nBody\n');
    } finally {
        harness.close();
    }
});

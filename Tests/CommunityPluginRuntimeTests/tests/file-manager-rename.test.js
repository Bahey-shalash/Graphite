// `FileManager.renameFile` answers a plugin from what Graphite's move came to: a rename Graphite
// refuses rejects the plugin's promise and leaves the file where it was.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime } = require('../support/runtime-harness');

test('renaming onto a name that is taken rejects and leaves the file and the vault\'s tree where they were', async () => {
    const harness = await startRuntime({ files: { 'A.md': 'first', 'B.md': 'second' } });
    try {
        const { vault, fileManager } = harness.app;
        const note = vault.getFileByPath('A.md');
        await assert.rejects(fileManager.renameFile(note, 'B.md'), (error) => error.name === 'HostOperationError' && error.kind === 'exists');
        assert.equal(note.path, 'A.md');
        assert.equal(vault.getFileByPath('A.md'), note);
        assert.equal(harness.readVaultFile('A.md'), 'first');
        assert.equal(harness.readVaultFile('B.md'), 'second');
    } finally {
        harness.close();
    }
});

test('a rename Graphite answers as alreadyExists or cancelled rejects with that kind, and a successful one moves the file in the tree', async () => {
    const harness = await startRuntime({ files: { 'A.md': 'first' } });
    try {
        const { vault, fileManager } = harness.app;
        const note = vault.getFileByPath('A.md');
        const transport = harness.runtime.hostBridge.transport;
        for (const kind of ['alreadyExists', 'cancelled', 'unavailable']) {
            harness.runtime.hostBridge.transport = async (message) => (message.operation === 'workspace.renameFile' ? { failure: { kind, message: 'Not renamed.' } } : transport(message));
            await assert.rejects(fileManager.renameFile(note, 'Renamed.md'), (error) => error.kind === kind);
            assert.equal(note.path, 'A.md', kind + ' leaves the file where it was');
        }
        harness.runtime.hostBridge.transport = transport;
        await fileManager.renameFile(note, 'Renamed.md');
        assert.equal(note.path, 'Renamed.md');
        assert.equal(vault.getFileByPath('A.md'), null);
        assert.equal(vault.getFileByPath('Renamed.md'), note);
    } finally {
        harness.close();
    }
});

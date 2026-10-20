// The data adapter's answers for paths that cannot be in the vault or are not there, and the
// addresses plugins get for vault files (`getResourcePath`).
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, plain } = require('../support/runtime-harness');

test('the adapter answers a path outside the vault as missing, and a missing file is read as ENOENT', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'text' } });
    try {
        const adapter = harness.app.vault.adapter;
        assert.equal(await adapter.exists('../outside.md'), false);
        assert.equal(await adapter.stat('../outside.md'), null);
        assert.equal(await adapter.exists('Note.md'), true);
        assert.equal(await adapter.exists('missing.md'), false);
        assert.equal(await adapter.stat('missing.md'), null);
        await assert.rejects(adapter.read('missing.md'), (error) => {
            assert.equal(error.code, 'ENOENT');
            assert.equal(error.kind, 'missing');
            return true;
        });
        await assert.rejects(adapter.read('../outside.md'), (error) => error.kind === 'outsideVault' && error.code === undefined);
    } finally {
        harness.close();
    }
});

test('the adapter answers a path Graphite calls invalid as missing', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        harness.runtime.hostBridge.transport = async (message) => (message.operation === 'vault.stat' ? { failure: { kind: 'invalidPath', message: 'Not a path.' } } : {});
        assert.equal(await harness.app.vault.adapter.exists('a/../../b'), false);
        assert.equal(await harness.app.vault.adapter.stat('a/../../b'), null);
    } finally {
        harness.close();
    }
});

test('getResourcePath joins the host\'s prefix with the percent-encoded path components', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const adapter = harness.app.vault.adapter;
        assert.equal(adapter.getResourcePath('A b/ü.png'), 'graphite-vault://resource/A%20b/%C3%BC.png', 'without a host prefix the runtime\'s own default applies');
        assert.equal(harness.obsidian.Platform.resourcePathPrefix, 'graphite-vault://resource/');

        await harness.send({
            operation: 'runtime.start',
            vault: { name: 'Test Vault', identifier: 'test-vault', configurationDirectory: '.obsidian', configuration: {}, corePlugins: [] },
            device: { isPhone: false, resourcePathPrefix: 'graphite-plugins://vault/' },
            appearance: 'light', recentFiles: [],
        });
        assert.equal(harness.obsidian.Platform.resourcePathPrefix, 'graphite-plugins://vault/');
        assert.equal(harness.app.vault.adapter.getResourcePath('A b/ü.png'), 'graphite-plugins://vault/A%20b/%C3%BC.png');
        assert.equal(harness.app.vault.adapter.getResourcePath('100%.png'), 'graphite-plugins://vault/100%25.png', 'a percent sign is encoded once');
        assert.equal(harness.app.vault.adapter.getResourcePath('/Folder//x?y#z.png'), 'graphite-plugins://vault/Folder/x%3Fy%23z.png', 'the path is normalized first, and reserved characters are encoded');
    } finally {
        harness.close();
    }
});

test('a vault file\'s resource address ends with its modified time', async () => {
    const harness = await startRuntime({ files: { 'Picture.png': 'bytes' } });
    try {
        await harness.send({
            operation: 'runtime.start',
            vault: { name: 'Test Vault', identifier: 'test-vault', configurationDirectory: '.obsidian', configuration: {}, corePlugins: [] },
            device: { isPhone: false, resourcePathPrefix: 'graphite-plugins://vault/' },
            appearance: 'light', recentFiles: [],
        });
        const file = harness.app.vault.getFileByPath('Picture.png');
        const address = harness.app.vault.getResourcePath(file);
        assert.match(address, /^graphite-plugins:\/\/vault\/Picture\.png\?[\d.]+$/);
        assert.equal(address.split('?')[1], String(file.stat.mtime), 'the query is the file\'s modification time in milliseconds');
        assert.deepEqual(plain(harness.app.vault.getResourcePath({ path: 'Folder/Σ.png', stat: { mtime: 5 } })), 'graphite-plugins://vault/Folder/%CE%A3.png?5');
    } finally {
        harness.close();
    }
});

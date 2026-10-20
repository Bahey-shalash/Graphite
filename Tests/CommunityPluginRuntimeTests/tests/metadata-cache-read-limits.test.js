// What the metadata cache reads while it fills: no note over 4 MiB, at most four reads at
// once, and no note text kept afterwards.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, plain } = require('../support/runtime-harness');

const maximumIndexedNoteBytes = 4 * 1024 * 1024;
const concurrentNoteReads = 4;

/// Starts the runtime on a vault whose `vault.read` answers are slowed a little, so reads
/// that are allowed together overlap, and records how many were in flight at once.
async function startCountingReads(files) {
    const harness = await startRuntime({ files, isStarting: false });
    const reads = { inFlight: 0, mostInFlight: 0, requests: [] };
    const answerMessage = harness.host.handle.bind(harness.host);
    harness.host.handle = async (message) => {
        if (message.operation !== 'vault.read') return answerMessage(message);
        reads.requests.push(plain(message));
        reads.inFlight += 1;
        reads.mostInFlight = Math.max(reads.mostInFlight, reads.inFlight);
        await new Promise((resolve) => setTimeout(resolve, 5));
        try { return await answerMessage(message); } finally { reads.inFlight -= 1; }
    };
    await harness.send({ operation: 'runtime.start', vault: { name: 'Test', identifier: 'reads', configuration: {} }, device: {}, recentFiles: [] });
    harness.app = harness.runtime.app;
    await harness.waitForMetadata();
    return { harness, reads };
}

test('the initial read of many notes never has more than four reads in flight', async () => {
    const files = {};
    for (let position = 0; position < 24; position += 1) files['Note ' + position + '.md'] = '# Note ' + position + '\n';
    const { harness, reads } = await startCountingReads(files);
    try {
        assert.equal(reads.requests.length, 24, 'every note is read once');
        assert.equal(reads.mostInFlight, concurrentNoteReads, 'four are read together, never a fifth');
    } finally {
        harness.close();
    }
});

test('every note is read with a limit of 4 MiB and without downloading it from the cloud', async () => {
    const { harness, reads } = await startCountingReads({ 'Small.md': '# Small\n' });
    try {
        assert.deepEqual(reads.requests, [{ operation: 'vault.read', path: 'Small.md', encoding: 'text', isSkippingCloudFiles: true, maximumBytes: maximumIndexedNoteBytes }]);
    } finally {
        harness.close();
    }
});

test('a note over 4 MiB has no metadata while a note of exactly 4 MiB has', async () => {
    const heading = '# Heading\n';
    const atTheLimit = heading + 'a'.repeat(maximumIndexedNoteBytes - heading.length);
    const overTheLimit = '# Larger\n' + 'a'.repeat(maximumIndexedNoteBytes);
    const { harness } = await startCountingReads({ 'At limit.md': atTheLimit, 'Over limit.md': overTheLimit });
    try {
        assert.equal(Buffer.byteLength(atTheLimit), maximumIndexedNoteBytes);
        assert.deepEqual(plain(harness.app.metadataCache.getCache('At limit.md').headings.map((entry) => entry.heading)), ['Heading']);
        assert.equal(harness.app.metadataCache.getCache('Over limit.md'), null);
    } finally {
        harness.close();
    }
});

test('the cache keeps what it parsed from a note and not the note\'s text', async () => {
    const bodySentence = 'A sentence in the body that no heading, link or tag repeats.';
    const { harness } = await startCountingReads({ 'Note.md': '# Heading\n\n' + bodySentence + '\n\nSee [[Other]] #tag\n', 'Other.md': 'x' });
    try {
        const cache = harness.app.metadataCache.getCache('Note.md');
        assert.ok(cache.headings.length === 1 && cache.links.length === 1 && cache.tags.length === 1);
        assert.ok(!JSON.stringify(plain(cache)).includes(bodySentence), 'the cached entry has no body text');
        assert.deepEqual(Object.keys(plain(cache)).sort(), ['headings', 'links', 'sections', 'tags']);
    } finally {
        harness.close();
    }
});

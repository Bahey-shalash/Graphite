// The links a plugin's page can follow: only web and mail addresses leave for the browser or Mail,
// notes open through Graphite, and nothing else (scripts, files, other schemes) does anything.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, plain, settle } = require('../support/runtime-harness');

/// Clicks an anchor with `href` in the plugin page, as a tap on a link a plugin drew would.
function clickLink(harness, href, className) {
    const anchor = harness.window.document.createElement('a');
    anchor.setAttribute('href', href);
    if (className) anchor.className = className;
    harness.window.document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
}

function openedExternally(harness) {
    return plain(harness.host.notificationsOf('workspace.openExternalLink').map((notification) => notification.address));
}

function openedInGraphite(harness) {
    return plain(harness.host.openedFiles.map((request) => [request.operation, request.linktext]));
}

test('a tapped link to a script, a file or another scheme does nothing, and the page stays', async () => {
    const harness = await startRuntime({ files: { 'Other.md': 'Other' } });
    try {
        const refused = [
            'javascript:alert(1)', 'JavaScript:alert(1)', ' javascript:alert(1)'.trim(), 'file:///etc/hosts', 'data:text/html,<script>alert(1)</script>',
            'ftp://example.com/file', 'tel:+41000000000', 'view-source:https://example.com', 'graphite://open?note=Other', 'blob:https://graphite-plugins.test/1234',
        ];
        for (const href of refused) clickLink(harness, href);
        clickLink(harness, 'javascript:alert(1)', 'internal-link');
        clickLink(harness, '#heading');
        clickLink(harness, '');
        await settle();
        assert.deepEqual(openedExternally(harness), []);
        assert.deepEqual(openedInGraphite(harness), []);
        assert.equal(harness.window.location.href, 'https://graphite-plugins.test/', 'the page stayed where it was');
    } finally {
        harness.close();
    }
});

test('a tapped web or mail link goes to Graphite to open outside the app, and a note link opens the note', async () => {
    const harness = await startRuntime({ files: { 'Other.md': 'Other' } });
    try {
        clickLink(harness, 'https://example.com/page');
        clickLink(harness, 'HTTP://example.com/upper');
        clickLink(harness, 'mailto:someone@example.com');
        clickLink(harness, 'Other', 'internal-link');
        await settle();
        assert.deepEqual(openedExternally(harness), ['https://example.com/page', 'HTTP://example.com/upper', 'mailto:someone@example.com']);
        assert.deepEqual(openedInGraphite(harness), [['workspace.openLinkText', 'Other']]);
    } finally {
        harness.close();
    }
});

test('window.open sends only web and mail addresses to Graphite and opens no window', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const results = [
            harness.window.open('https://example.com/a'),
            harness.window.open('mailto:someone@example.com'),
            harness.window.open('javascript:alert(1)'),
            harness.window.open('file:///etc/hosts'),
            harness.window.open('data:text/html,hello'),
            harness.window.open('ftp://example.com/file'),
            harness.window.open('http://[bad'),
        ];
        await settle();
        assert.deepEqual(results, [null, null, null, null, null, null, null]);
        assert.deepEqual(openedExternally(harness), ['https://example.com/a', 'mailto:someone@example.com']);
    } finally {
        harness.close();
    }
});

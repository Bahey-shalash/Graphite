// The type and state a plugin's view gives Graphite so the view opens again after a restart:
// the state is the view's `getState()` as JSON text, kept only up to 64 KiB.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

const largeStatePlugin = `"use strict";
var obsidian = require("obsidian");
class StateView extends obsidian.ItemView {
    getViewType() { return 'state-view'; }
    getDisplayText() { return 'State'; }
    getState() { return { data: this.leaf.stateSize === undefined ? '' : 'x'.repeat(this.leaf.stateSize) }; }
    async setState(state) {}
    async onOpen() {}
}
class ExamplePlugin extends obsidian.Plugin {
    onload() { this.registerView('state-view', (leaf) => new StateView(leaf)); }
}
module.exports = ExamplePlugin;`;

function listedStateOf(harness, leaf) {
    return plain(harness.host.notificationsOf('views.changed').at(-1).views).find((view) => view.leafIdentifier === leaf.id).state;
}

test('a view\'s saved state is its getState() as JSON text, and is sent only up to 65,536 characters', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: largeStatePlugin });
        const workspace = harness.app.workspace;
        const leaf = workspace.getLeaf('tab');
        await leaf.setViewState({ type: 'state-view', active: true });
        await settle();
        const wrapperLength = JSON.stringify({ data: '' }).length;

        leaf.stateSize = 65536 - wrapperLength;
        workspace.notifyLeavesChanged();
        const withinLimit = listedStateOf(harness, leaf);
        assert.equal(withinLimit.length, 65536);
        assert.deepEqual(JSON.parse(withinLimit), { data: 'x'.repeat(leaf.stateSize) });

        leaf.stateSize += 1;
        workspace.notifyLeavesChanged();
        assert.equal(listedStateOf(harness, leaf), null, 'one character more is not sent');

        leaf.stateSize = 3;
        workspace.notifyLeavesChanged();
        assert.equal(listedStateOf(harness, leaf), '{"data":"xxx"}');
    } finally {
        harness.close();
    }
});

test('a view reopens from its saved type and state, in a tab or in the right sidebar', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: largeStatePlugin });
        await harness.send({ operation: 'plugins.layoutReady' });
        const before = harness.app.workspace.pluginLeaves.length;

        const inTab = plain(await harness.send({ operation: 'view.restore', viewType: 'state-view', state: '{"data":"abc"}', placement: 'tab' }));
        assert.equal(inTab.isOpened, true);
        const inSidebar = plain(await harness.send({ operation: 'view.restore', viewType: 'state-view', state: '{}', placement: 'right' }));
        assert.equal(inSidebar.isOpened, true);
        assert.equal(harness.app.workspace.pluginLeaves.length, before + 2);
        const views = plain(harness.host.notificationsOf('views.changed').at(-1).views);
        assert.deepEqual(views.map((view) => view.placement).sort(), ['sidebar', 'tab']);
        const unparsable = plain(await harness.send({ operation: 'view.restore', viewType: 'state-view', state: 'not json', placement: 'tab' }));
        assert.equal(unparsable.isOpened, true, 'a state that is not JSON opens the view with no state');
    } finally {
        harness.close();
    }
});

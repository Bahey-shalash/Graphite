'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime } = require('../support/runtime-harness');

function pressKey(harness, key, modifierFlags) {
    const event = new harness.window.KeyboardEvent('keydown', Object.assign({ key, bubbles: true, cancelable: true }, modifierFlags));
    harness.window.document.dispatchEvent(event);
    return event;
}

test('Scope runs a handler registered with Mod when Command is pressed', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { Scope } = harness.obsidian;
        const scope = new Scope();
        let callCount = 0;
        scope.register(['Mod'], 'Enter', () => { callCount += 1; return false; });
        const event = new harness.window.KeyboardEvent('keydown', { key: 'Enter', metaKey: true, cancelable: true });
        assert.equal(scope.handleKeyEvent(event), true);
        assert.equal(callCount, 1);
        assert.equal(event.defaultPrevented, true);
    } finally {
        harness.close();
    }
});

test('Scope matches Mod together with other modifiers in any order', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { Scope } = harness.obsidian;
        const scope = new Scope();
        let callCount = 0;
        scope.register(['Shift', 'Mod'], 'k', () => { callCount += 1; return false; });
        scope.handleKeyEvent(new harness.window.KeyboardEvent('keydown', { key: 'K', metaKey: true, shiftKey: true, cancelable: true }));
        assert.equal(callCount, 1);
        scope.handleKeyEvent(new harness.window.KeyboardEvent('keydown', { key: 'K', metaKey: true, cancelable: true }));
        assert.equal(callCount, 1, 'Command alone is not Command and Shift');
    } finally {
        harness.close();
    }
});

test('Scope keeps Ctrl and Meta apart from Mod', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { Scope } = harness.obsidian;
        const scope = new Scope();
        const pressed = [];
        scope.register(['Ctrl'], 'Enter', () => { pressed.push('Ctrl'); return false; });
        scope.register(['Meta'], 'Enter', () => { pressed.push('Meta'); return false; });
        scope.handleKeyEvent(new harness.window.KeyboardEvent('keydown', { key: 'Enter', ctrlKey: true, cancelable: true }));
        scope.handleKeyEvent(new harness.window.KeyboardEvent('keydown', { key: 'Enter', metaKey: true, cancelable: true }));
        assert.deepEqual(pressed, ['Ctrl', 'Meta']);
    } finally {
        harness.close();
    }
});

test('A modal runs its Mod+Enter handler when Command-Return is pressed', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { Modal } = harness.obsidian;
        const modal = new Modal(harness.app);
        let submitCount = 0;
        modal.scope.register(['Mod'], 'Enter', () => { submitCount += 1; return false; });
        modal.open();
        const event = pressKey(harness, 'Enter', { metaKey: true });
        assert.equal(submitCount, 1);
        assert.equal(event.defaultPrevented, true);
        modal.close();
    } finally {
        harness.close();
    }
});

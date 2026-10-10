// Runs real Obsidian community plugins, built from their sources at the commits in
// compatibility/compatibility-plugins.json (`npm run build-compatibility-plugins`), in the
// runtime. Each plugin's expected behavior is what was observed and checked here; a change
// in it fails the test so the compatibility notes in Docs/Community-plugins.md stay true.
// Plugins that are not built are skipped.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const builtFolder = path.join(__dirname, '..', 'compatibility', 'built');

function builtPlugin(pluginIdentifier) {
    const folder = path.join(builtFolder, pluginIdentifier);
    if (!fileSystem.existsSync(path.join(folder, 'main.js'))) return null;
    const read = (name) => (fileSystem.existsSync(path.join(folder, name)) ? fileSystem.readFileSync(path.join(folder, name), 'utf8') : '');
    return { manifest: JSON.parse(read('manifest.json')), mainSource: read('main.js'), styles: read('styles.css') };
}

const studyVault = {
    'Welcome.md': '# Welcome\n\nA note with #tag and [[Other]].\n',
    'Other.md': '---\ntags: [x]\n---\nOther note\n',
    'Templates/Daily.md': '# <% tp.date.now() %>\n',
};

/// Loads a plugin as Graphite does at launch: vault read, a note open, layout ready.
async function loadInStudyVault(pluginIdentifier, options) {
    const pluginPackage = builtPlugin(pluginIdentifier);
    const harness = await startRuntime({ files: studyVault });
    if (options && options.withWorkerStandIn) installWorkerStandIn(harness.window);
    if (options && options.withIndexedDatabase) installIndexedDatabase(harness.window);
    await harness.waitForMetadata();
    await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'Welcome.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Welcome.md', 0) } });
    const answer = plain(await installAndLoadPlugin(harness, pluginPackage));
    await harness.send({ operation: 'plugins.layoutReady' });
    await settle();
    await settle();
    const commandList = harness.host.notificationsOf('commands.changed').at(-1);
    const commandNames = commandList ? plain(commandList.commands.map((command) => command.name)) : [];
    const unsupported = plain(harness.host.notificationsOf('plugin.unsupportedFeature').map((notification) => notification.featureName));
    const pageErrors = harness.consoleMessages.filter((message) => message.level === 'error').map((message) => message.text);
    return { harness, answer, commandNames, unsupported, pageErrors };
}

/// jsdom has no IndexedDB, which WebKit has; fake-indexeddb is a complete implementation
/// of it in JavaScript, kept in memory.
function installIndexedDatabase(window) {
    const fakeIndexedDatabase = require('fake-indexeddb');
    for (const name of Object.keys(fakeIndexedDatabase)) window[name] = fakeIndexedDatabase[name];
}

/// jsdom has no Web Workers, which WebKit has. The stand-in accepts messages and never
/// answers, so a plugin that starts a worker can load; what the worker does is not tested.
function installWorkerStandIn(window) {
    window.URL.createObjectURL = () => 'blob:graphite-test-stand-in';
    window.URL.revokeObjectURL = () => {};
    window.Worker = class WorkerStandIn {
        postMessage() {}
        terminate() {}
        addEventListener() {}
        removeEventListener() {}
    };
}

async function settingRowCount(harness, pluginIdentifier) {
    const answer = plain(await harness.send({ operation: 'settings.show', pluginIdentifier }));
    await settle();
    const count = harness.window.document.querySelectorAll('.graphite-plugin-surface .setting-item').length;
    await harness.send({ operation: 'surface.closed' });
    return { hasSettingTab: answer.hasSettingTab, count };
}

test('Obsidian\'s sample plugin: commands, modal, settings and editor command', { skip: !builtPlugin('sample-plugin') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('sample-plugin');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Sample Plugin: Open modal (simple)', 'Sample Plugin: Replace selected content', 'Sample Plugin: Open modal (complex)']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(await settingRowCount(harness, 'sample-plugin'), { hasSettingTab: true, count: 1 });
        await harness.send({ operation: 'command.run', commandIdentifier: 'sample-plugin:open-modal-simple' });
        assert.equal(harness.window.document.querySelector('.modal-content').textContent, 'Woah!');
        harness.window.document.querySelector('.modal-close-button').click();
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'sample-plugin:replace-selected', activeDocument: { path: 'Welcome.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Welcome.md', 2, 9) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        assert.equal(harness.host.editorSessions.get('Welcome.md').text, '# Sample editor command\n\nA note with #tag and [[Other]].\n');
        const ribbon = plain(harness.host.notificationsOf('ribbon.changed').at(-1).items);
        assert.deepEqual(ribbon.map((item) => item.title), ['Sample']);
    } finally {
        harness.close();
    }
});

test('Natural Language Dates: loads, inserts dates into the note, settings drawn', { skip: !builtPlugin('nldates-obsidian') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('nldates-obsidian');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.equal(commandNames.length, 8);
        assert.ok(commandNames.includes('Natural Language Dates: Insert the current date'));
        assert.deepEqual(unsupported, ['Suggestions while typing in a note']);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(await settingRowCount(harness, 'nldates-obsidian'), { hasSettingTab: true, count: 7 });
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'nldates-obsidian:nlp-today', activeDocument: { path: 'Welcome.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Welcome.md', 0) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        const today = harness.window.moment().format('YYYY-MM-DD');
        assert.ok(harness.host.editorSessions.get('Welcome.md').text.startsWith(today), 'today\'s date is inserted at the cursor in the default format');
    } finally {
        harness.close();
    }
});

test('QuickAdd: loads, registers its commands and draws its declarative settings', { skip: !builtPlugin('quickadd') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('quickadd');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, [
            'QuickAdd: Run', 'QuickAdd: Return to prompt', 'QuickAdd: New note from template', 'QuickAdd: Apply template to active note',
            'QuickAdd: Reload (dev)', 'QuickAdd: Open settings', 'QuickAdd: Open AI Assistant settings',
        ]);
        assert.deepEqual(unsupported, ['Command-line handlers']);
        assert.deepEqual(pageErrors, []);
        const settings = await settingRowCount(harness, 'quickadd');
        assert.equal(settings.hasSettingTab, true);
        assert.ok(settings.count >= 5, 'QuickAdd\'s groups of settings are drawn (' + settings.count + ' rows)');
    } finally {
        harness.close();
    }
});

test('Tag Wrangler: loads without commands (it works through tag menus Graphite does not offer yet)', { skip: !builtPlugin('tag-wrangler') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('tag-wrangler');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, []);
        assert.deepEqual(unsupported, ['Hover previews']);
        assert.deepEqual(pageErrors, []);
    } finally {
        harness.close();
    }
});

test('Templater: loads with CodeMirror and replaces templates in the open note', { skip: !builtPlugin('templater-obsidian') }, async () => {
    const { harness, answer, commandNames, unsupported } = await loadInStudyVault('templater-obsidian');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, [
            'Templater: Open insert template modal', 'Templater: Replace templates in the active file',
            'Templater: Jump to next cursor location', 'Templater: Create new note from template',
        ]);
        assert.ok(unsupported.includes('Syntax highlighting modes (CodeMirror 5)'));
        const settings = await settingRowCount(harness, 'templater-obsidian');
        assert.equal(settings.hasSettingTab, true);
        assert.ok(settings.count >= 5, 'Templater\'s settings are drawn (' + settings.count + ' rows)');
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'templater-obsidian:replace-in-file-templater', activeDocument: { path: 'Templates/Daily.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Templates/Daily.md', 0) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        const today = harness.window.moment().format('YYYY-MM-DD');
        const deadline = Date.now() + 3000;
        while (!harness.readVaultFile('Templates/Daily.md').includes(today) && Date.now() < deadline) await settle();
        assert.equal(harness.readVaultFile('Templates/Daily.md'), '# ' + today + '\n', 'Templater rewrote the note through the vault');
    } finally {
        harness.close();
    }
});

test('Dataview: loads with CodeMirror; code block queries are reported as not drawn in notes', { skip: !builtPlugin('dataview') }, async () => {
    const { harness, answer, commandNames, unsupported } = await loadInStudyVault('dataview', { withWorkerStandIn: true, withIndexedDatabase: true });
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.ok(commandNames.length >= 1);
        assert.ok(unsupported.includes('Drawing “dataview” code blocks in notes'));
        assert.ok(unsupported.includes('CodeMirror editor extensions'));
    } finally {
        harness.close();
    }
});

test('Tasks: loads, toggles a task done through the editor change, draws its declarative settings', { skip: !builtPlugin('obsidian-tasks-plugin') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('obsidian-tasks-plugin');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.ok(commandNames.includes('Tasks: Toggle task done'));
        assert.deepEqual(unsupported, ['Changing how notes look in reading view', 'Drawing “tasks” code blocks in notes', 'CodeMirror editor extensions', 'Suggestions while typing in a note']);
        assert.deepEqual(pageErrors, []);
        assert.ok((await settingRowCount(harness, 'obsidian-tasks-plugin')).count >= 5);
        harness.writeVaultFile('Tasks.md', '- [ ] Write the report\n');
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'obsidian-tasks-plugin:toggle-done', activeDocument: { path: 'Tasks.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Tasks.md', 4) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        const today = harness.window.moment().format('YYYY-MM-DD');
        assert.equal(harness.host.editorSessions.get('Tasks.md').text, '- [x] Write the report ✅ ' + today + '\n');
    } finally {
        harness.close();
    }
});

test('Outliner: loads and draws its settings; its commands need CodeMirror\'s editor view and say so', { skip: !builtPlugin('obsidian-outliner') }, async () => {
    const { harness, answer, commandNames, unsupported } = await loadInStudyVault('obsidian-outliner');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.equal(commandNames.length, 7);
        assert.deepEqual(unsupported, ['CodeMirror editor extensions']);
        assert.ok((await settingRowCount(harness, 'obsidian-outliner')).count >= 5);
        harness.writeVaultFile('List.md', '- one\n- two\n');
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'obsidian-outliner:move-list-item-down', activeDocument: { path: 'List.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('List.md', 2) } }));
        assert.equal(outcome.outcome, 'failed');
        assert.match(outcome.message, /CodeMirror editor view \(editor\.cm\)/);
        assert.equal(harness.host.editorSessions.get('List.md').text, '- one\n- two\n', 'the note is left as it was');
    } finally {
        harness.close();
    }
});

test('Kanban: refused at load, because it borrows Obsidian\'s CodeMirror note editor', { skip: !builtPlugin('obsidian-kanban') }, async () => {
    const { harness, answer } = await loadInStudyVault('obsidian-kanban');
    try {
        assert.equal(answer.isLoaded, false);
        assert.match(answer.errorMessage, /embedded “\.md” views \(embedRegistry\)/);
    } finally {
        harness.close();
    }
});

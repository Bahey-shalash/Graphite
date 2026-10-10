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

/// The text the plugin panel shows, with runs of white space as one space.
function surfaceText(harness) {
    return harness.window.document.querySelector('.graphite-plugin-surface').textContent.replace(/\s+/g, ' ');
}

test('Recent Files: lists the notes opened in Graphite in its view and keeps them in data.json', { skip: !builtPlugin('recent-files-obsidian') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('recent-files-obsidian');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Recent Files: Open']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(await settingRowCount(harness, 'recent-files-obsidian'), { hasSettingTab: true, count: 5 });
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'Other.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Other.md', 0) } });
        await settle();
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'recent-files-obsidian:recent-files-open' })), { outcome: 'ran' });
        await settle();
        const views = plain(harness.host.notificationsOf('views.changed').at(-1).views);
        assert.deepEqual(views.map((view) => view.title), ['Recent files']);
        assert.match(surfaceText(harness), /Recent files.*Other/);
        const recentFiles = JSON.parse(harness.readVaultFile('.obsidian/plugins/recent-files-obsidian/data.json')).recentFiles;
        assert.ok(recentFiles.some((file) => file.path === 'Other.md'), 'the opened note is kept in the plugin\'s data.json');
    } finally {
        harness.close();
    }
});

test('Style Settings: loads and says no theme or snippet offers settings', { skip: !builtPlugin('obsidian-style-settings') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('obsidian-style-settings');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Style Settings: Show style settings view']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'obsidian-style-settings' });
        await settle();
        assert.match(surfaceText(harness), /No style settings found/);
    } finally {
        harness.close();
    }
});

test('Homepage: loads, adds its commands and ribbon button, draws its settings', { skip: !builtPlugin('homepage') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('homepage');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Homepage: Copy debug info', 'Homepage: Open homepage', 'Homepage: Set to active file']);
        assert.deepEqual(unsupported, ['Command-line handlers']);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(plain(harness.host.notificationsOf('ribbon.changed').at(-1).items.map((item) => item.title)), ['Open homepage']);
        const settings = await settingRowCount(harness, 'homepage');
        assert.equal(settings.hasSettingTab, true);
        assert.ok(settings.count >= 10, 'Homepage\'s settings are drawn (' + settings.count + ' rows)');
    } finally {
        harness.close();
    }
});

test('Calendar: opens its view with the current month', { skip: !builtPlugin('calendar') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('calendar');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Calendar: Open view', 'Calendar: Open Weekly Note', 'Calendar: Reveal active note']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(await settingRowCount(harness, 'calendar'), { hasSettingTab: true, count: 5 });
        const views = plain(harness.host.notificationsOf('views.changed').at(-1).views);
        assert.deepEqual(views.map((view) => view.title), ['Calendar']);
        assert.deepEqual(plain(await harness.send({ operation: 'view.show', leafIdentifier: views[0].leafIdentifier })), { isShown: true });
        await settle();
        assert.ok(surfaceText(harness).includes(harness.window.moment().format('MMM YYYY')), 'the month grid shows the current month');
    } finally {
        harness.close();
    }
});

test('Advanced Tables: formats the table at the cursor through the editor change; its editor extensions do not run', { skip: !builtPlugin('table-editor-obsidian') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('table-editor-obsidian');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.equal(commandNames.length, 22);
        assert.ok(commandNames.includes('Advanced Tables: Format table at the cursor'));
        assert.deepEqual(unsupported, ['CodeMirror editor extensions']);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(await settingRowCount(harness, 'table-editor-obsidian'), { hasSettingTab: true, count: 4 });
        harness.writeVaultFile('Table.md', '| a | bb |\n|-|-|\n| 1 | 22222 |\n');
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'table-editor-obsidian:format-table', activeDocument: { path: 'Table.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Table.md', 2) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        assert.equal(harness.host.editorSessions.get('Table.md').text, '| a   | bb    |\n| --- | ----- |\n| 1   | 22222 |\n');
    } finally {
        harness.close();
    }
});

test('Commander: loads and draws its settings pages, with Obsidian\'s hidden status bar and settings header', { skip: !builtPlugin('cmdr') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('cmdr');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Commander: Open Commander Settings']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'cmdr' });
        await settle();
        assert.match(surfaceText(harness), /General.*Ribbon.*Mobile Toolbar.*Macros/);
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.failure')), []);
    } finally {
        harness.close();
    }
});

test('Iconize: loads and draws its settings; its icons in notes need reading view and editor changes', { skip: !builtPlugin('obsidian-icon-folder') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('obsidian-icon-folder');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Iconize: Set icon for file']);
        assert.deepEqual(unsupported, ['Changing how notes look in reading view', 'Suggestions while typing in a note', 'CodeMirror editor extensions']);
        assert.deepEqual(pageErrors, []);
        const settings = await settingRowCount(harness, 'obsidian-icon-folder');
        assert.equal(settings.hasSettingTab, true);
        assert.ok(settings.count >= 15, 'Iconize\'s settings are drawn (' + settings.count + ' rows)');
    } finally {
        harness.close();
    }
});

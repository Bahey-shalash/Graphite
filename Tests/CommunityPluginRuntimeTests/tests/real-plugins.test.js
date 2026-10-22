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
const vm = require('node:vm');
const { startRuntime, installAndLoadPlugin, plain, settle, waitUntil } = require('../support/runtime-harness');

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
    const harness = await startRuntime({ files: Object.assign({}, studyVault, options && options.files) });
    if (options && options.withWorkerStandIn) installWorkerStandIn(harness.window);
    if (options && options.withRunningWorkers) installRunningWorkers(harness.window);
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

/// A copy of a message made with another JavaScript context's own `Map`, `Set`, `Array`,
/// `Object` and `Date`, as a browser's structured clone gives the receiving side its own
/// objects (Dataview tells its `Map`s apart with `instanceof`).
function copyIntoRealm(value, realm) {
    if (value === null || typeof value !== 'object') return value;
    if (value instanceof Map || Object.prototype.toString.call(value) === '[object Map]') {
        const copy = new realm.Map();
        for (const [key, entry] of value.entries()) copy.set(copyIntoRealm(key, realm), copyIntoRealm(entry, realm));
        return copy;
    }
    if (Object.prototype.toString.call(value) === '[object Set]') {
        const copy = new realm.Set();
        for (const entry of value) copy.add(copyIntoRealm(entry, realm));
        return copy;
    }
    if (Array.isArray(value)) return realm.Array.from(value, (entry) => copyIntoRealm(entry, realm));
    if (Object.prototype.toString.call(value) === '[object Date]') return new realm.Date(value.getTime());
    const copy = new realm.Object();
    for (const key of Object.keys(value)) copy[key] = copyIntoRealm(value[key], realm);
    return copy;
}

/// jsdom has no Web Workers, which WebKit has. These run a worker's script, made from a
/// blob as Dataview makes its own, in a separate JavaScript context of Node, with messages
/// copied between the two as a browser copies them.
function installRunningWorkers(window) {
    const scriptsByAddress = new Map();
    let nextAddressNumber = 1;
    window.URL.createObjectURL = (blob) => {
        const address = 'blob:graphite-test-worker-' + nextAddressNumber;
        nextAddressNumber += 1;
        scriptsByAddress.set(address, new Promise((resolve) => {
            const reader = new window.FileReader();
            reader.onload = () => resolve(reader.result);
            reader.readAsText(blob);
        }));
        return address;
    };
    window.URL.revokeObjectURL = () => {};
    const pageRealm = { Map: window.Map, Set: window.Set, Array: window.Array, Object: window.Object, Date: window.Date };
    window.Worker = class RunningWorker {
        constructor(address) {
            this.listeners = [];
            this.onmessage = null;
            const page = this;
            const workerListeners = [];
            const workerScope = {
                postMessage(data) {
                    const event = { data: copyIntoRealm(data, pageRealm) };
                    setTimeout(() => {
                        if (page.onmessage) page.onmessage(event);
                        for (const listener of page.listeners.slice()) listener(event);
                    }, 0);
                },
                addEventListener(type, listener) { if (type === 'message') workerListeners.push(listener); },
                removeEventListener() {},
                onmessage: null,
                console, setTimeout, clearTimeout, setInterval, clearInterval, TextDecoder, TextEncoder,
            };
            workerScope.self = workerScope;
            const workerContext = vm.createContext(workerScope);
            const workerRealm = vm.runInContext('({ Map, Set, Array, Object, Date })', workerContext);
            this.deliver = (data) => {
                const event = { data: copyIntoRealm(data, workerRealm) };
                if (workerScope.onmessage) workerScope.onmessage(event);
                for (const listener of workerListeners.slice()) listener(event);
            };
            this.pendingMessages = [];
            this.isStarted = false;
            scriptsByAddress.get(address).then((script) => {
                vm.runInContext(script, workerContext);
                this.isStarted = true;
                for (const data of this.pendingMessages.splice(0)) this.deliver(data);
            });
        }
        postMessage(data) {
            if (this.isStarted) setTimeout(() => this.deliver(data), 0);
            else this.pendingMessages.push(data);
        }
        addEventListener(type, listener) { if (type === 'message') this.listeners.push(listener); }
        removeEventListener(type, listener) { this.listeners = this.listeners.filter((candidate) => candidate !== listener); }
        terminate() {}
    };
}

/// Draws a code block as Graphite's reading view asks for one, and waits until what the
/// plugin drew matches `expectedPattern`, from the answer or a later change.
async function drawCodeBlock(harness, message, expectedPattern) {
    const answer = plain(await harness.send(Object.assign({ operation: 'codeBlock.render', width: 700 }, message)));
    assert.equal(answer.isDrawn, true, answer.message);
    let html = answer.html;
    const changeCount = () => harness.host.notificationsOf('codeBlock.changed').filter((change) => change.blockIdentifier === message.blockIdentifier).length;
    await waitUntil(() => {
        const changes = harness.host.notificationsOf('codeBlock.changed').filter((change) => change.blockIdentifier === message.blockIdentifier);
        if (changes.length > 0) html = changes.at(-1).html;
        return expectedPattern.test(html);
    }, 10000).catch(() => { throw new Error('The block never showed ' + expectedPattern + '; it showed: ' + html + ' (' + changeCount() + ' changes)'); });
    return html;
}

/// The path of element positions from a block's element down to the first element in
/// it that `selector` matches, as Graphite's copy reports a tap.
function elementPathInBlock(harness, blockIdentifier, selector) {
    const blockElement = Array.from(harness.window.document.querySelectorAll('.graphite-reading-block'))
        .map((container) => container.firstElementChild).find((element) => element && element.closest('.graphite-reading-block'));
    const element = blockElement.querySelector(selector);
    const path = [];
    for (let current = element; current !== blockElement; current = current.parentElement) {
        path.unshift(Array.prototype.indexOf.call(current.parentElement.children, current));
    }
    return path;
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

test('Natural Language Dates: loads, inserts dates into the note, suggests dates after @, settings drawn', { skip: !builtPlugin('nldates-obsidian') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('nldates-obsidian');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.equal(commandNames.length, 8);
        assert.ok(commandNames.includes('Natural Language Dates: Insert the current date'));
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(await settingRowCount(harness, 'nldates-obsidian'), { hasSettingTab: true, count: 7 });
        // Typing `@tom`, a key at a time as Graphite sends each change, offers dates;
        // choosing one links tomorrow's date in its place.
        let suggested = null;
        for (const typed of ['@', '@t', '@to', '@tom']) {
            harness.writeVaultFile('Plan.md', 'Meet ' + typed + '\n');
            suggested = plain(await harness.send({ operation: 'editor.update', wantsSuggestions: true, requestIdentifier: 'dates-' + typed.length, activeDocument: { path: 'Plan.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Plan.md', 5 + typed.length) } }));
        }
        assert.equal(suggested.suggestion.pluginIdentifier, 'nldates-obsidian');
        assert.deepEqual(suggested.suggestion.items.map((item) => item.title), ['Tomorrow']);
        assert.deepEqual(plain(await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'dates-4', position: 0 })), { outcome: 'ran' });
        await settle();
        const tomorrow = harness.window.moment().add(1, 'day').format('YYYY-MM-DD');
        assert.equal(harness.host.editorSessions.get('Plan.md').text, 'Meet [[' + tomorrow + ']]\n');
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
        const noteMenu = plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'quickadd-menu', paths: ['Welcome.md'] }));
        assert.deepEqual(noteMenu.items.map((item) => item.title), ['QuickAdd: Apply template to active note']);
    } finally {
        harness.close();
    }
});

test('Tag Wrangler: loads without commands; the editor menu on a tag offers renaming it', { skip: !builtPlugin('tag-wrangler') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('tag-wrangler');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, []);
        assert.deepEqual(unsupported, ['Hover previews']);
        assert.deepEqual(pageErrors, []);
        // The cursor on `#tag` in "A note with #tag and [[Other]]."
        const onTag = plain(await harness.send({ operation: 'menu.editor', menuIdentifier: 'tag-menu', activeDocument: { path: 'Welcome.md', mode: 'source', editorSnapshot: harness.host.openNote('Welcome.md', 25) } }));
        assert.deepEqual(onTag.items.map((item) => item.title), ['Rename #tag', 'Create tag page']);
        assert.deepEqual(plain(await harness.send({ operation: 'menu.choose', menuIdentifier: 'tag-menu', position: 0 })), { outcome: 'ran' });
        await waitUntil(() => harness.window.document.querySelector('.modal-container'), 3000).catch(() => {
            throw new Error('No rename window; page errors: ' + JSON.stringify(harness.consoleMessages.filter((message) => message.level === 'error')) + ' failures: ' + JSON.stringify(plain(harness.host.notificationsOf('plugin.failure'))));
        });
        assert.match(harness.window.document.querySelector('.modal-container').textContent, /tag/i, 'its rename window opens on the plugin panel');
        const nameField = harness.window.document.querySelector('.modal-container input');
        nameField.value = 'topic';
        nameField.dispatchEvent(new harness.window.Event('input', { bubbles: true }));
        const continueButton = Array.from(harness.window.document.querySelectorAll('.modal-container button')).find((button) => button.textContent === 'Continue');
        continueButton.click();
        await waitUntil(() => harness.readVaultFile('Welcome.md').includes('#topic'), 5000).catch(() => {
            throw new Error('Not renamed; the panel shows: ' + (harness.window.document.querySelector('.modal-container') || { textContent: '(nothing)' }).textContent);
        });
        assert.equal(harness.readVaultFile('Welcome.md'), '# Welcome\n\nA note with #topic and [[Other]].\n', 'Tag Wrangler renamed the tag in the note through the vault');
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
        // A folder's menu offers a note from a template there; a note's does not.
        const folderMenu = plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'folder-menu', paths: ['Templates'] }));
        assert.deepEqual(folderMenu.items.map((item) => item.title), ['Create new note from template']);
        assert.deepEqual(plain(await harness.send({ operation: 'menu.choose', menuIdentifier: 'folder-menu', position: 0 })), { outcome: 'ran' });
        await settle();
        const templateChoice = Array.from(harness.window.document.querySelectorAll('.suggestion-item')).find((item) => item.textContent === 'Templates/Daily');
        templateChoice.click();
        await waitUntil(() => harness.vaultFileExists('Templates/Untitled.md'), 3000);
        await waitUntil(() => harness.readVaultFile('Templates/Untitled.md').includes(today), 3000);
        assert.equal(harness.readVaultFile('Templates/Untitled.md'), '# ' + today + '\n', 'the new note is made from the template in the folder');
        assert.deepEqual(plain(await harness.send({ operation: 'menu.file', menuIdentifier: 'note-menu', paths: ['Welcome.md'] })), { items: [] });
    } finally {
        harness.close();
    }
});

test('Dataview: a TABLE query in a note is drawn for the reading view from the vault\'s notes', { skip: !builtPlugin('dataview') }, async () => {
    const { harness, answer, commandNames, unsupported } = await loadInStudyVault('dataview', {
        withRunningWorkers: true, withIndexedDatabase: true,
        files: { 'Books/Dune.md': '---\nrating: 5\n---\nA book.\n', 'Books/Emma.md': '---\nrating: 4\n---\nAnother.\n' },
    });
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.ok(commandNames.length >= 1);
        assert.ok(!unsupported.some((feature) => /code blocks/.test(feature)), 'its code blocks are no longer reported as unsupported');
        assert.ok(unsupported.includes('CodeMirror editor extensions'));
        assert.deepEqual(plain(harness.host.notificationsOf('codeBlocks.changed').at(-1).languages).sort(), ['dataview', 'dataviewjs']);
        const html = await drawCodeBlock(harness, {
            blockIdentifier: 'dataview-table', language: 'dataview', source: 'TABLE rating FROM "Books" SORT rating DESC', sourcePath: 'Welcome.md',
        }, /Dune[\s\S]*Emma/);
        if (process.env.GRAPHITE_PRINT_BLOCKS) console.log(html);
        assert.match(html, /<table/);
        assert.match(html, /class="internal-link"[^>]*data-href="Books\/Dune.md"|data-href="Books\/Dune.md"[^>]*class="internal-link"/);
        assert.match(html, />5</);

        // An inline query in a note's text is a post-processor's work: that part of the note
        // is shown as Dataview draws it, while a part it does not change stays Graphite's.
        const inlineQuery = plain(await harness.send({
            operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'dataview-inline', source: 'Dune is rated `= [[Books/Dune]].rating` stars.', sourcePath: 'Welcome.md', width: 700,
        }));
        assert.equal(inlineQuery.isChanged, true);
        let inlineHTML = inlineQuery.html;
        await waitUntil(() => {
            const changes = harness.host.notificationsOf('codeBlock.changed').filter((change) => change.blockIdentifier === 'dataview-inline');
            if (changes.length > 0) inlineHTML = changes.at(-1).html;
            return /rated <span[^>]*>5<\/span>|rated .*>5</.test(inlineHTML);
        }, 10000).catch(() => { throw new Error('The inline query showed: ' + inlineHTML); });
        const plainSection = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'dataview-plain', source: 'Nothing to query here.', sourcePath: 'Welcome.md' }));
        assert.deepEqual(plainSection, { isDrawn: true, isChanged: false });
    } finally {
        harness.close();
    }
});

test('Tasks: loads, toggles a task done through the editor change, draws its declarative settings', { skip: !builtPlugin('obsidian-tasks-plugin') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('obsidian-tasks-plugin');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.ok(commandNames.includes('Tasks: Toggle task done'));
        assert.deepEqual(unsupported, ['CodeMirror editor extensions']);
        assert.deepEqual(pageErrors, []);
        assert.ok((await settingRowCount(harness, 'obsidian-tasks-plugin')).count >= 5);
        harness.writeVaultFile('Tasks.md', '- [ ] Write the report\n');
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'obsidian-tasks-plugin:toggle-done', activeDocument: { path: 'Tasks.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Tasks.md', 4) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        const today = harness.window.moment().format('YYYY-MM-DD');
        assert.equal(harness.host.editorSessions.get('Tasks.md').text, '- [x] Write the report ✅ ' + today + '\n');
        // Typing on a task line offers Tasks' fields; choosing one writes it into the line.
        const typeOnTaskLine = async (line, requestIdentifier) => {
            harness.writeVaultFile('Typing.md', line + '\n');
            return plain(await harness.send({ operation: 'editor.update', wantsSuggestions: true, requestIdentifier, activeDocument: { path: 'Typing.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Typing.md', line.length) } }));
        };
        const fieldSuggestions = await typeOnTaskLine('- [ ] Pay rent du', 'fields');
        assert.deepEqual(fieldSuggestions.suggestion.items.map((item) => item.title), ['📅 due date', '⏳ scheduled date']);
        await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'fields', position: 0 });
        await settle();
        assert.equal(harness.host.editorSessions.get('Typing.md').text, '- [ ] Pay rent 📅 \n');
        const dateSuggestions = await typeOnTaskLine('- [ ] Pay rent 📅 ', 'dates');
        assert.equal(dateSuggestions.suggestion.items[0].title, 'today (' + today + ')');
        await harness.send({ operation: 'editor.chooseSuggestion', requestIdentifier: 'dates', position: 0 });
        await settle();
        assert.equal(harness.host.editorSessions.get('Typing.md').text, '- [ ] Pay rent 📅 ' + today + ' \n');
    } finally {
        harness.close();
    }
});

test('Tasks: a query block lists the vault\'s open tasks, and ticking one there ticks it in its note', { skip: !builtPlugin('obsidian-tasks-plugin') }, async () => {
    const { harness, answer } = await loadInStudyVault('obsidian-tasks-plugin', {
        files: { 'Projects/Plan.md': '# Plan\n\n- [ ] Write the report\n- [x] Book the room\n- [ ] Send the slides\n' },
    });
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(plain(harness.host.notificationsOf('codeBlocks.changed').at(-1).languages), ['tasks']);
        const html = await drawCodeBlock(harness, { blockIdentifier: 'tasks-query', language: 'tasks', source: 'not done', sourcePath: 'Welcome.md' }, /Send the slides/);
        assert.match(html, /Write the report/);
        assert.doesNotMatch(html, /Book the room/, 'done tasks are not listed');
        assert.match(html, /2 tasks/);
        const path = elementPathInBlock(harness, 'tasks-query', 'input.task-list-item-checkbox');
        const tap = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'tasks-query', elementPath: path }));
        assert.equal(tap.isHandled, true);
        const today = harness.window.moment().format('YYYY-MM-DD');
        await waitUntil(() => harness.readVaultFile('Projects/Plan.md').includes('✅'), 5000);
        assert.equal(harness.readVaultFile('Projects/Plan.md'), '# Plan\n\n- [x] Write the report ✅ ' + today + '\n- [x] Book the room\n- [ ] Send the slides\n');
    } finally {
        harness.close();
    }
});

test('Outliner: loads and draws its settings; moves list items, and its folding commands say they need CodeMirror\'s view', { skip: !builtPlugin('obsidian-outliner') }, async () => {
    const { harness, answer, commandNames, unsupported } = await loadInStudyVault('obsidian-outliner');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.equal(commandNames.length, 7);
        assert.deepEqual(unsupported, ['CodeMirror editor extensions']);
        assert.ok((await settingRowCount(harness, 'obsidian-outliner')).count >= 5);
        harness.writeVaultFile('List.md', '- one\n- two\n');
        const moved = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'obsidian-outliner:move-list-item-down', activeDocument: { path: 'List.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('List.md', 2) } }));
        assert.deepEqual(moved, { outcome: 'ran' });
        await settle();
        assert.equal(harness.host.editorSessions.get('List.md').text, '- two\n- one\n', 'the item moved down through the editor change');
        harness.writeVaultFile('List.md', '- one\n- two\n');
        const folded = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'obsidian-outliner:fold', activeDocument: { path: 'List.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('List.md', 2) } }));
        assert.equal(folded.outcome, 'failed');
        assert.match(folded.message, /CodeMirror editor view \(editor\.cm\)/);
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

/// The text of a plugin view as Graphite shows it in a tab or sidebar panel.
async function attachedViewText(harness, leafIdentifier) {
    const attached = plain(await harness.send({ operation: 'view.attach', blockIdentifier: 'view-' + leafIdentifier, leafIdentifier, width: 320, height: 700 }));
    assert.equal(attached.isDrawn, true, attached.message);
    const element = harness.window.document.createElement('div');
    element.innerHTML = attached.html;
    return element.textContent.replace(/\s+/g, ' ');
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
        assert.deepEqual(views.map((view) => [view.title, view.placement]), [['Recent files', 'sidebar']]);
        assert.match(await attachedViewText(harness, views[0].leafIdentifier), /Other/);
        // A tap on a file in the view opens it in Graphite.
        const fileRow = Array.from(harness.window.document.querySelectorAll('.graphite-plugin-view .tree-item-self, .graphite-plugin-view .nav-file-title')).find((row) => row.textContent.includes('Other'));
        fileRow.click();
        await settle();
        assert.ok(harness.host.openedFiles.some((request) => request.path === 'Other.md'), 'the note opens through Graphite');
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

test('Style Settings: finds a theme\'s settings and sets its variables on the page, which copies take', { skip: !builtPlugin('obsidian-style-settings') }, async () => {
    const { harness, answer, pageErrors } = await loadInStudyVault('obsidian-style-settings');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        const themeCSS = '/* @settings\nname: Example Theme\nid: example-theme\nsettings:\n  - id: example-accent\n    title: Example accent\n    type: variable-color\n    format: hex\n    default: \'#ff0000\'\n*/\nbody { --example-accent: #ff0000; }';
        await harness.send({ operation: 'appearance.styles', styles: { theme: { name: 'Example', css: themeCSS }, snippets: [] }, appearanceConfiguration: { cssTheme: 'Example' } });
        // Style Settings reads the page's style sheets a moment after css-change.
        await new Promise((resolve) => setTimeout(resolve, 300));
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'obsidian-style-settings' });
        await settle();
        // The settings tab redraws once Style Settings has read the page again.
        for (let attempt = 0; attempt < 100 && !/Example Theme/.test(surfaceText(harness)); attempt += 1) await new Promise((resolve) => setTimeout(resolve, 20));
        assert.match(surfaceText(harness), /Example Theme/, 'the theme\'s settings are listed');
        const plugin = harness.app.plugins.getPlugin('obsidian-style-settings');
        plugin.settingsManager.setSetting('example-theme', 'example-accent', '#00ff00');
        await settle();
        const managerStyle = harness.window.document.getElementById('css-settings-manager');
        assert.match(managerStyle.textContent, /--example-accent:\s*#00ff00/);
        assert.ok(harness.window.document.body.classList.contains('css-settings-manager'));
        assert.match(harness.runtime.pluginStyles(), /--example-accent:\s*#00ff00/, 'copies get the value with the page\'s styles');
        assert.deepEqual(pageErrors, []);
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
        assert.deepEqual(views.map((view) => [view.title, view.placement]), [['Calendar', 'sidebar']]);
        assert.deepEqual(plain(await harness.send({ operation: 'view.show', leafIdentifier: views[0].leafIdentifier })), { isShown: true });
        assert.equal(plain(harness.host.notificationsOf('view.reveal').at(-1)).placement, 'sidebar');
        const calendarText = await attachedViewText(harness, views[0].leafIdentifier);
        assert.ok(calendarText.includes(harness.window.moment().format('MMMM')) || calendarText.includes(harness.window.moment().format('MMM')), 'the month grid shows the current month: ' + calendarText.slice(0, 200));
        await harness.send({ operation: 'view.close', leafIdentifier: views[0].leafIdentifier });
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('views.changed').at(-1).views), [], 'closing its panel closes the view');
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

test('Iconize: loads and draws its settings; its icons in the editor need editor changes', { skip: !builtPlugin('obsidian-icon-folder') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('obsidian-icon-folder');
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Iconize: Set icon for file']);
        assert.deepEqual(unsupported, ['CodeMirror editor extensions']);
        assert.deepEqual(pageErrors, []);
        const settings = await settingRowCount(harness, 'obsidian-icon-folder');
        assert.equal(settings.hasSettingTab, true);
        assert.ok(settings.count >= 15, 'Iconize\'s settings are drawn (' + settings.count + ' rows)');
    } finally {
        harness.close();
    }
});

// Plugins the sweep of Obsidian's directory found working (Docs/Community-plugins.md, 2026-10-12),
// pinned to the releases the sweep installed.

test('List to Table: converts the selected list to a table through the editor', { skip: !builtPlugin('list-to-table') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('list-to-table', { files: { 'Fruits.md': 'Fruits:\n- apple\n- [x] pear\n  - quince\n' } });
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, [
            'List to Table: Convert to table with single column', 'List to Table: Convert to table with nested items as rows',
            'List to Table: Convert to table with nested items as columns',
        ]);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        const selection = harness.host.openNote('Fruits.md', 8, 38);
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'list-to-table:convert-list-to-table', activeDocument: { path: 'Fruits.md', mode: 'source', editorSnapshot: selection } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await settle();
        const session = harness.host.editorSessions.get('Fruits.md');
        assert.equal(session.text, 'Fruits:\n|          |\n| -------- |\n| apple |\n| pear |\n| quince |\n', 'every item, ticked or nested, is a row');
        assert.equal(session.appliedChanges.length, 1, 'one change, which Graphite\'s Undo takes back');
    } finally {
        harness.close();
    }
});

test('Vault Router: sweeps the inbox, moving each note by the first rule that matches it', { skip: !builtPlugin('vault-router') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('vault-router', { files: {
        'Inbox/Daily - Monday.md': 'Today.\n',
        'Inbox/Standup.md': '---\ntags: [meeting]\nproject: Apollo\n---\nNotes.\n',
        'Inbox/Idea.md': 'No rule for this one.\n',
    } });
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Vault Router: Route current note', 'Vault Router: Preview route for current note', 'Vault Router: Sweep inbox']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        assert.deepEqual(plain(await harness.send({ operation: 'command.run', commandIdentifier: 'vault-router:route-inbox-now' })), { outcome: 'ran' });
        await waitUntil(() => harness.vaultFileExists('Journal/Daily/Daily - Monday.md') && harness.vaultFileExists('Meetings/Apollo/Standup.md'), 5000);
        assert.equal(harness.readVaultFile('Meetings/Apollo/Standup.md'), '---\ntags: [meeting]\nproject: Apollo\n---\nNotes.\n', 'the note moves unchanged');
        assert.equal(harness.vaultFileExists('Inbox/Standup.md'), false);
        assert.equal(harness.vaultFileExists('Inbox/Idea.md'), true, 'a note no rule matches stays');
        assert.deepEqual(plain(harness.host.notificationsOf('workspace.renameFile').map((message) => message.destinationPath)).sort(), ['Journal/Daily/Daily - Monday.md', 'Meetings/Apollo/Standup.md'],
            'moved through Graphite\'s file manager, which updates links');
    } finally {
        harness.close();
    }
});

test('Merge And Open Target: merges the open note into the chosen one, trashes it and opens the target', { skip: !builtPlugin('merge-open-target') }, async () => {
    const { harness, answer, commandNames, unsupported, pageErrors } = await loadInStudyVault('merge-open-target', { files: { 'Draft.md': 'Draft idea.\n', 'Project.md': '# Project\n' } });
    try {
        assert.deepEqual(answer, { isLoaded: true });
        assert.deepEqual(commandNames, ['Merge And Open Target: Merge current file into another note and open target', 'Merge And Open Target: Merge selected text into another note and open target']);
        assert.deepEqual(unsupported, []);
        assert.deepEqual(pageErrors, []);
        const outcome = plain(await harness.send({ operation: 'command.run', commandIdentifier: 'merge-open-target:merge-current-file-into-another-and-open-target', activeDocument: { path: 'Draft.md', mode: 'source', editorSnapshot: harness.host.openNote('Draft.md', 0) } }));
        assert.deepEqual(outcome, { outcome: 'ran' });
        await waitUntil(() => Array.from(harness.window.document.querySelectorAll('.suggestion-item')).some((item) => item.textContent.includes('Project')), 3000);
        Array.from(harness.window.document.querySelectorAll('.suggestion-item')).find((item) => item.textContent.includes('Project')).click();
        await waitUntil(() => harness.window.document.querySelector('.modal button.mod-cta'), 3000);
        harness.window.document.querySelector('.modal button.mod-cta').click();
        await waitUntil(() => harness.readVaultFile('Project.md').includes('Draft idea.'), 5000);
        // Its default separator, two line breaks, follows the target's own last one, as in Obsidian.
        assert.equal(harness.readVaultFile('Project.md'), '# Project\n\n\nDraft idea.\n');
        assert.equal(harness.vaultFileExists('Draft.md'), false, 'the merged note leaves the vault');
        assert.deepEqual(harness.host.openedFiles.map((message) => message.path), ['Project.md'], 'the target opens');
    } finally {
        harness.close();
    }
});

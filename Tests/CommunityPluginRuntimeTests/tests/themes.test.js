// The vault's Obsidian theme and CSS snippets in the plugins' page: Graphite sends them,
// the page adds them after the plugins' styles, `app.customCss` reports them, and the page
// tells Graphite when its styles or body classes change so copies of blocks and views follow.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const themeCSS = `/* @settings
name: Example Theme
id: example-theme
settings:
  - id: example-accent
    title: Accent
    type: variable-color
    format: hex
    default: '#ff0000'
*/
body.theme-dark { --background-primary: #101010; }
body.theme-light { --background-primary: #fafafa; }
body.example-scheme { --text-normal: #123456; }`;

const styles = {
    theme: { name: 'Example', css: themeCSS },
    snippets: [{ name: 'boxes', css: 'blockquote { border: 1px solid; }' }],
    installedThemes: ['Example', 'Other'],
    snippetNames: ['boxes', 'off'],
    accent: { hue: 254, saturation: 80, lightness: 68 },
};

async function nextStyleNotification(harness, count) {
    for (let attempt = 0; attempt < 100; attempt += 1) {
        const notifications = harness.host.notificationsOf('styles.changed');
        if (notifications.length > count) return plain(notifications.at(-1));
        await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error('No styles.changed notification.');
}

test('the theme and enabled snippets join the page after the plugins\' styles, and app.customCss reports them', async () => {
    const harness = await startRuntime({});
    try {
        const manifest = { id: 'styled', name: 'Styled', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };
        await installAndLoadPlugin(harness, { manifest, styles: '.styled { color: red; }',
            mainSource: '"use strict"; var o = require("obsidian"); module.exports = class extends o.Plugin { onload() { this.changes = 0; this.registerEvent(this.app.workspace.on("css-change", () => { this.changes += 1; })); } };' });
        const before = harness.host.notificationsOf('styles.changed').length;
        await harness.send({ operation: 'appearance.styles', styles, appearanceConfiguration: { cssTheme: 'Example', theme: 'obsidian', baseFontSize: 18 } });
        const document = harness.window.document;
        const styleElements = Array.from(document.head.querySelectorAll('style'));
        const themePosition = styleElements.findIndex((element) => element.getAttribute('data-graphite-theme') === 'Example');
        const pluginPosition = styleElements.findIndex((element) => element.getAttribute('data-graphite-plugin') === 'styled');
        assert.ok(themePosition > pluginPosition && pluginPosition >= 0, 'the theme comes after the plugins\' styles');
        assert.equal(document.head.querySelector('style[data-graphite-snippet="boxes"]').textContent, 'blockquote { border: 1px solid; }');
        const customCss = harness.app.customCss;
        assert.equal(customCss.theme, 'Example');
        assert.deepEqual(plain(Array.from(customCss.enabledSnippets)), ['boxes']);
        assert.deepEqual(plain(customCss.snippets), ['boxes', 'off']);
        assert.equal(customCss.getThemeFolder(), '.obsidian/themes');
        assert.ok(harness.app.plugins.getPlugin('styled').changes >= 1, 'plugins hear css-change, as Style Settings reparses on it');
        assert.equal(harness.app.vault.getConfig('baseFontSize'), 18, 'getConfig reads appearance.json too');
        assert.equal(harness.app.vault.getConfig('cssTheme'), 'Example');
        assert.equal(document.body.style.getPropertyValue('--accent-h'), '254');

        const notification = await nextStyleNotification(harness, before);
        assert.match(notification.styles, /\.styled \{ color: red; \}/);
        assert.match(notification.styles, /@settings/, 'copies get the theme, with its settings comments');
        assert.match(notification.bodyStyle, /--accent-h: 254/);

        // A plugin sets a class on the body, as Minimal Theme Settings and Style Settings do.
        const count = harness.host.notificationsOf('styles.changed').length;
        document.body.classList.add('example-scheme', 'css-settings-manager');
        const classNotification = await nextStyleNotification(harness, count);
        assert.deepEqual(classNotification.bodyClasses.split(' ').sort(), ['css-settings-manager', 'example-scheme'], 'the runtime\'s own and light or dark classes are left to each copy');

        // The same styles sent again change nothing in the page.
        const themeElement = document.head.querySelector('style[data-graphite-theme]');
        await harness.send({ operation: 'appearance.styles', styles, appearanceConfiguration: {} });
        assert.equal(document.head.querySelector('style[data-graphite-theme]'), themeElement);

        // No theme: its element goes.
        await harness.send({ operation: 'appearance.styles', styles: { snippets: [] }, appearanceConfiguration: {} });
        assert.equal(document.head.querySelector('style[data-graphite-theme]'), null);
        assert.equal(document.head.querySelector('style[data-graphite-snippet]'), null);
        assert.equal(harness.app.customCss.theme, '');
    } finally {
        harness.close();
    }
});

test('choosing a theme or snippets from a plugin goes through Graphite; the light or dark choice stays in the page', async () => {
    const harness = await startRuntime({});
    try {
        harness.app.customCss.setTheme('Minimal');
        harness.app.customCss.setCssEnabledStatus('boxes', true);
        harness.app.vault.setConfig('baseFontSize', 20);
        harness.app.setTheme('moonstone');
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('appearance.setConfig').map((message) => [message.key, message.value])),
            [['cssTheme', 'Minimal'], ['enabledCssSnippets', ['boxes']], ['baseFontSize', 20]]);
        assert.equal(harness.app.getTheme(), 'moonstone');
        assert.equal(harness.app.vault.getConfig('baseFontSize'), 20);
        // Other settings stay Graphite's to change: a plugin's value is kept for the plugins and
        // reported, without failing the plugin (the community plugin sweep).
        harness.app.vault.setConfig('vimMode', true);
        await settle();
        assert.equal(harness.app.vault.getConfig('vimMode'), true);
        assert.ok(harness.host.notificationsOf('plugin.unsupportedFeature').some((message) => /vimMode/.test(message.featureName)));
        assert.ok(!harness.host.notificationsOf('appearance.setConfig').some((message) => message.key === 'vimMode'), 'not written to Graphite\'s settings');
    } finally {
        harness.close();
    }
});

test('a theme too large for every copy is left out of copies, not out of the page', async () => {
    const harness = await startRuntime({});
    try {
        const largeTheme = 'body { --x: 1; }\n' + '/* padding */\n'.repeat(260000);
        await harness.send({ operation: 'appearance.styles', styles: { theme: { name: 'Large', css: largeTheme }, snippets: [{ name: 'boxes', css: 'blockquote { border: 1px solid; }' }] }, appearanceConfiguration: {} });
        assert.ok(harness.window.document.head.querySelector('style[data-graphite-theme="Large"]'));
        const copyStyles = harness.runtime.pluginStyles();
        assert.ok(!copyStyles.includes('/* padding */'), 'the theme is not sent to copies');
        assert.match(copyStyles, /blockquote/, 'snippets still are');
    } finally {
        harness.close();
    }
});

test('the plugins page shares the default variable layer the theme resolver measures against', () => {
    const fileSystem = require('node:fs');
    const path = require('node:path');
    const runtimeFolder = path.join(__dirname, '../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime');
    const indexPage = fileSystem.readFileSync(path.join(runtimeFolder, 'index.html'), 'utf8');
    const defaultLayerPosition = indexPage.indexOf('href="graphite-default-variables.css"');
    assert.ok(defaultLayerPosition > 0, 'index.html links the default layer');
    assert.ok(defaultLayerPosition < indexPage.indexOf('href="community-plugin-runtime.css"'), 'the default layer comes first');
    // Graphite's look is written as the base color scale, so a theme that replaces only the
    // scale restyles plugin pages: the semantic colors must come from the default layer.
    const runtimeStyles = fileSystem.readFileSync(path.join(runtimeFolder, 'community-plugin-runtime.css'), 'utf8');
    for (const semanticColor of ['--background-primary:', '--text-normal:', '--text-muted:', '--text-faint:', '--background-modifier-border:']) {
        assert.ok(!runtimeStyles.includes(semanticColor), `${semanticColor} comes from the base scale`);
    }
    assert.match(runtimeStyles, /--color-base-00: #ffffff/);
});

// BUG-RUNTIME-04: the runtime's own styles overrode the fonts the default layer takes from a theme.
test('a theme\'s font variables reach the plugins page through the default layer', () => {
    const fileSystem = require('node:fs');
    const path = require('node:path');
    const { JSDOM } = require('jsdom');
    const runtimeFolder = path.join(__dirname, '../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime');
    const indexPage = fileSystem.readFileSync(path.join(runtimeFolder, 'index.html'), 'utf8');
    const styleSheetNames = Array.from(indexPage.matchAll(/<link rel="stylesheet" href="([^"]+)">/g), (match) => match[1]);
    const pageStyles = styleSheetNames.map((name) => '<style>' + fileSystem.readFileSync(path.join(runtimeFolder, name), 'utf8') + '</style>').join('');
    const themeStyles = '<style>body { --font-text-theme: "Theme Text"; --font-interface-theme: "Theme Interface"; --font-monospace-theme: "Theme Code"; }</style>';
    const page = new JSDOM('<!doctype html><html><head>' + pageStyles + themeStyles + '</head><body class="graphite-plugin-runtime theme-light"></body></html>');
    try {
        const bodyStyle = page.window.getComputedStyle(page.window.document.body);
        // jsdom cascades custom properties but leaves `var()` unresolved, as declared.
        const resolvedVariable = (name) => bodyStyle.getPropertyValue(name).trim().replace(/var\((--[\w-]+)\)/g, (reference, referencedName) => resolvedVariable(referencedName));
        assert.equal(resolvedVariable('--font-text'), '"Theme Text"');
        assert.equal(resolvedVariable('--font-interface'), '"Theme Interface"');
        assert.equal(resolvedVariable('--font-monospace'), '"Theme Code"');
    } finally {
        page.window.close();
    }
});

// BUG-RUNTIME-07: getTheme() answered the dark theme on a light page.
test('app.getTheme follows the page\'s light or dark appearance when appearance.json names no theme', async () => {
    const harness = await startRuntime({});
    try {
        assert.equal(harness.app.isDarkMode(), false);
        assert.equal(harness.app.getTheme(), 'moonstone', 'a light page is Obsidian\'s light theme');
        await harness.send({ operation: 'appearance.changed', appearance: 'dark' });
        assert.equal(harness.app.isDarkMode(), true);
        assert.equal(harness.app.getTheme(), 'obsidian', 'a dark page is Obsidian\'s dark theme');
        assert.equal(harness.app.vault.config.theme, harness.app.getTheme(), 'the settings object reports the same theme');
    } finally {
        harness.close();
    }
});

// Obsidian's declarative settings (1.13): a setting tab that returns definitions from
// `getSettingDefinitions()` is drawn from them instead of by `display()`. Controls read and
// write through the tab's `getControlValue` and `setControlValue`, validation messages
// show under the setting, `visible` and `disabled` predicates are re-evaluated by
// `refreshDomState()`, and pages open within the plugin panel with a way back.
(function installDeclarativeSettings(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Setting, SettingGroup, SettingTab, PluginSettingTab, AbstractInputSuggest, setIcon } = exportedApi;

    function evaluate(predicateOrValue, fallback) {
        if (predicateOrValue === undefined) return fallback;
        return typeof predicateOrValue === 'function' ? Boolean(predicateOrValue()) : Boolean(predicateOrValue);
    }

    function isGroup(definition) { return definition && (definition.type === 'group' || definition.type === 'list'); }
    function isPage(definition) { return definition && definition.type === 'page'; }

    // MARK: Choosing files and folders

    class VaultPathSuggest extends AbstractInputSuggest {
        constructor(app, inputElement, candidates) {
            super(app, inputElement);
            this.candidates = candidates;
        }
        getSuggestions(query) {
            const lowercasedQuery = query.toLowerCase();
            return this.candidates().filter((path) => path.toLowerCase().includes(lowercasedQuery)).slice(0, 100);
        }
        renderSuggestion(path, element) { element.setText(path); }
    }

    // MARK: Drawing a tab

    /// Draws a tab's definitions into its container. Returns false when it has none, so the
    /// caller falls back to `display()`.
    function render(settingTab) {
        const definitions = settingTab.getSettingDefinitions();
        if (!Array.isArray(definitions) || definitions.length === 0) return false;
        settingTab.settingItems = definitions;
        settingTab.renderedSettings = [];
        settingTab.containerEl.empty();
        settingTab.containerEl.addClass('mod-declarative');
        renderItems(settingTab, settingTab.containerEl, definitions);
        return true;
    }

    function renderItems(settingTab, containerElement, items) {
        let implicitGroup = null;
        for (const item of items) {
            if (isGroup(item)) {
                implicitGroup = null;
                renderGroup(settingTab, containerElement, item);
                continue;
            }
            if (!implicitGroup) implicitGroup = new SettingGroup(containerElement);
            renderDefinition(settingTab, implicitGroup, implicitGroup.itemsEl, item, null);
        }
    }

    function renderGroup(settingTab, containerElement, groupDefinition) {
        const group = new SettingGroup(containerElement);
        if (groupDefinition.heading) group.setHeading(groupDefinition.heading);
        if (groupDefinition.cls) group.addClass(groupDefinition.cls);
        for (const extraButton of groupDefinition.extraButtons || []) group.addExtraButton(extraButton);
        settingTab.renderedSettings.push({ definition: groupDefinition, element: group.groupEl });
        const rows = [];
        (groupDefinition.items || []).forEach((item, index) => {
            const setting = renderDefinition(settingTab, group, group.itemsEl, item, groupDefinition.type === 'list' ? { groupDefinition, index } : null);
            if (setting) rows.push({ item, setting });
        });
        if (groupDefinition.type === 'list') {
            if (rows.length === 0 && groupDefinition.emptyState) group.itemsEl.createDiv({ cls: 'setting-list-empty', text: '' }).setText(groupDefinition.emptyState);
            if (groupDefinition.addItem) {
                const addSetting = new Setting(group.itemsEl).setName(groupDefinition.addItem.name).setClass('setting-list-add-item');
                addSetting.addExtraButton((button) => button.setIcon('plus').setTooltip(groupDefinition.addItem.name).onClick(() => groupDefinition.addItem.action(addSetting.settingEl)));
            }
        }
        if (groupDefinition.search) {
            group.addSearch((search) => {
                search.setPlaceholder(groupDefinition.search.placeholder || 'Search…');
                search.onChange((query) => {
                    for (const row of rows) row.setting.settingEl.toggle(!query || groupDefinition.search.match(row.item, query));
                });
            });
        }
    }

    /// One setting row: a control, an action, something the plugin draws, a page, or a name alone.
    function renderDefinition(settingTab, group, containerElement, definition, listPlacement) {
        if (isPage(definition)) return renderPageRow(settingTab, containerElement, definition);
        const setting = new Setting(containerElement);
        setting.setName(definition.name || '');
        if (definition.desc !== undefined) setting.setDesc(definition.desc);
        if (definition.control) renderControl(settingTab, setting, definition.control);
        else if (definition.action) {
            setting.settingEl.addClass('mod-clickable');
            setting.settingEl.addEventListener('click', () => {
                if (!evaluate(definition.disabled, false)) definition.action(setting.settingEl, listPlacement ? listPlacement.index : 0);
            });
        } else if (definition.render) {
            const cleanup = definition.render(setting, group);
            if (typeof cleanup === 'function') settingTab.renderCleanups = (settingTab.renderCleanups || []).concat([cleanup]);
        }
        if (listPlacement) addListControls(setting, listPlacement);
        settingTab.renderedSettings.push({ definition, setting, element: setting.settingEl });
        applyDomState(definition, setting.settingEl, setting);
        return setting;
    }

    function addListControls(setting, listPlacement) {
        const { groupDefinition, index } = listPlacement;
        const count = (groupDefinition.items || []).length;
        if (groupDefinition.onReorder) {
            if (index > 0) setting.addExtraButton((button) => button.setIcon('arrow-up').setTooltip('Move up').onClick(() => groupDefinition.onReorder(index, index - 1)));
            if (index < count - 1) setting.addExtraButton((button) => button.setIcon('arrow-down').setTooltip('Move down').onClick(() => groupDefinition.onReorder(index, index + 1)));
        }
        if (groupDefinition.onDelete) setting.addExtraButton((button) => button.setIcon('trash-2').setTooltip('Delete').onClick(() => groupDefinition.onDelete(index)));
    }

    function renderControl(settingTab, setting, control) {
        const storedValue = settingTab.getControlValue(control.key);
        const value = storedValue === undefined || storedValue === null ? control.defaultValue : storedValue;
        const commit = async (newValue) => {
            if (control.validate) {
                const problem = await control.validate(newValue);
                setting.setErrorMessage(problem || null);
                if (problem) return;
            }
            await settingTab.setControlValue(control.key, newValue);
            settingTab.refreshDomState();
        };
        const app = settingTab.app;
        switch (control.type) {
        case 'toggle':
            setting.addToggle((toggle) => toggle.setValue(Boolean(value)).onChange(commit));
            break;
        case 'dropdown':
            setting.addDropdown((dropdown) => dropdown.addOptions(control.options || {}).setValue(value === undefined ? '' : String(value)).onChange(commit));
            break;
        case 'slider':
            setting.addSlider((slider) => {
                slider.setLimits(control.min, control.max, control.step).setValue(value === undefined ? control.min : value).setDynamicTooltip();
                if (control.displayFormat) slider.setDisplayFormat(control.displayFormat);
                slider.onChange(commit);
            });
            break;
        case 'number':
            setting.addText((text) => {
                text.inputEl.type = 'number';
                if (control.min !== undefined) text.inputEl.min = String(control.min);
                if (control.max !== undefined) text.inputEl.max = String(control.max);
                if (control.step !== undefined) text.inputEl.step = String(control.step);
                if (control.placeholder) text.setPlaceholder(control.placeholder);
                text.setValue(value === undefined ? '' : String(value)).onChange((typed) => {
                    const number = Number(typed);
                    if (typed.trim() === '' || Number.isNaN(number)) { setting.setErrorMessage('Enter a number.'); return; }
                    commit(number);
                });
            });
            break;
        case 'color':
            setting.addColorPicker((color) => color.setValue(value || '#000000').onChange(commit));
            break;
        case 'textarea':
            setting.addTextArea((textArea) => {
                if (control.placeholder) textArea.setPlaceholder(control.placeholder);
                if (control.rows) textArea.inputEl.rows = control.rows;
                textArea.setValue(value === undefined ? '' : String(value)).onChange(commit);
            });
            break;
        case 'secret':
            setting.addSecret((secret) => secret.setValue(value === undefined ? '' : String(value)).onChange(commit));
            break;
        case 'file':
        case 'folder':
            setting.addText((text) => {
                if (control.placeholder) text.setPlaceholder(control.placeholder);
                text.setValue(value === undefined ? '' : String(value)).onChange(commit);
                new VaultPathSuggest(app, text.inputEl, () => {
                    if (control.type === 'file') return app.vault.getFiles().filter((file) => !control.filter || control.filter(file)).map((file) => file.path);
                    return app.vault.getAllFolders(Boolean(control.includeRoot)).filter((folder) => !control.filter || control.filter(folder)).map((folder) => folder.path);
                }).onSelect((path) => { text.setValue(path); commit(path); });
            });
            break;
        default:
            setting.addText((text) => {
                if (control.placeholder) text.setPlaceholder(control.placeholder);
                text.setValue(value === undefined ? '' : String(value)).onChange(commit);
            });
        }
        if (control.disabled !== undefined) setting.setDisabled(evaluate(control.disabled, false));
    }

    function renderPageRow(settingTab, containerElement, pageDefinition) {
        const setting = new Setting(containerElement).setName(pageDefinition.name).setClass('mod-page');
        if (pageDefinition.desc !== undefined) setting.setDesc(pageDefinition.desc);
        if (pageDefinition.displayValue !== undefined || pageDefinition.status !== undefined) {
            setting.addDisplayValue((display) => {
                const displayValue = typeof pageDefinition.displayValue === 'function' ? pageDefinition.displayValue() : pageDefinition.displayValue;
                const status = typeof pageDefinition.status === 'function' ? pageDefinition.status() : pageDefinition.status;
                display.setValue(displayValue || null).setStatus(status || null);
            });
        }
        const chevron = setting.controlEl.createDiv({ cls: 'setting-page-chevron' });
        setIcon(chevron, 'chevron-right');
        setting.settingEl.addClass('mod-clickable');
        setting.settingEl.addEventListener('click', () => openPage(settingTab, pageDefinition));
        settingTab.renderedSettings.push({ definition: pageDefinition, setting, element: setting.settingEl });
        applyDomState(pageDefinition, setting.settingEl, setting);
        return setting;
    }

    /// Shows a page in place of the tab, with a way back to it.
    function openPage(settingTab, pageDefinition) {
        const container = settingTab.containerEl;
        container.empty();
        const backRow = container.createDiv({ cls: 'setting-page-back clickable-icon' });
        setIcon(backRow.createSpan(), 'chevron-left');
        backRow.createSpan({ text: 'Back' });
        container.createEl('h2', { cls: 'setting-page-title', text: pageDefinition.name });
        let customPage = null;
        backRow.addEventListener('click', () => {
            if (customPage) customPage.hide();
            runtime.pluginSurface.refreshSettingTab(settingTab);
        });
        if (pageDefinition.page) {
            customPage = pageDefinition.page();
            container.appendChild(customPage.rootEl || customPage.containerEl);
            customPage.display();
            return;
        }
        settingTab.renderedSettings = [];
        renderItems(settingTab, container, pageDefinition.items || []);
    }

    function applyDomState(definition, element, setting) {
        element.toggle(evaluate(definition.visible, true));
        if (setting && definition.control && definition.control.disabled !== undefined) setting.setDisabled(evaluate(definition.control.disabled, false));
        if (setting && definition.action && definition.disabled !== undefined) setting.setDisabled(evaluate(definition.disabled, false));
    }

    // MARK: SettingTab's declarative members

    SettingTab.prototype.getSettingDefinitions = function getSettingDefinitions() { return []; };
    SettingTab.prototype.update = function update() {
        this.settingItems = this.getSettingDefinitions() || [];
        if (runtime.pluginSurface.shownSettingTab === this) runtime.pluginSurface.refreshSettingTab(this);
    };
    SettingTab.prototype.refreshDomState = function refreshDomState() {
        for (const rendered of this.renderedSettings || []) applyDomState(rendered.definition, rendered.element, rendered.setting);
    };
    /// Obsidian's own tabs read and write `app.json`; Graphite changes those in its Settings.
    SettingTab.prototype.getControlValue = function getControlValue(key) { return this.app.vault.getConfig(key); };
    SettingTab.prototype.setControlValue = function setControlValue(key, value) { return this.app.vault.setConfig(key, value); };
    PluginSettingTab.prototype.getControlValue = function getControlValue(key) {
        const settings = this.plugin && this.plugin.settings;
        return settings && typeof settings === 'object' ? settings[key] : undefined;
    };
    PluginSettingTab.prototype.setControlValue = async function setControlValue(key, value) {
        if (!this.plugin) return;
        if (!this.plugin.settings || typeof this.plugin.settings !== 'object') this.plugin.settings = {};
        this.plugin.settings[key] = value;
        await this.plugin.saveData(this.plugin.settings);
    };
    const originalHide = SettingTab.prototype.hide;
    SettingTab.prototype.hide = function hide() {
        for (const cleanup of (this.renderCleanups || []).splice(0)) {
            try { cleanup(); } catch (error) { console.error(error); }
        }
        return originalHide.call(this);
    };

    runtime.declarativeSettings = { render };
})(globalThis);

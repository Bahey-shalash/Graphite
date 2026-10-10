// Obsidian's interface classes for plugins: icons, `Notice`, `Modal`, `Setting` and its
// controls, setting tabs, suggestion lists, menus, tooltips and keyboard scopes. Plugin
// interface is drawn in the runtime's page, which Graphite shows as the plugin panel (in
// Settings, inline on the plugin's page); notices are shown by Graphite itself.
(function installRuntimeInterface(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Component } = exportedApi;
    const hostBridge = runtime.hostBridge;

    // MARK: Icons

    /// Obsidian's names from before it used Lucide, which plugins still pass.
    const legacyIconNames = {
        'cross': 'x', 'cross-in-box': 'x-square', 'checkmark': 'check', 'check-small': 'check', 'gear': 'settings', 'document': 'file',
        'documents': 'files', 'dice': 'dice-5', 'pencil': 'pencil', 'trash': 'trash-2', 'search': 'search', 'info': 'info',
        'help': 'help-circle', 'left-arrow': 'arrow-left', 'right-arrow': 'arrow-right', 'up-arrow-with-tail': 'arrow-up',
        'down-arrow-with-tail': 'arrow-down', 'left-arrow-with-tail': 'arrow-left', 'right-arrow-with-tail': 'arrow-right',
        'up-chevron-glyph': 'chevron-up', 'down-chevron-glyph': 'chevron-down', 'left-chevron-glyph': 'chevron-left',
        'right-chevron-glyph': 'chevron-right', 'calendar-with-checkmark': 'calendar-check', 'sheets-in-box': 'archive',
        'enter': 'corner-down-left', 'paper-plane': 'send', 'plus-with-circle': 'plus-circle', 'minus-with-circle': 'minus-circle',
        'star-list': 'list', 'bullet-list': 'list', 'number-list': 'list-ordered', 'stacked-levels': 'layers', 'lines-of-text': 'align-left',
        'vertical-three-dots': 'more-vertical', 'three-horizontal-bars': 'menu', 'reset': 'rotate-ccw', 'restore-file-glyph': 'history',
        'popup-open': 'external-link', 'open-vault': 'folder-open', 'go-to-file': 'file-search', 'switch': 'repeat', 'sync': 'refresh-cw',
        'link': 'link', 'broken-link': 'unlink', 'hashtag': 'hash', 'image-file': 'image', 'audio-file': 'file-audio',
        'pdf-file': 'file-text', 'blocks': 'box', 'code-glyph': 'code', 'bold-glyph': 'bold', 'italic-glyph': 'italic',
        'strikethrough-glyph': 'strikethrough', 'highlight-glyph': 'highlighter', 'quote-glyph': 'quote', 'languages': 'languages',
        'install': 'download', 'uppercase-lowercase-a': 'case-sensitive', 'forward-arrow': 'arrow-right', 'filled-pin': 'pin',
        'pin': 'pin', 'star': 'star', 'bookmark': 'bookmark', 'lock': 'lock', 'unlock': 'unlock', 'clock': 'clock',
        'folder': 'folder', 'microphone': 'mic', 'microphone-filled': 'mic', 'presentation': 'presentation', 'wrench-screwdriver-glyph': 'wrench',
        'percent-sign-glyph': 'percent', 'any-key': 'keyboard', 'create-new': 'square-pen', 'dot-network': 'network', 'bracket-glyph': 'brackets',
    };

    const customIcons = new Map();
    let lucideIconsByName = null;

    function kebabCaseName(pascalCaseName) {
        return pascalCaseName
            .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
            .replace(/([A-Z])([A-Z][a-z])/g, '$1-$2')
            .replace(/([a-wyzA-Z]|(?<![0-9])x)([0-9])/g, '$1-$2')
            .toLowerCase();
    }

    function lucideIcons() {
        if (lucideIconsByName) return lucideIconsByName;
        lucideIconsByName = new Map();
        const library = globalScope.lucide || {};
        for (const exportedName of Object.keys(library)) {
            const iconNode = library[exportedName];
            if (Array.isArray(iconNode) && iconNode[0] === 'svg') lucideIconsByName.set(kebabCaseName(exportedName), iconNode);
        }
        return lucideIconsByName;
    }

    function resolveIconName(iconName) {
        const name = String(iconName || '').replace(/^lucide-/, '');
        if (customIcons.has(iconName)) return { custom: customIcons.get(iconName) };
        if (lucideIcons().has(name)) return { lucide: lucideIcons().get(name), name };
        const legacy = legacyIconNames[name];
        if (legacy && lucideIcons().has(legacy)) return { lucide: lucideIcons().get(legacy), name: legacy };
        return null;
    }

    function svgFromLucideNode(iconNode, iconName) {
        const svgNamespace = 'http://www.w3.org/2000/svg';
        const build = (node) => {
            const element = globalScope.document.createElementNS(svgNamespace, node[0]);
            for (const attributeName of Object.keys(node[1] || {})) element.setAttribute(attributeName, String(node[1][attributeName]));
            for (const child of node[2] || []) element.appendChild(build(child));
            return element;
        };
        const svg = build(iconNode);
        svg.setAttribute('class', 'svg-icon lucide-' + iconName);
        return svg;
    }

    function getIcon(iconName) {
        const resolved = resolveIconName(iconName);
        if (!resolved) return null;
        if (resolved.custom) {
            const container = globalScope.document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            container.setAttribute('viewBox', '0 0 100 100');
            container.setAttribute('class', 'svg-icon ' + iconName);
            container.innerHTML = resolved.custom;
            return container;
        }
        return svgFromLucideNode(resolved.lucide, resolved.name);
    }

    function setIcon(parentElement, iconName) {
        parentElement.empty();
        const icon = getIcon(iconName);
        if (icon) parentElement.appendChild(icon);
    }

    function addIcon(iconIdentifier, svgContent) { customIcons.set(iconIdentifier, svgContent); }
    function removeIcon(iconIdentifier) { customIcons.delete(iconIdentifier); }
    function getIconIds() {
        return Array.from(lucideIcons().keys()).map((name) => 'lucide-' + name).concat(Array.from(customIcons.keys()));
    }

    // MARK: Tooltips

    function setTooltip(element, tooltip, options) {
        if (tooltip) {
            element.setAttribute('aria-label', tooltip);
            element.setAttribute('title', tooltip);
            if (options && options.placement) element.setAttribute('data-tooltip-position', options.placement);
        } else {
            element.removeAttribute('aria-label');
            element.removeAttribute('title');
        }
    }
    function displayTooltip(element, tooltip, options) { setTooltip(element, tooltip, options); }

    // MARK: Keyboard scopes

    class Scope {
        constructor(parent) {
            this.parent = parent || null;
            this.keymapEventHandlers = [];
        }
        register(modifiers, key, callback) {
            const handler = { scope: this, modifiers: modifiers ? modifiers.slice().sort().join(',') : null, key: key ? key.toLowerCase() : null, func: callback };
            this.keymapEventHandlers.push(handler);
            return handler;
        }
        unregister(handler) { this.keymapEventHandlers.remove(handler); }
        handleKeyEvent(event) {
            const modifiers = Keymap.modifiersOf(event);
            for (const handler of this.keymapEventHandlers.slice().reverse()) {
                const isKeyMatch = handler.key === null || handler.key === event.key.toLowerCase();
                const isModifierMatch = handler.modifiers === null || handler.modifiers === modifiers;
                if (isKeyMatch && isModifierMatch) {
                    const outcome = handler.func(event, { modifiers, key: event.key, vkey: event.key });
                    if (outcome === false) {
                        event.preventDefault();
                        return true;
                    }
                }
            }
            return this.parent ? this.parent.handleKeyEvent(event) : false;
        }
    }

    class Keymap {
        constructor() {
            this.scopes = [];
            this.rootScope = new Scope();
        }
        pushScope(scope) { this.scopes.push(scope); }
        popScope(scope) { this.scopes.remove(scope); }
        getRootScope() { return this.rootScope; }
        handleKeyEvent(event) {
            const scope = this.scopes.last() || this.rootScope;
            return scope.handleKeyEvent(event);
        }
        static modifiersOf(event) {
            const modifiers = [];
            if (event.altKey) modifiers.push('Alt');
            if (event.ctrlKey) modifiers.push('Ctrl');
            if (event.metaKey) modifiers.push('Meta');
            if (event.shiftKey) modifiers.push('Shift');
            return modifiers.sort().join(',');
        }
        static isModifier(event, modifier) {
            if (modifier === 'Mod') return Boolean(event.metaKey);
            return Boolean(event[modifier.toLowerCase() + 'Key']);
        }
        static isModEvent(event) {
            if (!event) return false;
            if (event.metaKey || event.ctrlKey) return event.shiftKey ? 'window' : 'tab';
            if (event.button === 1) return 'tab';
            return false;
        }
    }

    // MARK: The plugin panel

    /// What the runtime's page shows, and asking Graphite to show or hide it.
    const pluginSurface = {
        openModals: [],
        shownSettingTab: null,
        shownLeaf: null,
        isPresented: false,

        hostElement() {
            return globalScope.document.querySelector('.graphite-plugin-surface') || globalScope.document.body;
        },
        clearShownContent() {
            if (this.shownSettingTab) {
                const settingTab = this.shownSettingTab;
                this.shownSettingTab = null;
                settingTab.hide();
                settingTab.containerEl.detach();
            }
            if (this.shownLeaf) {
                this.shownLeaf.containerEl.detach();
                this.shownLeaf = null;
            }
        },
        present(title) {
            this.isPresented = true;
            hostBridge.notify('surface.present', { title: title || '' });
        },
        dismissIfEmpty() {
            if (this.openModals.length > 0 || this.shownSettingTab || this.shownLeaf) return;
            if (!this.isPresented) return;
            this.isPresented = false;
            hostBridge.notify('surface.dismiss', {});
        },
        showSettingTab(settingTab, title) {
            this.clearShownContent();
            this.shownSettingTab = settingTab;
            this.hostElement().appendChild(settingTab.containerEl);
            this.drawSettingTab(settingTab);
            this.present(title);
        },
        /// From its definitions (Obsidian 1.13) when it has them, otherwise by `display()`.
        drawSettingTab(settingTab) {
            settingTab.containerEl.empty();
            if (!runtime.declarativeSettings || !runtime.declarativeSettings.render(settingTab)) settingTab.display();
        },
        refreshSettingTab(settingTab) {
            if (this.shownSettingTab !== settingTab) return;
            this.drawSettingTab(settingTab);
        },
        showLeaf(leaf) {
            this.clearShownContent();
            this.shownLeaf = leaf;
            this.hostElement().appendChild(leaf.containerEl);
            leaf.updateHeader();
            this.present(leaf.getDisplayText());
        },
        modalOpened(modal) {
            this.openModals.push(modal);
            this.present(modal.titleEl.getText());
        },
        modalClosed(modal) {
            this.openModals.remove(modal);
            this.dismissIfEmpty();
        },
        /// Graphite closed the panel (a swipe, Done, or leaving the plugin's settings page).
        handleClosedByPerson() {
            for (const modal of this.openModals.slice().reverse()) modal.close();
            this.clearShownContent();
            this.isPresented = false;
        },
    };
    runtime.pluginSurface = pluginSurface;

    // MARK: Notices

    let nextNoticeNumber = 1;

    class Notice {
        constructor(message, durationMilliseconds) {
            this.noticeIdentifier = 'notice-' + nextNoticeNumber;
            nextNoticeNumber += 1;
            this.containerEl = createDiv({ cls: 'notice-container' });
            this.noticeEl = this.containerEl.createDiv({ cls: 'notice' });
            this.messageEl = this.noticeEl.createDiv({ cls: 'notice-message' });
            this.messageEl.setText(message === undefined ? '' : message);
            const duration = durationMilliseconds === undefined ? 4500 : durationMilliseconds;
            hostBridge.notify('notice.show', {
                noticeIdentifier: this.noticeIdentifier,
                message: this.messageEl.getText(),
                durationMilliseconds: duration,
                pluginIdentifier: runtime.callingPluginIdentifier(),
            });
        }
        setMessage(message) {
            this.messageEl.setText(message);
            hostBridge.notify('notice.update', { noticeIdentifier: this.noticeIdentifier, message: this.messageEl.getText() });
            return this;
        }
        hide() {
            hostBridge.notify('notice.hide', { noticeIdentifier: this.noticeIdentifier });
        }
    }

    // MARK: Modals

    class Modal {
        constructor(app) {
            this.app = app || runtime.app;
            this.scope = new Scope(this.app.scope);
            this.shouldRestoreSelection = false;
            this.containerEl = createDiv({ cls: 'modal-container mod-dim' });
            this.bgEl = this.containerEl.createDiv({ cls: 'modal-bg' });
            this.modalEl = this.containerEl.createDiv({ cls: 'modal' });
            this.closeButtonEl = this.modalEl.createDiv({ cls: 'modal-close-button', attr: { 'aria-label': 'Close' } });
            this.headerEl = this.modalEl.createDiv({ cls: 'modal-header' });
            this.titleEl = this.headerEl.createDiv({ cls: 'modal-title' });
            this.contentEl = this.modalEl.createDiv({ cls: 'modal-content' });
            this.isOpen = false;
            this.closeCallback = null;
            this.closeButtonEl.addEventListener('click', () => this.close());
            this.bgEl.addEventListener('click', () => this.close());
            this.scope.register([], 'Escape', () => { this.close(); return false; });
            this.keydownListener = (event) => { if (this.isOpen && pluginSurface.openModals.last() === this) this.scope.handleKeyEvent(event); };
        }
        open() {
            if (this.isOpen) return;
            this.isOpen = true;
            pluginSurface.hostElement().ownerDocument.body.appendChild(this.containerEl);
            globalScope.document.addEventListener('keydown', this.keydownListener, true);
            this.app.keymap.pushScope(this.scope);
            pluginSurface.modalOpened(this);
            try {
                const opening = this.onOpen();
                if (opening && opening.catch) opening.catch((error) => console.error(error));
            } catch (error) {
                console.error(error);
            }
        }
        close() {
            if (!this.isOpen) return;
            this.isOpen = false;
            globalScope.document.removeEventListener('keydown', this.keydownListener, true);
            this.app.keymap.popScope(this.scope);
            try { this.onClose(); } catch (error) { console.error(error); }
            this.containerEl.detach();
            if (this.closeCallback) {
                try { this.closeCallback(); } catch (error) { console.error(error); }
            }
            pluginSurface.modalClosed(this);
        }
        onOpen() {}
        onClose() {}
        setTitle(title) {
            this.titleEl.setText(title);
            return this;
        }
        setContent(content) {
            this.contentEl.setText(content);
            return this;
        }
        setCloseCallback(callback) {
            this.closeCallback = callback;
            return this;
        }
        /// The phone's back gesture closes a modal, as on Obsidian mobile.
        onHistoryBack() {
            this.close();
            return true;
        }
    }

    // MARK: Setting controls

    class BaseComponent {
        constructor() { this.disabled = false; }
        then(callback) { callback(this); return this; }
        setDisabled(isDisabled) { this.disabled = Boolean(isDisabled); return this; }
    }

    class ValueComponent extends BaseComponent {
        registerOptionListener(listeners, key) {
            listeners[key] = (value) => {
                if (value !== undefined) this.setValue(value);
                return this.getValue();
            };
            return this;
        }
    }

    class AbstractTextComponent extends ValueComponent {
        constructor(inputElement) {
            super();
            this.inputEl = inputElement;
            this.changeCallback = null;
            this.inputEl.addEventListener('input', () => this.onChanged());
        }
        setDisabled(isDisabled) {
            super.setDisabled(isDisabled);
            this.inputEl.disabled = this.disabled;
            return this;
        }
        getValue() { return this.inputEl.value; }
        setValue(value) { this.inputEl.value = value === undefined || value === null ? '' : value; return this; }
        setPlaceholder(placeholder) { this.inputEl.placeholder = placeholder; return this; }
        onChanged() { if (this.changeCallback) this.changeCallback(this.getValue()); }
        onChange(callback) { this.changeCallback = callback; return this; }
    }

    class TextComponent extends AbstractTextComponent {
        constructor(containerElement) {
            super(containerElement.createEl('input', { type: 'text', attr: { spellcheck: 'false' } }));
        }
    }

    class SecretComponent extends TextComponent {
        constructor(containerElement) {
            super(containerElement);
            this.inputEl.type = 'password';
        }
    }

    class TextAreaComponent extends AbstractTextComponent {
        constructor(containerElement) {
            super(containerElement.createEl('textarea', { attr: { spellcheck: 'false' } }));
        }
    }

    class SearchComponent extends AbstractTextComponent {
        constructor(containerElement) {
            const wrapper = containerElement.createDiv({ cls: 'search-input-container' });
            super(wrapper.createEl('input', { type: 'search', attr: { enterkeyhint: 'search', spellcheck: 'false' } }));
            this.containerEl = wrapper;
            this.clearButtonEl = wrapper.createDiv({ cls: 'search-input-clear-button' });
            this.clearButtonEl.addEventListener('click', () => {
                this.setValue('');
                this.onChanged();
                this.inputEl.focus();
            });
        }
        onChanged() {
            this.clearButtonEl.toggle(this.getValue().length > 0);
            super.onChanged();
        }
    }

    class MomentFormatComponent extends TextComponent {
        constructor(containerElement) {
            super(containerElement);
            this.defaultFormat = '';
            this.sampleEl = null;
        }
        setDefaultFormat(defaultFormat) {
            this.defaultFormat = defaultFormat;
            this.setPlaceholder(defaultFormat);
            this.updateSample();
            return this;
        }
        setSampleEl(sampleElement) { this.sampleEl = sampleElement; this.updateSample(); return this; }
        setValue(value) { super.setValue(value); this.updateSample(); return this; }
        onChanged() { this.updateSample(); super.onChanged(); }
        updateSample() {
            if (!this.sampleEl || !globalScope.moment) return;
            this.sampleEl.setText(globalScope.moment().format(this.getValue() || this.defaultFormat));
        }
    }

    class ToggleComponent extends ValueComponent {
        constructor(containerElement) {
            super();
            this.toggleEl = containerElement.createDiv({ cls: 'checkbox-container' });
            this.inputEl = this.toggleEl.createEl('input', { type: 'checkbox', attr: { tabindex: '0' } });
            this.isOn = false;
            this.changeCallback = null;
            this.toggleEl.addEventListener('click', (event) => {
                event.preventDefault();
                this.onClick();
            });
        }
        setDisabled(isDisabled) { super.setDisabled(isDisabled); this.toggleEl.toggleClass('is-disabled', this.disabled); return this; }
        getValue() { return this.isOn; }
        setValue(isOn) {
            this.isOn = Boolean(isOn);
            this.toggleEl.toggleClass('is-enabled', this.isOn);
            this.inputEl.checked = this.isOn;
            return this;
        }
        setTooltip(tooltip, options) { setTooltip(this.toggleEl, tooltip, options); return this; }
        onClick() {
            if (this.disabled) return;
            this.setValue(!this.isOn);
            if (this.changeCallback) this.changeCallback(this.isOn);
        }
        onChange(callback) { this.changeCallback = callback; return this; }
    }

    class DropdownComponent extends ValueComponent {
        constructor(containerElement) {
            super();
            this.selectEl = containerElement.createEl('select', { cls: 'dropdown' });
            this.changeCallback = null;
            this.selectEl.addEventListener('change', () => { if (this.changeCallback) this.changeCallback(this.getValue()); });
        }
        setDisabled(isDisabled) { super.setDisabled(isDisabled); this.selectEl.disabled = this.disabled; return this; }
        addOption(value, display) { this.selectEl.createEl('option', { value, text: display }); return this; }
        addOptions(options) { for (const value of Object.keys(options)) this.addOption(value, options[value]); return this; }
        getValue() { return this.selectEl.value; }
        setValue(value) { this.selectEl.value = value; return this; }
        onChange(callback) { this.changeCallback = callback; return this; }
    }

    class SliderComponent extends ValueComponent {
        constructor(containerElement) {
            super();
            this.sliderEl = containerElement.createEl('input', { type: 'range', cls: 'slider' });
            this.isInstant = false;
            this.changeCallback = null;
            this.valueLabel = null;
            const report = () => {
                if (this.valueLabel) this.valueLabel.setText(this.getValuePretty());
                if (this.changeCallback) this.changeCallback(this.getValue());
            };
            this.sliderEl.addEventListener('input', () => { if (this.isInstant) report(); else if (this.valueLabel) this.valueLabel.setText(this.getValuePretty()); });
            this.sliderEl.addEventListener('change', () => { if (!this.isInstant) report(); });
        }
        setDisabled(isDisabled) { super.setDisabled(isDisabled); this.sliderEl.disabled = this.disabled; return this; }
        setInstant(isInstant) { this.isInstant = Boolean(isInstant); return this; }
        setLimits(minimum, maximum, step) {
            if (minimum !== null && minimum !== undefined) this.sliderEl.min = String(minimum);
            if (maximum !== null && maximum !== undefined) this.sliderEl.max = String(maximum);
            this.sliderEl.step = step === 'any' ? 'any' : String(step);
            return this;
        }
        getValue() { return Number(this.sliderEl.value); }
        setValue(value) { this.sliderEl.value = String(value); if (this.valueLabel) this.valueLabel.setText(this.getValuePretty()); return this; }
        getValuePretty() { return this.displayFormat ? this.displayFormat(this.getValue()) : String(this.getValue()); }
        setDisplayFormat(format) { this.displayFormat = format; if (this.valueLabel) this.valueLabel.setText(this.getValuePretty()); return this; }
        setDynamicTooltip() {
            if (!this.valueLabel) this.valueLabel = this.sliderEl.insertAdjacentElement('afterend', createSpan({ cls: 'slider-value' }));
            this.valueLabel.setText(this.getValuePretty());
            return this;
        }
        showTooltip() { this.setDynamicTooltip(); }
        setTooltip(tooltip, options) { setTooltip(this.sliderEl, tooltip, options); return this; }
        onChange(callback) { this.changeCallback = callback; return this; }
    }

    class ButtonComponent extends BaseComponent {
        constructor(containerElement) {
            super();
            this.buttonEl = containerElement.createEl('button');
            this.clickCallback = null;
            this.buttonEl.addEventListener('click', (event) => { if (!this.disabled && this.clickCallback) this.clickCallback(event); });
        }
        setDisabled(isDisabled) { super.setDisabled(isDisabled); this.buttonEl.disabled = this.disabled; return this; }
        setCta() { this.buttonEl.addClass('mod-cta'); return this; }
        removeCta() { this.buttonEl.removeClass('mod-cta'); return this; }
        setWarning() { this.buttonEl.addClass('mod-warning'); return this; }
        setDestructive() { this.buttonEl.addClass('mod-destructive'); return this; }
        removeDestructive() { this.buttonEl.removeClass('mod-destructive'); return this; }
        setTooltip(tooltip, options) { setTooltip(this.buttonEl, tooltip, options); return this; }
        setButtonText(text) { this.buttonEl.setText(text); return this; }
        setIcon(iconName) { setIcon(this.buttonEl, iconName); return this; }
        setClass(className) { this.buttonEl.addClass(className); return this; }
        onClick(callback) { this.clickCallback = callback; return this; }
    }

    class ExtraButtonComponent extends BaseComponent {
        constructor(containerElement) {
            super();
            this.extraSettingsEl = containerElement.createDiv({ cls: 'clickable-icon extra-setting-button' });
            this.clickCallback = null;
            this.extraSettingsEl.addEventListener('click', () => { if (!this.disabled && this.clickCallback) this.clickCallback(); });
            setIcon(this.extraSettingsEl, 'settings');
        }
        setDisabled(isDisabled) { super.setDisabled(isDisabled); this.extraSettingsEl.toggleClass('is-disabled', this.disabled); return this; }
        setTooltip(tooltip, options) { setTooltip(this.extraSettingsEl, tooltip, options); return this; }
        setIcon(iconName) { setIcon(this.extraSettingsEl, iconName); return this; }
        onClick(callback) { this.clickCallback = callback; return this; }
    }

    function hexToRgb(hex) {
        const match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '');
        return match ? { r: parseInt(match[1], 16), g: parseInt(match[2], 16), b: parseInt(match[3], 16) } : { r: 0, g: 0, b: 0 };
    }
    function rgbToHex(color) {
        return '#' + [color.r, color.g, color.b].map((channel) => Math.round(Math.min(Math.max(channel, 0), 255)).toString(16).padStart(2, '0')).join('');
    }
    function rgbToHsl(color) {
        const red = color.r / 255; const green = color.g / 255; const blue = color.b / 255;
        const maximum = Math.max(red, green, blue); const minimum = Math.min(red, green, blue);
        const lightness = (maximum + minimum) / 2;
        if (maximum === minimum) return { h: 0, s: 0, l: lightness };
        const difference = maximum - minimum;
        const saturation = lightness > 0.5 ? difference / (2 - maximum - minimum) : difference / (maximum + minimum);
        let hue;
        if (maximum === red) hue = (green - blue) / difference + (green < blue ? 6 : 0);
        else if (maximum === green) hue = (blue - red) / difference + 2;
        else hue = (red - green) / difference + 4;
        return { h: hue * 60, s: saturation, l: lightness };
    }
    function hslToRgb(color) {
        const hue = (((color.h % 360) + 360) % 360) / 360;
        const { s: saturation, l: lightness } = color;
        if (saturation === 0) return { r: lightness * 255, g: lightness * 255, b: lightness * 255 };
        const channel = (offset) => {
            let position = hue + offset;
            if (position < 0) position += 1;
            if (position > 1) position -= 1;
            const upper = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation;
            const lower = 2 * lightness - upper;
            if (position < 1 / 6) return lower + (upper - lower) * 6 * position;
            if (position < 1 / 2) return upper;
            if (position < 2 / 3) return lower + (upper - lower) * (2 / 3 - position) * 6;
            return lower;
        };
        return { r: channel(1 / 3) * 255, g: channel(0) * 255, b: channel(-1 / 3) * 255 };
    }

    class ColorComponent extends ValueComponent {
        constructor(containerElement) {
            super();
            this.colorPickerEl = containerElement.createEl('input', { type: 'color' });
            this.changeCallback = null;
            this.colorPickerEl.addEventListener('input', () => { if (this.changeCallback) this.changeCallback(this.getValue()); });
        }
        setDisabled(isDisabled) { super.setDisabled(isDisabled); this.colorPickerEl.disabled = this.disabled; return this; }
        getValue() { return this.colorPickerEl.value; }
        getValueRgb() { return hexToRgb(this.getValue()); }
        getValueHsl() { return rgbToHsl(this.getValueRgb()); }
        setValue(value) { this.colorPickerEl.value = value; return this; }
        setValueRgb(color) { return this.setValue(rgbToHex(color)); }
        setValueHsl(color) { return this.setValue(rgbToHex(hslToRgb(color))); }
        onChange(callback) { this.changeCallback = callback; return this; }
    }

    class ProgressBarComponent extends ValueComponent {
        constructor(containerElement) {
            super();
            this.progressBar = containerElement.createDiv({ cls: 'setting-progress-bar' });
            this.lineEl = this.progressBar.createDiv({ cls: 'setting-progress-bar-inner' });
            this.value = 0;
        }
        getValue() { return this.value; }
        setValue(value) {
            this.value = Math.min(Math.max(Number(value) || 0, 0), 100);
            this.lineEl.style.width = this.value + '%';
            return this;
        }
    }

    class DisplayValueComponent {
        constructor(containerElement) {
            this.valueEl = containerElement.createDiv({ cls: 'setting-display-value' });
        }
        setDisabled() { return this; }
        setValue(value) { this.valueEl.setText(value === null || value === undefined ? '' : value); return this; }
        setStatus(status) { this.valueEl.toggleClass('mod-warning', status === 'warning'); return this; }
    }

    // MARK: Setting

    class Setting {
        constructor(containerElement) {
            this.settingEl = containerElement.createDiv({ cls: 'setting-item' });
            this.infoEl = this.settingEl.createDiv({ cls: 'setting-item-info' });
            this.nameEl = this.infoEl.createDiv({ cls: 'setting-item-name' });
            this.descEl = this.infoEl.createDiv({ cls: 'setting-item-description' });
            this.controlEl = this.settingEl.createDiv({ cls: 'setting-item-control' });
            this.components = [];
        }
        setName(name) { this.nameEl.setText(name); return this; }
        setDesc(description) { this.descEl.setText(description); return this; }
        setClass(className) { this.settingEl.addClass(className); return this; }
        setTooltip(tooltip, options) { setTooltip(this.nameEl, tooltip, options); return this; }
        setHeading() { this.settingEl.addClass('setting-item-heading'); return this; }
        setDisabled(isDisabled) {
            this.settingEl.toggleClass('is-disabled', isDisabled);
            for (const component of this.components) component.setDisabled(isDisabled);
            return this;
        }
        addComponentOf(componentType, callback) {
            const component = new componentType(this.controlEl);
            this.components.push(component);
            if (callback) callback(component);
            return this;
        }
        addButton(callback) { return this.addComponentOf(ButtonComponent, callback); }
        addExtraButton(callback) { return this.addComponentOf(ExtraButtonComponent, callback); }
        addToggle(callback) { return this.addComponentOf(ToggleComponent, callback); }
        addText(callback) { return this.addComponentOf(TextComponent, callback); }
        addSecret(callback) { return this.addComponentOf(SecretComponent, callback); }
        addSearch(callback) { return this.addComponentOf(SearchComponent, callback); }
        addTextArea(callback) { return this.addComponentOf(TextAreaComponent, callback); }
        addMomentFormat(callback) { return this.addComponentOf(MomentFormatComponent, callback); }
        addDropdown(callback) { return this.addComponentOf(DropdownComponent, callback); }
        addColorPicker(callback) { return this.addComponentOf(ColorComponent, callback); }
        addProgressBar(callback) { return this.addComponentOf(ProgressBarComponent, callback); }
        addSlider(callback) { return this.addComponentOf(SliderComponent, callback); }
        addDisplayValue(callback) { return this.addComponentOf(DisplayValueComponent, callback); }
        setErrorMessage(message) {
            if (!this.errorEl) this.errorEl = this.infoEl.createDiv({ cls: 'setting-item-error' });
            this.errorEl.setText(message || '');
            this.errorEl.toggle(Boolean(message));
            this.settingEl.toggleClass('has-error', Boolean(message));
            return this;
        }
        addComponent(callback) {
            const component = callback(this.controlEl);
            if (component) this.components.push(component);
            return this;
        }
        then(callback) { callback(this); return this; }
        clear() {
            this.controlEl.empty();
            this.components = [];
            return this;
        }
    }

    class SettingGroup {
        constructor(containerElement) {
            this.groupEl = containerElement.createDiv({ cls: 'setting-group' });
            this.headerEl = this.groupEl.createDiv({ cls: 'setting-group-heading' });
            this.headerControlsEl = this.headerEl.createDiv({ cls: 'setting-group-heading-controls' });
            this.itemsEl = this.groupEl.createDiv({ cls: 'setting-items' });
            this.listEl = this.itemsEl;
        }
        addSearch(callback) { callback(new SearchComponent(this.headerControlsEl)); return this; }
        addExtraButton(callback) { callback(new ExtraButtonComponent(this.headerControlsEl)); return this; }
        setHeading(heading) {
            if (!this.headingTextEl) this.headingTextEl = this.headerEl.createDiv({ cls: 'setting-group-heading-text', prepend: true });
            this.headingTextEl.setText(heading);
            return this;
        }
        addSetting(callback) {
            const setting = new Setting(this.itemsEl);
            callback(setting);
            return this;
        }
        addClass(className) { this.groupEl.addClass(className); return this; }
    }

    // MARK: Confirmation dialogs

    class ConfirmationModal extends Modal {
        constructor(app) {
            super(app);
            this.modalEl.addClass('mod-confirmation');
            this.buttonContainerEl = this.modalEl.createDiv({ cls: 'modal-button-container' });
        }
        addClass(className) { this.modalEl.addClass(className); return this; }
        addCheckbox(label, callback) {
            const labelElement = this.buttonContainerEl.createEl('label', { cls: 'mod-checkbox' });
            const checkbox = labelElement.createEl('input', { type: 'checkbox', attr: { tabindex: '-1' } });
            labelElement.appendText(label);
            checkbox.addEventListener('change', () => callback(checkbox.checked));
            return this;
        }
        addButton(callback) {
            const button = new ConfirmationButton(this.buttonContainerEl, this);
            callback(button);
            return this;
        }
        addCancelButton(text) {
            return this.addButton((button) => button.setButtonText(text || 'Cancel').setCancel());
        }
    }

    class ConfirmationButton extends ButtonComponent {
        constructor(containerElement, modal) {
            super(containerElement);
            this.modal = modal;
            this.isCancel = false;
            this.buttonEl.addEventListener('click', () => { if (this.isCancel || !this.clickCallback) this.modal.close(); });
        }
        onClick(handler) {
            this.clickCallback = async (event) => {
                const outcome = await handler(event);
                if (outcome !== false) this.modal.close();
            };
            return this;
        }
        setInitialFocus() { globalScope.setTimeout(() => this.buttonEl.focus(), 0); return this; }
        setSecondary() { this.buttonEl.addClass('mod-secondary'); return this; }
        setCancel() { this.isCancel = true; this.buttonEl.addClass('mod-cancel'); return this; }
    }

    // MARK: Setting tabs

    class SettingTab {
        constructor(app) {
            this.app = app;
            this.containerEl = createDiv({ cls: 'vertical-tab-content' });
            this.icon = 'settings';
        }
        display() {}
        hide() {}
    }

    class SettingPage {
        constructor() {
            this.rootEl = createDiv({ cls: 'setting-page' });
            this.titlebarEl = this.rootEl.createDiv({ cls: 'setting-page-titlebar' });
            this.containerEl = this.rootEl.createDiv({ cls: 'setting-page-content vertical-tab-content' });
            this.title = '';
        }
        display() {}
        hide() {}
    }

    class PluginSettingTab extends SettingTab {
        constructor(app, plugin) {
            super(app);
            this.plugin = plugin;
        }
    }

    // MARK: Suggestions

    class SuggestionList {
        constructor(owner, containerElement, scope) {
            this.owner = owner;
            this.containerEl = containerElement;
            this.values = [];
            this.suggestionElements = [];
            this.selectedPosition = 0;
            containerElement.on('click', '.suggestion-item', (event, element) => {
                event.preventDefault();
                const position = this.suggestionElements.indexOf(element);
                this.setSelectedItem(position);
                this.useSelectedItem(event);
            });
            containerElement.on('mousemove', '.suggestion-item', (event, element) => {
                this.setSelectedItem(this.suggestionElements.indexOf(element));
            });
            scope.register([], 'ArrowUp', (event) => { this.setSelectedItem(this.selectedPosition - 1); event.preventDefault(); return false; });
            scope.register([], 'ArrowDown', (event) => { this.setSelectedItem(this.selectedPosition + 1); event.preventDefault(); return false; });
            scope.register([], 'Enter', (event) => { this.useSelectedItem(event); return false; });
        }
        setSuggestions(values) {
            this.containerEl.empty();
            this.values = values || [];
            this.suggestionElements = this.values.map((value) => {
                const element = this.containerEl.createDiv({ cls: 'suggestion-item' });
                this.owner.renderSuggestion(value, element);
                return element;
            });
            this.setSelectedItem(0);
        }
        setSelectedItem(position) {
            if (this.suggestionElements.length === 0) return;
            const wrapped = ((position % this.suggestionElements.length) + this.suggestionElements.length) % this.suggestionElements.length;
            const previous = this.suggestionElements[this.selectedPosition];
            if (previous) previous.removeClass('is-selected');
            this.selectedPosition = wrapped;
            const selected = this.suggestionElements[wrapped];
            selected.addClass('is-selected');
            if (selected.scrollIntoView) selected.scrollIntoView({ block: 'nearest' });
        }
        useSelectedItem(event) {
            const value = this.values[this.selectedPosition];
            if (value !== undefined) this.owner.selectSuggestion(value, event);
        }
    }

    class SuggestModal extends Modal {
        constructor(app) {
            super(app);
            this.limit = 100;
            this.emptyStateText = 'No results found.';
            this.modalEl.addClass('prompt');
            this.headerEl.detach();
            this.closeButtonEl.detach();
            this.inputEl = this.modalEl.createEl('input', { cls: 'prompt-input', type: 'text', attr: { enterkeyhint: 'done', spellcheck: 'false' } });
            this.modalEl.insertBefore(this.inputEl, this.contentEl);
            this.resultContainerEl = this.contentEl;
            this.resultContainerEl.addClass('prompt-results');
            this.instructionsEl = this.modalEl.createDiv({ cls: 'prompt-instructions' });
            this.suggestionList = new SuggestionList(this, this.resultContainerEl, this.scope);
            this.inputEl.addEventListener('input', () => this.updateSuggestions());
        }
        setPlaceholder(placeholder) { this.inputEl.placeholder = placeholder; }
        setInstructions(instructions) {
            this.instructionsEl.empty();
            for (const instruction of instructions) {
                const element = this.instructionsEl.createDiv({ cls: 'prompt-instruction' });
                element.createSpan({ cls: 'prompt-instruction-command', text: instruction.command });
                element.createSpan({ text: instruction.purpose });
            }
        }
        onOpen() {
            this.updateSuggestions();
            this.inputEl.focus();
        }
        async updateSuggestions() {
            const query = this.inputEl.value;
            const suggestions = await this.getSuggestions(query);
            if (query !== this.inputEl.value) return;
            const limited = (suggestions || []).slice(0, this.limit);
            if (limited.length === 0) {
                this.resultContainerEl.empty();
                this.onNoSuggestion();
                return;
            }
            this.suggestionList.setSuggestions(limited);
        }
        onNoSuggestion() {
            this.resultContainerEl.createDiv({ cls: 'suggestion-empty', text: this.emptyStateText });
        }
        selectSuggestion(value, event) {
            this.close();
            this.onChooseSuggestion(value, event);
        }
        selectActiveSuggestion(event) { this.suggestionList.useSelectedItem(event); }
        getSuggestions() { return []; }
        renderSuggestion(value, element) { element.setText(String(value)); }
        onChooseSuggestion() {}
    }

    class FuzzySuggestModal extends SuggestModal {
        getSuggestions(query) {
            const search = exportedApi.prepareFuzzySearch(query);
            const results = [];
            for (const item of this.getItems()) {
                const match = search(this.getItemText(item));
                if (match) results.push({ item, match });
            }
            if (query) exportedApi.sortSearchResults(results);
            return results;
        }
        renderSuggestion(result, element) {
            exportedApi.renderResults(element, this.getItemText(result.item), result.match);
        }
        onChooseSuggestion(result, event) { this.onChooseItem(result.item, event); }
        getItems() { return []; }
        getItemText(item) { return String(item); }
        onChooseItem() {}
    }

    /// Suggestions under a text field, as Obsidian's popover suggest does.
    class PopoverSuggest {
        constructor(app, scope) {
            this.app = app || runtime.app;
            this.scope = scope || new Scope(this.app.scope);
            this.suggestEl = createDiv({ cls: 'suggestion-container' });
            const suggestionsElement = this.suggestEl.createDiv({ cls: 'suggestion' });
            this.suggestions = new SuggestionList(this, suggestionsElement, this.scope);
            this.scope.register([], 'Escape', () => { this.close(); return false; });
            this.isOpen = false;
        }
        open() {
            if (this.isOpen) return;
            this.isOpen = true;
            pluginSurface.hostElement().ownerDocument.body.appendChild(this.suggestEl);
            this.app.keymap.pushScope(this.scope);
        }
        close() {
            if (!this.isOpen) return;
            this.isOpen = false;
            this.app.keymap.popScope(this.scope);
            this.suggestEl.detach();
        }
        renderSuggestion() {}
        selectSuggestion() {}
        onHistoryBack() { this.close(); return true; }
    }

    class AbstractInputSuggest extends PopoverSuggest {
        constructor(app, textInputElement) {
            super(app);
            this.textInputEl = textInputElement;
            this.limit = 100;
            this.selectCallback = null;
            this.keydownListener = (event) => { if (this.isOpen) this.scope.handleKeyEvent(event); };
            textInputElement.addEventListener('input', () => this.onInputChanged());
            textInputElement.addEventListener('focus', () => this.onInputChanged());
            textInputElement.addEventListener('blur', () => globalScope.setTimeout(() => this.close(), 150));
            textInputElement.addEventListener('keydown', this.keydownListener);
        }
        async onInputChanged() {
            const query = this.getValue();
            const suggestions = await this.getSuggestions(query);
            if (query !== this.getValue()) return;
            if (!suggestions || suggestions.length === 0) { this.close(); return; }
            this.suggestions.setSuggestions(suggestions.slice(0, this.limit));
            this.open();
            const bounds = this.textInputEl.getBoundingClientRect();
            this.suggestEl.style.left = bounds.left + 'px';
            this.suggestEl.style.top = bounds.bottom + 'px';
            this.suggestEl.style.minWidth = bounds.width + 'px';
        }
        getValue() { return this.textInputEl.value !== undefined ? this.textInputEl.value : this.textInputEl.textContent; }
        setValue(value) {
            if (this.textInputEl.value !== undefined) this.textInputEl.value = value;
            else this.textInputEl.textContent = value;
        }
        onSelect(callback) { this.selectCallback = callback; return this; }
        selectSuggestion(value, event) {
            if (this.selectCallback) this.selectCallback(value, event);
            this.close();
        }
        getSuggestions() { return []; }
    }

    /// Suggestions while typing in a note. Graphite's editor is native, so these never appear.
    class EditorSuggest extends PopoverSuggest {
        constructor(app) {
            super(app);
            this.context = null;
            this.limit = 100;
            this.instructionsEl = this.suggestEl.createDiv({ cls: 'prompt-instructions' });
        }
        setInstructions() {}
        onTrigger() { return null; }
        getSuggestions() { return []; }
    }

    // MARK: Menus

    class MenuItem {
        constructor(menu) {
            this.menu = menu;
            this.title = '';
            this.icon = null;
            this.isChecked = false;
            this.isDisabled = false;
            this.isWarning = false;
            this.section = '';
            this.clickCallback = null;
            this.submenu = null;
            this.dom = createDiv({ cls: 'menu-item' });
        }
        setTitle(title) { this.title = typeof title === 'string' ? title : title.textContent; return this; }
        setIcon(icon) { this.icon = icon; return this; }
        setChecked(isChecked) { this.isChecked = Boolean(isChecked); return this; }
        setDisabled(isDisabled) { this.isDisabled = Boolean(isDisabled); return this; }
        setWarning(isWarning) { this.isWarning = Boolean(isWarning); return this; }
        setIsLabel(isLabel) { this.isDisabled = Boolean(isLabel) || this.isDisabled; return this; }
        setSection(section) { this.section = section; return this; }
        setSubmenu() {
            this.submenu = new Menu();
            return this.submenu;
        }
        onClick(callback) { this.clickCallback = callback; return this; }
    }

    class MenuSeparator {}

    /// A plugin's menu. Graphite shows it natively, the way its own menus look.
    class Menu extends Component {
        constructor() {
            super();
            this.items = [];
            this.hideCallbacks = [];
            this.isUsingNativeMenu = true;
        }
        setNoIcon() { return this; }
        setUseNativeMenu(isUsingNativeMenu) { this.isUsingNativeMenu = isUsingNativeMenu; return this; }
        addItem(callback) {
            const item = new MenuItem(this);
            this.items.push(item);
            callback(item);
            return this;
        }
        addSeparator() { this.items.push(new MenuSeparator()); return this; }
        flattenedItems() {
            const flattened = [];
            for (const item of this.items) {
                if (item instanceof MenuSeparator) { flattened.push({ isSeparator: true }); continue; }
                if (item.submenu) {
                    for (const subitem of item.submenu.flattenedItems()) flattened.push(Object.assign({}, subitem, { title: subitem.isSeparator ? '' : item.title + ' › ' + subitem.title }));
                    continue;
                }
                flattened.push({ item, title: item.title, icon: item.icon, isChecked: item.isChecked, isDisabled: item.isDisabled, isWarning: item.isWarning, section: item.section });
            }
            return flattened;
        }
        async showMenu() {
            const entries = this.flattenedItems();
            const choices = entries.filter((entry) => !entry.isSeparator);
            try {
                const response = await hostBridge.send('menu.show', {
                    items: choices.map((entry, position) => ({ position, title: entry.title, icon: entry.icon || null, isChecked: entry.isChecked, isDisabled: entry.isDisabled, isWarning: entry.isWarning, section: entry.section || '' })),
                });
                const chosen = typeof response.chosenPosition === 'number' ? choices[response.chosenPosition] : null;
                if (chosen && chosen.item.clickCallback && !chosen.isDisabled) chosen.item.clickCallback(new globalScope.MouseEvent('click'));
            } finally {
                this.hide();
            }
        }
        showAtMouseEvent() { this.showMenu(); return this; }
        showAtPosition() { this.showMenu(); return this; }
        hide() {
            for (const callback of this.hideCallbacks.splice(0)) {
                try { callback(); } catch (error) { console.error(error); }
            }
            this.unload();
            return this;
        }
        close() { this.hide(); }
        onHide(callback) { this.hideCallbacks.push(callback); }
        setParentElement() { return this; }
        onHistoryBack() { this.hide(); return true; }
        static forEvent() { return new Menu(); }
    }

    // MARK: Hover previews

    class HoverPopover extends Component {
        constructor(parent, targetElement) {
            super();
            this.parent = parent;
            this.targetEl = targetElement;
            this.hoverEl = createDiv({ cls: 'popover hover-popover' });
            this.state = 0;
            runtime.reportUnsupportedFeature('Hover previews');
        }
        hide() {}
    }

    Object.assign(exportedApi, {
        setIcon, getIcon, addIcon, removeIcon, getIconIds, setTooltip, displayTooltip,
        Scope, Keymap, Notice, Modal,
        BaseComponent, ValueComponent, AbstractTextComponent, TextComponent, SecretComponent, TextAreaComponent, SearchComponent,
        MomentFormatComponent, ToggleComponent, DropdownComponent, SliderComponent, ButtonComponent, ExtraButtonComponent,
        ColorComponent, ProgressBarComponent, DisplayValueComponent, Setting, SettingGroup, SettingTab, PluginSettingTab, SettingPage,
        ConfirmationModal, ConfirmationButton,
        SuggestModal, FuzzySuggestModal, PopoverSuggest, AbstractInputSuggest, EditorSuggest,
        Menu, MenuItem, MenuSeparator, HoverPopover,
    });
    exportedApi.PopoverState = { Showing: 0, Shown: 1, Hiding: 2, Hidden: 3 };
})(globalThis);

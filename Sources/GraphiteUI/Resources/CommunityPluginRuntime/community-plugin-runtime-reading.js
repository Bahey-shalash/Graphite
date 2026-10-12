// Plugins' code blocks in Graphite's native reading view, and the links plugins draw.
//
// A note's reading view is native, so a block such as ```` ```dataview ```` cannot be drawn
// into it directly. Each block is drawn here instead, in the runtime's page, by the
// plugin's code block processor, and stays alive while the note shows it: the plugin keeps
// its block up to date as it does in Obsidian. Graphite receives a copy of the block's HTML
// each time it changes and shows the copy in a web view of its own inside the note, without
// running any script there; a tap on the copy comes back as a tap on the element it hit here.
(function installRuntimeReading(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Component } = exportedApi;
    const hostBridge = runtime.hostBridge;

    /// A larger block is shown as too large rather than copied: the copy crosses to the
    /// app as one message, and a runaway plugin must not build an unbounded one.
    const maximumSnapshotCharacters = 4 * 1024 * 1024;
    /// How long changes are gathered before a block's new copy is sent, so a plugin that
    /// draws a table row by row sends the table once.
    const snapshotDelayMilliseconds = 60;
    /// How long a processor may take before its block is sent as it is; the block keeps
    /// updating afterwards.
    const processorWaitMilliseconds = 15000;

    /// Blocks shown in a note, by the identifier Graphite gave them.
    const drawnBlocks = new Map();

    /// Where blocks are drawn: on the page's screen, so plugins that draw only what is
    /// visible (Tasks) draw them, but transparent and behind everything; each with the width
    /// it has in the note, so plugins that measure their element (charts) lay out as seen.
    function readingArea() {
        const document = globalScope.document;
        let area = document.querySelector('.graphite-reading-blocks');
        if (!area) {
            area = document.createElement('div');
            area.className = 'graphite-reading-blocks';
            area.setAttribute('aria-hidden', 'true');
            document.body.appendChild(area);
        }
        return area;
    }

    // MARK: Copies of blocks

    /// Copies what the live block shows that its HTML does not hold: whether boxes are
    /// ticked, what fields contain, and what canvases have drawn (as pictures).
    function copyLiveState(originalRoot, copiedRoot) {
        const selector = 'input, textarea, select, canvas';
        const originals = Array.from(originalRoot.querySelectorAll(selector));
        const copies = Array.from(copiedRoot.querySelectorAll(selector));
        originals.forEach((original, position) => {
            const copy = copies[position];
            if (!copy) return;
            switch (original.tagName) {
            case 'INPUT':
                if (original.type === 'checkbox' || original.type === 'radio') {
                    if (original.checked) copy.setAttribute('checked', ''); else copy.removeAttribute('checked');
                } else if (original.type !== 'file' && original.type !== 'password') {
                    copy.setAttribute('value', original.value);
                }
                break;
            case 'TEXTAREA':
                copy.textContent = original.value;
                break;
            case 'SELECT':
                Array.from(copy.options).forEach((option, optionPosition) => {
                    if (original.options[optionPosition] && original.options[optionPosition].selected) option.setAttribute('selected', '');
                    else option.removeAttribute('selected');
                });
                break;
            case 'CANVAS': {
                // A picture in the canvas's place keeps the element's position among its
                // siblings, which taps are sent back by.
                const picture = globalScope.document.createElement('img');
                try { picture.src = original.toDataURL('image/png'); } catch (error) { picture.alt = ''; }
                const bounds = original.getBoundingClientRect();
                picture.style.width = (bounds.width || original.width) + 'px';
                picture.style.height = (bounds.height || original.height) + 'px';
                picture.className = original.className;
                copy.replaceWith(picture);
                break;
            }
            default:
                break;
            }
        });
    }

    function copyOf(entry) {
        const copiedRoot = entry.element.cloneNode(true);
        copyLiveState(entry.element, copiedRoot);
        const html = copiedRoot.outerHTML;
        if (html.length > maximumSnapshotCharacters) {
            return '<div class="graphite-plugin-error">This block is too large for Graphite to show (' + Math.round(html.length / 1048576) + ' MB).</div>';
        }
        return html;
    }

    function scheduleCopy(entry) {
        if (entry.isCopyScheduled || entry.isReleased) return;
        entry.isCopyScheduled = true;
        globalScope.setTimeout(() => {
            entry.isCopyScheduled = false;
            if (entry.isReleased) return;
            sendCopyIfChanged(entry);
        }, snapshotDelayMilliseconds);
    }

    function sendCopyIfChanged(entry) {
        const html = copyOf(entry);
        if (html === entry.lastSentHTML) return;
        entry.lastSentHTML = html;
        hostBridge.notify('codeBlock.changed', { blockIdentifier: entry.blockIdentifier, html });
    }

    /// The style sheets of loaded plugins, which the copies need to look as they do here.
    function pluginStyles() {
        return Array.from(globalScope.document.querySelectorAll('style[data-graphite-plugin]')).map((styleElement) => styleElement.textContent).join('\n');
    }

    // MARK: Drawing and releasing blocks

    function sectionInformation(message) {
        if (typeof message.noteText !== 'string' || typeof message.firstLine !== 'number') return null;
        return { text: message.noteText, lineStart: message.firstLine, lineEnd: message.firstLine + Math.max(1, message.lineCount || 1) - 1 };
    }

    function waitAtMost(promise, milliseconds) {
        return Promise.race([promise, new Promise((resolve) => globalScope.setTimeout(resolve, milliseconds))]);
    }

    function release(blockIdentifier) {
        const entry = drawnBlocks.get(blockIdentifier);
        if (!entry) return;
        drawnBlocks.delete(blockIdentifier);
        entry.isReleased = true;
        if (entry.observer) entry.observer.disconnect();
        try { entry.component.unload(); } catch (error) { console.error(error); }
        entry.container.remove();
    }

    async function draw(message) {
        const app = runtime.app;
        release(message.blockIdentifier);
        const registered = runtime.codeBlockProcessors.get(message.language);
        if (!app || !registered) return { isDrawn: false, message: 'No plugin draws “' + message.language + '” code blocks now.' };
        const sourcePath = message.sourcePath || '';
        const container = readingArea().createDiv({ cls: 'markdown-preview-view markdown-rendered graphite-reading-block' });
        container.style.width = Math.max(200, Math.min(4000, Number(message.width) || 700)) + 'px';
        container.setAttribute('data-graphite-source-path', sourcePath);
        const blockElement = container.createDiv({ cls: 'block-language-' + message.language });
        const component = new Component();
        component.load();
        const entry = {
            blockIdentifier: message.blockIdentifier, container, element: blockElement, component,
            observer: null, isCopyScheduled: false, isReleased: false, lastSentHTML: null,
        };
        drawnBlocks.set(message.blockIdentifier, entry);
        const cache = app.metadataCache.getCache(sourcePath);
        const section = sectionInformation(message);
        const context = {
            docId: 'graphite-' + message.blockIdentifier,
            sourcePath,
            frontmatter: cache && cache.frontmatter ? cache.frontmatter : null,
            el: blockElement,
            addChild(child) { component.addChild(child); },
            getSectionInfo() { return section; },
        };
        // Changes are watched from the start, so what an asynchronous processor draws after
        // this answer reaches Graphite too.
        entry.observer = new globalScope.MutationObserver(() => scheduleCopy(entry));
        entry.observer.observe(container, { subtree: true, childList: true, attributes: true, characterData: true });
        container.addEventListener('change', () => scheduleCopy(entry), true);
        container.addEventListener('input', () => scheduleCopy(entry), true);
        try {
            await waitAtMost(Promise.resolve(registered.handler(String(message.source || ''), blockElement, context)), processorWaitMilliseconds);
        } catch (error) {
            console.error(error);
            hostBridge.notify('plugin.failure', { pluginIdentifier: registered.pluginIdentifier, message: 'A “' + message.language + '” block failed: ' + (error && error.message ? error.message : String(error)) });
            blockElement.createEl('pre', { cls: 'graphite-plugin-error', text: String(error && error.message ? error.message : error) });
        }
        if (entry.isReleased) return { isDrawn: false, message: 'The block was closed while it was drawn.' };
        // Obsidian runs the other post-processors over a section after its code block.
        const ordered = runtime.markdownPostProcessors.slice().sort((firstProcessor, secondProcessor) => firstProcessor.sortOrder - secondProcessor.sortOrder);
        for (const registeredProcessor of ordered) {
            try {
                await waitAtMost(Promise.resolve(registeredProcessor.postProcessor(blockElement, context)), processorWaitMilliseconds);
            } catch (error) {
                console.error(error);
            }
        }
        if (entry.isReleased) return { isDrawn: false, message: 'The block was closed while it was drawn.' };
        entry.lastSentHTML = copyOf(entry);
        return { isDrawn: true, html: entry.lastSentHTML, styles: pluginStyles() };
    }

    /// Element children, by position, from the block's element down to the one tapped.
    function elementAtPath(entry, elementPath) {
        let element = entry.element;
        for (const position of elementPath || []) {
            if (!element || !element.children || typeof position !== 'number') return null;
            element = element.children[position];
        }
        return element || null;
    }

    /// A tap as a browser delivers it: pointer and mouse presses, then the click, whose
    /// default action ticks a box or follows a link.
    function tap(element) {
        const view = globalScope;
        const options = { bubbles: true, cancelable: true, composed: true, view, button: 0 };
        if (typeof globalScope.PointerEvent === 'function') element.dispatchEvent(new globalScope.PointerEvent('pointerdown', Object.assign({ pointerType: 'touch', isPrimary: true }, options)));
        element.dispatchEvent(new globalScope.MouseEvent('mousedown', options));
        if (typeof globalScope.PointerEvent === 'function') element.dispatchEvent(new globalScope.PointerEvent('pointerup', Object.assign({ pointerType: 'touch', isPrimary: true }, options)));
        element.dispatchEvent(new globalScope.MouseEvent('mouseup', options));
        if (typeof element.click === 'function') element.click();
        else element.dispatchEvent(new globalScope.MouseEvent('click', options));
    }

    /// Text typed into a field of the copy, given to the plugin's field as typing would.
    function enter(element, value) {
        if (!('value' in element)) return;
        element.value = String(value);
        element.dispatchEvent(new globalScope.Event('input', { bubbles: true }));
        element.dispatchEvent(new globalScope.Event('change', { bubbles: true }));
    }

    Object.assign(runtime.messageHandlers, {
        async 'codeBlock.render'(message) {
            return draw(message);
        },
        async 'codeBlock.event'(message) {
            const entry = drawnBlocks.get(message.blockIdentifier);
            if (!entry) return { isHandled: false };
            const element = elementAtPath(entry, message.elementPath);
            if (!element) return { isHandled: false };
            if (message.eventType === 'input') enter(element, message.value);
            else tap(element);
            // The plugin's handlers usually change the block at once; its copy goes back with
            // the answer, and later changes as usual.
            await new Promise((resolve) => globalScope.setTimeout(resolve, 0));
            if (entry.isReleased) return { isHandled: true };
            entry.lastSentHTML = copyOf(entry);
            return { isHandled: true, html: entry.lastSentHTML };
        },
        async 'codeBlock.release'(message) {
            release(message.blockIdentifier);
            return {};
        },
    });

    /// Blocks drawn by a plugin that unloads go with it; Graphite draws them again when a
    /// plugin registers their language again.
    runtime.releaseAllCodeBlocks = function releaseAllCodeBlocks() {
        for (const blockIdentifier of Array.from(drawnBlocks.keys())) release(blockIdentifier);
    };

    // MARK: Links

    /// Obsidian follows links from the app, not the page: internal links open the note,
    /// web links the browser. Without this a link in a plugin's view or block would load
    /// in place of the runtime's page and end every plugin.
    function followLink(event) {
        if (event.defaultPrevented || event.button > 0) return;
        const target = event.target;
        const anchor = target && typeof target.closest === 'function' ? target.closest('a') : null;
        if (!anchor) return;
        const destination = anchor.getAttribute('data-href') || anchor.getAttribute('href') || '';
        event.preventDefault();
        if (destination === '' || destination.startsWith('#') || /^javascript:/i.test(destination)) return;
        if (/^(https?|mailto):/i.test(destination)) {
            hostBridge.notify('workspace.openExternalLink', { address: destination });
            return;
        }
        if (/^[a-z][a-z0-9+.-]*:/i.test(destination) && !anchor.classList.contains('internal-link')) return;
        const app = runtime.app;
        if (!app) return;
        const sourceElement = anchor.closest('[data-graphite-source-path]');
        const sourcePath = sourceElement ? sourceElement.getAttribute('data-graphite-source-path') : (app.workspace.getActiveFile() ? app.workspace.getActiveFile().path : '');
        let linktext = destination;
        try { linktext = decodeURI(destination); } catch (error) { linktext = destination; }
        app.workspace.openLinkText(linktext, sourcePath, exportedApi.Keymap.isModEvent(event)).catch((error) => console.error(error));
    }
    globalScope.document.addEventListener('click', followLink);
})(globalThis);

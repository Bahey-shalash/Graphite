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

    // MARK: Events copies forward

    /// The events plugins listen for on their elements that a copy cannot turn into a tap: a
    /// context menu (right-click, or a long press on a touch screen), hovering, presses that
    /// drag, and drag and drop. Each element listening for one says so in an attribute,
    /// which its copy carries, so the copy forwards these only where a plugin listens.
    const forwardedEventKinds = {
        contextmenu: 'menu',
        mouseover: 'hover', mouseenter: 'hover', mouseout: 'hover', mouseleave: 'hover',
        pointerover: 'hover', pointerenter: 'hover', pointerout: 'hover', pointerleave: 'hover',
        mousedown: 'press', pointerdown: 'press', touchstart: 'press',
        dragstart: 'drag', dragenter: 'drop', dragover: 'drop', drop: 'drop',
    };
    const listenAttribute = 'data-graphite-listens';
    const originalAddEventListener = globalScope.EventTarget.prototype.addEventListener;
    globalScope.EventTarget.prototype.addEventListener = function addEventListener(type, listener, options) {
        const kind = forwardedEventKinds[type];
        if (kind && globalScope.Element && this instanceof globalScope.Element) {
            const kinds = (this.getAttribute(listenAttribute) || '').split(' ').filter(Boolean);
            if (!kinds.includes(kind)) this.setAttribute(listenAttribute, kinds.concat(kind).join(' '));
        }
        return originalAddEventListener.call(this, type, listener, options);
    };

    /// Where a position in the copy, measured from the block's top left corner, is here, with
    /// the keys held there: plugins check them (Calendar previews a day's note while ⌘ is held).
    function pointIn(entry, message) {
        const bounds = followReplacement(entry).getBoundingClientRect();
        const clientX = bounds.left + (Number(message.x) || 0);
        const clientY = bounds.top + (Number(message.y) || 0);
        return {
            clientX, clientY, screenX: clientX, screenY: clientY,
            metaKey: message.metaKey === true, ctrlKey: message.ctrlKey === true, shiftKey: message.shiftKey === true, altKey: message.altKey === true,
        };
    }

    function mouseOptions(point, extra) {
        return Object.assign({ bubbles: true, cancelable: true, composed: true, view: globalScope }, point, extra);
    }

    /// A right-click or long press: plugins open their menu (`Menu.showAtMouseEvent`).
    function openContextMenu(entry, element, message) {
        const options = mouseOptions(pointIn(entry, message), { button: 2, buttons: 2 });
        if (typeof globalScope.PointerEvent === 'function') element.dispatchEvent(new globalScope.PointerEvent('pointerdown', Object.assign({ pointerType: 'mouse', isPrimary: true }, options)));
        element.dispatchEvent(new globalScope.MouseEvent('contextmenu', options));
    }

    function ancestorsUpTo(element, root) {
        const ancestors = [];
        for (let current = element; current && current !== root.parentNode; current = current.parentNode) ancestors.push(current);
        return ancestors;
    }

    /// The pointer moved onto another element of the copy (a mouse, trackpad or hovering
    /// Pencil), or left it: over and out events bubble from the elements, enter and leave
    /// go to each element the pointer entered or left, as a browser sends them.
    function hover(entry, element, message) {
        const root = followReplacement(entry);
        const previous = entry.hoveredElement && root.contains(entry.hoveredElement) ? entry.hoveredElement : null;
        if (previous === element) return;
        entry.hoveredElement = element;
        const options = mouseOptions(pointIn(entry, message), {});
        const hasPointerEvents = typeof globalScope.PointerEvent === 'function';
        const previousAncestors = previous ? ancestorsUpTo(previous, root) : [];
        const newAncestors = element ? ancestorsUpTo(element, root) : [];
        if (previous) {
            if (hasPointerEvents) previous.dispatchEvent(new globalScope.PointerEvent('pointerout', Object.assign({ pointerType: 'mouse' }, options, { relatedTarget: element })));
            previous.dispatchEvent(new globalScope.MouseEvent('mouseout', Object.assign({}, options, { relatedTarget: element })));
            for (const left of previousAncestors.filter((ancestor) => !newAncestors.includes(ancestor))) {
                const leaveOptions = Object.assign({}, options, { bubbles: false, relatedTarget: element });
                if (hasPointerEvents) left.dispatchEvent(new globalScope.PointerEvent('pointerleave', Object.assign({ pointerType: 'mouse' }, leaveOptions)));
                left.dispatchEvent(new globalScope.MouseEvent('mouseleave', leaveOptions));
            }
        }
        if (element) {
            if (hasPointerEvents) element.dispatchEvent(new globalScope.PointerEvent('pointerover', Object.assign({ pointerType: 'mouse' }, options, { relatedTarget: previous })));
            element.dispatchEvent(new globalScope.MouseEvent('mouseover', Object.assign({}, options, { relatedTarget: previous })));
            for (const entered of newAncestors.filter((ancestor) => !previousAncestors.includes(ancestor)).reverse()) {
                const enterOptions = Object.assign({}, options, { bubbles: false, relatedTarget: previous });
                if (hasPointerEvents) entered.dispatchEvent(new globalScope.PointerEvent('pointerenter', Object.assign({ pointerType: 'mouse' }, enterOptions)));
                entered.dispatchEvent(new globalScope.MouseEvent('mouseenter', enterOptions));
            }
        }
    }

    /// Replays a hover the copy forwarded, and answers the link a plugin asked Graphite to
    /// preview there meanwhile (`hover-link`), which the copy shows beside the element; null
    /// for none, and always while the core plugin Page Preview is off.
    function linkHoveredDuring(entry, replay) {
        const app = runtime.app;
        if (!app || !app.internalPlugins.getEnabledPluginById('page-preview')) {
            replay();
            return null;
        }
        return app.workspace.pagePreview.linkHoveredDuring(followReplacement(entry), replay);
    }

    /// A data transfer for a drag, Obsidian's own where the page has one, otherwise a
    /// stand-in holding what the plugin sets.
    function newDataTransfer() {
        try { if (typeof globalScope.DataTransfer === 'function') return new globalScope.DataTransfer(); } catch (error) { /* a stand-in follows */ }
        const data = new Map();
        return {
            dropEffect: 'none', effectAllowed: 'all', files: [], items: [],
            get types() { return Array.from(data.keys()); },
            setData(format, value) { data.set(String(format), String(value)); },
            getData(format) { return data.has(String(format)) ? data.get(String(format)) : ''; },
            clearData(format) { if (format === undefined) data.clear(); else data.delete(String(format)); },
            setDragImage() {},
        };
    }

    function dragEvent(type, point, dataTransfer) {
        const options = mouseOptions(point, { dataTransfer });
        let event = null;
        try { if (typeof globalScope.DragEvent === 'function') event = new globalScope.DragEvent(type, options); } catch (error) { event = null; }
        if (!event || event.dataTransfer !== dataTransfer) {
            event = new globalScope.MouseEvent(type, mouseOptions(point, {}));
            Object.defineProperty(event, 'dataTransfer', { value: dataTransfer });
        }
        return event;
    }

    /// A press that moves in the copy: for an element that can be dragged (`draggable`, or
    /// one listening for `dragstart`), drag and drop as a browser runs it, over the elements
    /// the copy finds under the finger; otherwise pointer and mouse presses and moves, which
    /// sliders and sortable lists follow.
    function gesture(entry, message) {
        const point = pointIn(entry, message);
        const over = (message.overPath ? elementAtPath(entry, message.overPath) : null) || (entry.gesture && entry.gesture.source);
        const hasPointerEvents = typeof globalScope.PointerEvent === 'function';
        const pointerOptions = (extra) => Object.assign({ pointerType: message.pointerType || 'touch', isPrimary: true, pointerId: 1 }, mouseOptions(point, extra));
        if (message.phase === 'down') {
            const source = elementAtPath(entry, message.elementPath);
            if (!source) return;
            const draggable = source.closest('[draggable="true"]') || source.closest('[' + listenAttribute + '~="drag"]');
            entry.gesture = { source, draggable: draggable && followReplacement(entry).contains(draggable) ? draggable : null, dataTransfer: null, over: null, accepts: false };
            if (hasPointerEvents) source.dispatchEvent(new globalScope.PointerEvent('pointerdown', pointerOptions({ button: 0, buttons: 1 })));
            source.dispatchEvent(new globalScope.MouseEvent('mousedown', mouseOptions(point, { button: 0, buttons: 1 })));
            return;
        }
        const state = entry.gesture;
        if (!state) return;
        if (state.draggable) {
            if (!state.dataTransfer && message.phase === 'move') {
                state.dataTransfer = newDataTransfer();
                if (!state.draggable.dispatchEvent(dragEvent('dragstart', point, state.dataTransfer))) { state.draggable = null; return; }
            }
            if (!state.dataTransfer) { entry.gesture = null; return; }
            if (over && over !== state.over) {
                if (state.over) state.over.dispatchEvent(dragEvent('dragleave', point, state.dataTransfer));
                over.dispatchEvent(dragEvent('dragenter', point, state.dataTransfer));
                state.over = over;
            }
            // A drop target says it takes the drop by cancelling `dragover`.
            if (over && message.phase !== 'cancel') state.accepts = !over.dispatchEvent(dragEvent('dragover', point, state.dataTransfer));
            if (message.phase === 'up' || message.phase === 'cancel') {
                if (message.phase === 'up' && over && state.accepts) over.dispatchEvent(dragEvent('drop', point, state.dataTransfer));
                state.draggable.dispatchEvent(dragEvent('dragend', point, state.dataTransfer));
                entry.gesture = null;
            }
            return;
        }
        const target = over || state.source;
        if (message.phase === 'move') {
            if (hasPointerEvents) target.dispatchEvent(new globalScope.PointerEvent('pointermove', pointerOptions({ buttons: 1 })));
            target.dispatchEvent(new globalScope.MouseEvent('mousemove', mouseOptions(point, { buttons: 1 })));
            return;
        }
        if (hasPointerEvents) target.dispatchEvent(new globalScope.PointerEvent(message.phase === 'cancel' ? 'pointercancel' : 'pointerup', pointerOptions({ button: 0, buttons: 0 })));
        target.dispatchEvent(new globalScope.MouseEvent('mouseup', mouseOptions(point, { button: 0, buttons: 0 })));
        entry.gesture = null;
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

    /// Plugins may put their own element in the block's place (`el.replaceWith(…)`, as
    /// Admonition does) instead of drawing into it; what is in the place is then the block.
    /// Several elements in its place are gathered into one, which taps are found from.
    function followReplacement(entry) {
        if (entry.leaf || entry.element.parentNode === entry.container) return entry.element;
        const replacements = Array.from(entry.container.children);
        if (replacements.length === 0) return entry.element;
        if (replacements.length === 1) {
            entry.element = replacements[0];
        } else {
            const gathered = globalScope.document.createElement('div');
            gathered.className = entry.element.className;
            for (const replacement of replacements) gathered.appendChild(replacement);
            entry.container.appendChild(gathered);
            entry.element = gathered;
        }
        return entry.element;
    }

    function copyOf(entry) {
        followReplacement(entry);
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

    /// The most style text sent to copies. Every copy of a block or view parses what it is
    /// given, so a theme that would take the total past this (themes with fonts written into
    /// their file reach several megabytes) is left out of copies, which keep the plugins'
    /// styles, Style Settings' values and the snippets.
    const maximumCopyStyleCharacters = 3 * 1024 * 1024;

    function styleText(styleElement) {
        if (styleElement.textContent.trim() !== '') return styleElement.textContent;
        try { return Array.from(styleElement.sheet ? styleElement.sheet.cssRules : []).map((rule) => rule.cssText).join('\n'); } catch (error) { return ''; }
    }

    /// The style sheets in the page, which the copies need to look as they do here: each
    /// plugin's styles.css, the styles its components add themselves (Svelte components, as
    /// in Calendar, add theirs to the page's head, some through the CSS object model, which
    /// leaves the element's text empty), the vault's theme and snippets, and the variables
    /// Style Settings writes.
    function pluginStyles() {
        const styleElements = Array.from(globalScope.document.querySelectorAll('style'));
        const texts = styleElements.map(styleText);
        // Style sheets made in script and adopted by the page (Admonition's callout colors).
        const adopted = Array.from(globalScope.document.adoptedStyleSheets || []).map((sheet) => {
            try { return Array.from(sheet.cssRules).map((rule) => rule.cssText).join('\n'); } catch (error) { return ''; }
        }).join('\n');
        if (adopted) { texts.push(adopted); styleElements.push(globalScope.document.createElement('style')); }
        const total = texts.reduce((sum, text) => sum + text.length, 0);
        if (total <= maximumCopyStyleCharacters) return texts.join('\n');
        return texts.filter((text, position) => !styleElements[position].hasAttribute('data-graphite-theme')).join('\n');
    }
    runtime.pluginStyles = pluginStyles;

    /// The page body's classes and inline style that copies take: those plugins and themes
    /// set (Style Settings' `css-settings-manager`, Minimal Theme Settings' scheme and option
    /// classes and its variables), without the runtime's own and the light or dark class, which
    /// each copy sets from Graphite's appearance.
    function bodyPresentation() {
        const body = globalScope.document.body;
        const ownClasses = new Set(['graphite-plugin-runtime', 'theme-light', 'theme-dark', 'is-mobile', 'is-ios', 'is-tablet', 'is-phone']);
        return {
            bodyClasses: Array.from(body.classList).filter((className) => !ownClasses.has(className)).join(' '),
            bodyStyle: body.getAttribute('style') || '',
        };
    }
    runtime.bodyPresentation = bodyPresentation;

    let lastSentStyles = null;
    let isStyleNotificationScheduled = false;
    /// Tells Graphite when the page's styles or body classes change (a plugin loads, Style
    /// Settings or Minimal Theme Settings changes a value, the theme changes), so the copies
    /// already shown restyle without being drawn again.
    function scheduleStyleNotification() {
        if (isStyleNotificationScheduled) return;
        isStyleNotificationScheduled = true;
        globalScope.setTimeout(() => {
            isStyleNotificationScheduled = false;
            const presentation = Object.assign({ styles: pluginStyles() }, bodyPresentation());
            const key = presentation.styles.length + '\u0000' + presentation.bodyClasses + '\u0000' + presentation.bodyStyle + '\u0000' + presentation.styles;
            if (key === lastSentStyles) return;
            lastSentStyles = key;
            hostBridge.notify('styles.changed', presentation);
        }, 150);
    }
    const styleObserver = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
            const target = mutation.target;
            const isHead = target === globalScope.document.head || (target.parentNode && target.parentNode.nodeName === 'STYLE') || target.nodeName === 'STYLE'
                || Array.from(mutation.addedNodes || []).concat(Array.from(mutation.removedNodes || [])).some((node) => node.nodeName === 'STYLE');
            if (isHead || target === globalScope.document.body) { scheduleStyleNotification(); return; }
        }
    });
    // The runtime's scripts run in the page's head, before its body exists.
    function observeStyles() {
        styleObserver.observe(globalScope.document.head, { childList: true, subtree: true, characterData: true });
        styleObserver.observe(globalScope.document.body, { attributes: true, attributeFilter: ['class', 'style'] });
        scheduleStyleNotification();
    }
    if (globalScope.document.body) observeStyles(); else globalScope.document.addEventListener('DOMContentLoaded', observeStyles);

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
        // A plugin's view outlives the place that showed it; only blocks are unloaded.
        if (entry.leaf) entry.element.detach();
        else { try { entry.component.unload(); } catch (error) { console.error(error); } }
        entry.container.remove();
    }

    /// A block's place in the reading area, its component, and the watch that sends its
    /// changes to Graphite.
    function startEntry(message, elementClass) {
        const sourcePath = message.sourcePath || '';
        const container = readingArea().createDiv({ cls: 'markdown-preview-view markdown-rendered graphite-reading-block' });
        container.style.width = Math.max(200, Math.min(4000, Number(message.width) || 700)) + 'px';
        container.setAttribute('data-graphite-source-path', sourcePath);
        const element = container.createDiv({ cls: elementClass });
        const component = new Component();
        component.load();
        const entry = {
            blockIdentifier: message.blockIdentifier, container, element, component, addedChildCount: 0,
            observer: null, isCopyScheduled: false, isReleased: false, lastSentHTML: null,
        };
        drawnBlocks.set(message.blockIdentifier, entry);
        const cache = runtime.app.metadataCache.getCache(sourcePath);
        entry.section = sectionInformation(message);
        entry.context = {
            docId: 'graphite-' + message.blockIdentifier,
            sourcePath,
            frontmatter: cache && cache.frontmatter ? cache.frontmatter : null,
            el: element,
            addChild(child) { entry.addedChildCount += 1; component.addChild(child); },
            getSectionInfo() { return entry.section; },
        };
        return entry;
    }

    /// Changes are watched from the start, so what an asynchronous plugin draws after the
    /// answer reaches Graphite too.
    function watch(entry) {
        entry.observer = new globalScope.MutationObserver(() => scheduleCopy(entry));
        entry.observer.observe(entry.container, { subtree: true, childList: true, attributes: true, characterData: true });
        entry.container.addEventListener('change', () => scheduleCopy(entry), true);
        entry.container.addEventListener('input', () => scheduleCopy(entry), true);
    }

    async function runPostProcessors(entry) {
        const ordered = runtime.markdownPostProcessors.slice().sort((firstProcessor, secondProcessor) => firstProcessor.sortOrder - secondProcessor.sortOrder);
        for (const registeredProcessor of ordered) {
            if (entry.isReleased) return;
            try {
                await waitAtMost(Promise.resolve(registeredProcessor.postProcessor(entry.element, entry.context)), processorWaitMilliseconds);
            } catch (error) {
                console.error(error);
                hostBridge.notify('plugin.failure', { pluginIdentifier: registeredProcessor.pluginIdentifier, message: 'Changing a note\'s reading view failed: ' + (error && error.message ? error.message : String(error)) });
            }
        }
    }

    async function draw(message) {
        const app = runtime.app;
        release(message.blockIdentifier);
        const registered = runtime.codeBlockProcessors.get(message.language);
        if (!app || !registered) return { isDrawn: false, message: 'No plugin draws “' + message.language + '” code blocks now.' };
        const entry = startEntry(message, 'block-language-' + message.language);
        watch(entry);
        try {
            await waitAtMost(Promise.resolve(registered.handler(String(message.source || ''), entry.element, entry.context)), processorWaitMilliseconds);
        } catch (error) {
            console.error(error);
            hostBridge.notify('plugin.failure', { pluginIdentifier: registered.pluginIdentifier, message: 'A “' + message.language + '” block failed: ' + (error && error.message ? error.message : String(error)) });
            entry.element.createEl('pre', { cls: 'graphite-plugin-error', text: String(error && error.message ? error.message : error) });
        }
        if (entry.isReleased) return { isDrawn: false, message: 'The block was closed while it was drawn.' };
        // Obsidian runs the other post-processors over a section after its code block.
        await runPostProcessors(entry);
        if (entry.isReleased) return { isDrawn: false, message: 'The block was closed while it was drawn.' };
        entry.lastSentHTML = copyOf(entry);
        return { isDrawn: true, html: entry.lastSentHTML, styles: pluginStyles() };
    }

    const taskLinePattern = /^\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+\[(.)\]/;

    /// Numbers the section's own task checkboxes with their line in the section, so a tap
    /// on one ticks the task in the note, as Obsidian's reading view does. Checkboxes a
    /// plugin draws later are the plugin's own.
    function markTaskCheckboxes(element, markdown) {
        const taskLines = String(markdown).split('\n').map((line, lineIndex) => (taskLinePattern.test(line) ? lineIndex : -1)).filter((lineIndex) => lineIndex >= 0);
        const checkboxes = Array.from(element.querySelectorAll('li > input[type="checkbox"]'));
        if (checkboxes.length !== taskLines.length) return;
        checkboxes.forEach((checkbox, position) => {
            checkbox.removeAttribute('disabled');
            checkbox.setAttribute('data-graphite-task-line', String(taskLines[position]));
        });
    }

    /// What a reader sees of a section: its text, and the elements that show more than text.
    function visibleSignature(element) {
        return element.textContent + '\u0000' + element.querySelectorAll('img, svg, canvas, button, input, select, textarea, iframe, video, audio, table').length;
    }

    /// A part of a note, offered to the plugins' post-processors as Obsidian offers each
    /// section of its reading view. Graphite keeps showing its own rendering unless a plugin
    /// changed what the section shows (its text or its pictures and controls) or attached
    /// something that keeps it up to date (Dataview's inline queries); only then is the
    /// plugin's version kept, alive, and copied into the note like a code block.
    async function drawSection(message) {
        const app = runtime.app;
        release(message.blockIdentifier);
        if (!app || runtime.markdownPostProcessors.length === 0) return { isDrawn: true, isChanged: false };
        const entry = startEntry(message, 'el-section');
        const response = await hostBridge.send('markdown.render', { markdown: String(message.source || ''), sourcePath: message.sourcePath || '' });
        if (entry.isReleased) return { isDrawn: false, message: 'The section was closed while it was drawn.' };
        entry.element.appendChild(exportedApi.sanitizeHTMLToDom(response.html || ''));
        runtime.convertInternalLinks(app, entry.element, message.sourcePath || '');
        markTaskCheckboxes(entry.element, message.source || '');
        const signatureBefore = visibleSignature(entry.element);
        watch(entry);
        await runPostProcessors(entry);
        if (entry.isReleased) return { isDrawn: false, message: 'The section was closed while it was drawn.' };
        if (entry.addedChildCount === 0 && visibleSignature(followReplacement(entry)) === signatureBefore) {
            release(message.blockIdentifier);
            return { isDrawn: true, isChanged: false };
        }
        entry.lastSentHTML = copyOf(entry);
        return { isDrawn: true, isChanged: true, html: entry.lastSentHTML, styles: pluginStyles() };
    }

    /// Element children, by position, from the block's element down to the one tapped.
    function elementAtPath(entry, elementPath) {
        let element = followReplacement(entry);
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

    /// A key pressed in a field of the copy (Return, Escape, arrows), which plugins' search
    /// fields and lists act on.
    function press(element, key) {
        const options = { key: String(key), bubbles: true, cancelable: true };
        element.dispatchEvent(new globalScope.KeyboardEvent('keydown', options));
        element.dispatchEvent(new globalScope.KeyboardEvent('keyup', options));
    }

    /// Text typed into a field of the copy, given to the plugin's field as typing would.
    function enter(element, value) {
        if (!('value' in element)) return;
        element.value = String(value);
        element.dispatchEvent(new globalScope.Event('input', { bubbles: true }));
        element.dispatchEvent(new globalScope.Event('change', { bubbles: true }));
    }

    // MARK: Plugin views

    /// A plugin's view shown in a Graphite tab or sidebar panel: its leaf's element is laid
    /// out here at the size Graphite gives it, and copied like a code block while shown.
    function attachView(message) {
        const app = runtime.app;
        release(message.blockIdentifier);
        const leaf = app ? app.workspace.getLeafById(message.leafIdentifier) : null;
        if (!leaf || leaf === app.workspace.markdownLeaf) return { isDrawn: false, message: 'This view was closed.' };
        for (const entry of drawnBlocks.values()) { if (entry.leaf === leaf) release(entry.blockIdentifier); }
        const container = readingArea().createDiv({ cls: 'graphite-reading-block graphite-plugin-view' });
        container.appendChild(leaf.containerEl);
        if (leaf.waitingPlace) { leaf.waitingPlace.remove(); leaf.waitingPlace = null; }
        const entry = {
            blockIdentifier: message.blockIdentifier, container, element: leaf.containerEl, leaf, component: null, addedChildCount: 0,
            observer: null, isCopyScheduled: false, isReleased: false, lastSentHTML: null,
        };
        drawnBlocks.set(message.blockIdentifier, entry);
        resizeView(entry, message.width, message.height);
        watch(entry);
        entry.lastSentHTML = copyOf(entry);
        return { isDrawn: true, html: entry.lastSentHTML, styles: pluginStyles(), title: leaf.getDisplayText() };
    }

    /// The size Graphite last gave a tab's view and a sidebar panel's view.
    const lastViewSizes = { tab: { width: 700, height: 600 }, sidebar: { width: 320, height: 600 } };
    function placementOfLeaf(leaf) { return leaf.kind === 'left' || leaf.kind === 'right' ? 'sidebar' : 'tab'; }

    function resizeView(entry, width, height) {
        const size = { width: Math.max(200, Math.min(4000, Number(width) || 700)), height: Math.max(100, Math.min(4000, Number(height) || 600)) };
        lastViewSizes[placementOfLeaf(entry.leaf)] = size;
        entry.container.style.width = size.width + 'px';
        entry.container.style.height = size.height + 'px';
        try { entry.leaf.onResize(); } catch (error) { console.error(error); }
        scheduleWorkspaceResize();
    }

    /// Obsidian's workspace says `resize` whenever its panes change size; plugins redraw on it
    /// (Mind Map draws its map then). Sizes that arrive together are one resize.
    let isWorkspaceResizeScheduled = false;
    function scheduleWorkspaceResize() {
        if (isWorkspaceResizeScheduled || !runtime.app) return;
        isWorkspaceResizeScheduled = true;
        globalScope.setTimeout(() => {
            isWorkspaceResizeScheduled = false;
            try { runtime.app.workspace.trigger('resize'); } catch (error) { console.error(error); }
        }, 50);
    }

    /// A new leaf waits in the page, at the size its tab or panel last had, until Graphite
    /// shows it: plugins measure their view as it opens (Mind Map fits its map to it), and
    /// an element outside the page measures nothing.
    runtime.placeNewLeaf = function placeNewLeaf(leaf) {
        const size = lastViewSizes[placementOfLeaf(leaf)];
        const place = readingArea().createDiv({ cls: 'graphite-reading-block graphite-plugin-view' });
        place.style.width = size.width + 'px';
        place.style.height = size.height + 'px';
        place.appendChild(leaf.containerEl);
        leaf.waitingPlace = place;
    };

    // MARK: Live views

    /// The view shown live: Graphite shows this page itself in the view's tab, and the leaf
    /// fills the page, so the plugin gets touches, Pencil, typing and gestures as in Obsidian
    /// (Excalidraw draws). One view at a time; the others stay copies.
    let liveLeaf = null;
    let liveContainer = null;

    function showLive(leafIdentifier) {
        const app = runtime.app;
        const leaf = app ? app.workspace.getLeafById(leafIdentifier) : null;
        if (!leaf || leaf === app.workspace.markdownLeaf) return { isShown: false };
        if (liveLeaf === leaf) return { isShown: true };
        hideLive();
        // A copy of the same leaf would show nothing while it is live.
        for (const entry of Array.from(drawnBlocks.values())) { if (entry.leaf === leaf) release(entry.blockIdentifier); }
        if (leaf.waitingPlace) { leaf.waitingPlace.remove(); leaf.waitingPlace = null; }
        const document = globalScope.document;
        liveContainer = document.body.createDiv({ cls: 'graphite-live-view' });
        liveContainer.appendChild(leaf.containerEl);
        document.body.addClass('graphite-live');
        liveLeaf = leaf;
        try { leaf.onResize(); } catch (error) { console.error(error); }
        scheduleWorkspaceResize();
        return { isShown: true };
    }

    function hideLive(leafIdentifier) {
        if (!liveLeaf || (leafIdentifier && liveLeaf.id !== leafIdentifier)) return;
        const leaf = liveLeaf;
        liveLeaf = null;
        // Back to a place in the page at its last size, where a copy or the next live showing
        // finds it; a leaf that was closed meanwhile is simply let go.
        if (runtime.app && runtime.app.workspace.pluginLeaves.includes(leaf) && runtime.placeNewLeaf) runtime.placeNewLeaf(leaf);
        else leaf.containerEl.detach();
        if (liveContainer) liveContainer.remove();
        liveContainer = null;
        globalScope.document.body.removeClass('graphite-live');
    }

    globalScope.addEventListener('resize', () => {
        if (!liveLeaf) return;
        try { liveLeaf.onResize(); } catch (error) { console.error(error); }
        scheduleWorkspaceResize();
    });

    Object.assign(runtime.messageHandlers, {
        /// Every view of a file saves what it holds (`FileView.save`, which text views and
        /// Excalidraw implement), each for at most three seconds.
        async 'views.saveFiles'() {
            const app = runtime.app;
            if (!app) return {};
            const savingViews = app.workspace.pluginLeaves.map((leaf) => leaf.view).filter((view) => view instanceof exportedApi.FileView && view.file && typeof view.save === 'function');
            await Promise.all(savingViews.map((view) => waitAtMost(Promise.resolve().then(() => view.save()).catch((error) => console.error(error)), 3000)));
            return { savedCount: savingViews.length };
        },
        async 'view.live'(message) {
            return showLive(message.leafIdentifier);
        },
        async 'view.unlive'(message) {
            hideLive(message.leafIdentifier || null);
            return {};
        },
        async 'view.attach'(message) {
            return attachView(message);
        },
        async 'view.resize'(message) {
            const entry = drawnBlocks.get(message.blockIdentifier);
            if (entry && entry.leaf) resizeView(entry, message.width, message.height);
            return {};
        },
        /// The person closed the view's tab or panel: the view closes, as in Obsidian.
        async 'view.close'(message) {
            const leaf = runtime.app ? runtime.app.workspace.getLeafById(message.leafIdentifier) : null;
            if (leaf && leaf !== runtime.app.workspace.markdownLeaf) leaf.detach();
            return {};
        },
        async 'codeBlock.render'(message) {
            return message.kind === 'section' ? drawSection(message) : draw(message);
        },
        async 'codeBlock.event'(message) {
            const entry = drawnBlocks.get(message.blockIdentifier);
            if (!entry) return { isHandled: false };
            // A Live Preview block may have moved since it was drawn: Graphite says where it is now.
            if (message.sectionIsCurrent) entry.section = sectionInformation(message);
            const eventType = message.eventType || 'tap';
            if (eventType === 'hover') {
                const element = message.elementPath ? elementAtPath(entry, message.elementPath) : null;
                const linkHover = linkHoveredDuring(entry, () => hover(entry, element, message));
                return linkHover ? { isHandled: true, linkHover } : { isHandled: true };
            }
            if (eventType === 'gesture') {
                gesture(entry, message);
                // Moves change the block as they go; its copy follows as other changes do.
                if (message.phase === 'move' || message.phase === 'down') return { isHandled: true };
            }
            const element = eventType === 'gesture' ? followReplacement(entry) : elementAtPath(entry, message.elementPath);
            if (!element) return { isHandled: false };
            // A task of the note itself is ticked by Graphite, in the note.
            if ((eventType === 'tap' || eventType === 'key') && element.matches('input[data-graphite-task-line]')) {
                return { isHandled: true, taskLine: Number(element.getAttribute('data-graphite-task-line')) };
            }
            if (eventType === 'input') enter(element, message.value);
            else if (eventType === 'key') press(element, message.key);
            else if (eventType === 'contextmenu') openContextMenu(entry, element, message);
            else if (eventType === 'tap') tap(element);
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
    /// web links the browser. Without this a link (an anchor or an image map's area) in a
    /// plugin's view or block would load in place of the runtime's page and end every plugin.
    function followLink(event) {
        if (event.defaultPrevented || event.button > 0) return;
        const target = event.target;
        const link = target && typeof target.closest === 'function' ? target.closest('a, area') : null;
        if (!link) return;
        const destination = link.getAttribute('data-href') || link.getAttribute('href') || '';
        event.preventDefault();
        if (destination === '' || destination.startsWith('#') || /^javascript:/i.test(destination)) return;
        if (/^(https?|mailto):/i.test(destination)) {
            hostBridge.notify('workspace.openExternalLink', { address: destination });
            return;
        }
        if (/^[a-z][a-z0-9+.-]*:/i.test(destination) && !link.classList.contains('internal-link')) return;
        const app = runtime.app;
        if (!app) return;
        const sourceElement = link.closest('[data-graphite-source-path]');
        const sourcePath = sourceElement ? sourceElement.getAttribute('data-graphite-source-path') : (app.workspace.getActiveFile() ? app.workspace.getActiveFile().path : '');
        let linktext = destination;
        try { linktext = decodeURI(destination); } catch (error) { linktext = destination; }
        app.workspace.openLinkText(linktext, sourcePath, exportedApi.Keymap.isModEvent(event)).catch((error) => console.error(error));
    }
    globalScope.document.addEventListener('click', followLink);
})(globalThis);

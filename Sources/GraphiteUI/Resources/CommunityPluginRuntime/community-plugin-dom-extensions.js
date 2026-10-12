// The helpers Obsidian adds to the DOM and to built-in prototypes before any plugin
// loads (`declare global` in obsidian.d.ts). Plugins call them without importing them,
// so they have to exist on the page exactly as Obsidian names them.
(function installObsidianDomExtensions(globalScope) {
    'use strict';

    function defineMissing(target, name, implementation) {
        if (!target || Object.prototype.hasOwnProperty.call(target, name)) return;
        Object.defineProperty(target, name, { value: implementation, configurable: true, writable: true, enumerable: false });
    }

    function defineGetter(target, name, getter) {
        if (!target || Object.prototype.hasOwnProperty.call(target, name)) return;
        Object.defineProperty(target, name, { get: getter, configurable: true, enumerable: false });
    }

    // Object, Array, Math, String and Number additions.
    defineMissing(Object, 'isEmpty', function isEmpty(object) {
        for (const key in object) { if (Object.prototype.hasOwnProperty.call(object, key)) return false; }
        return true;
    });
    defineMissing(Object, 'each', function each(object, callback, context) {
        for (const key in object) {
            if (Object.prototype.hasOwnProperty.call(object, key) && callback.call(context, object[key], key) === false) return false;
        }
        return true;
    });
    defineMissing(Array, 'combine', function combine(arrays) {
        return [].concat(...arrays);
    });
    defineMissing(Array.prototype, 'first', function first() { return this.length > 0 ? this[0] : undefined; });
    defineMissing(Array.prototype, 'last', function last() { return this.length > 0 ? this[this.length - 1] : undefined; });
    defineMissing(Array.prototype, 'contains', function contains(target) { return this.indexOf(target) !== -1; });
    defineMissing(Array.prototype, 'remove', function remove(target) {
        for (let position = this.length - 1; position >= 0; position -= 1) {
            if (this[position] === target) this.splice(position, 1);
        }
    });
    defineMissing(Array.prototype, 'shuffle', function shuffle() {
        for (let position = this.length - 1; position > 0; position -= 1) {
            const swapPosition = Math.floor(Math.random() * (position + 1));
            const held = this[position];
            this[position] = this[swapPosition];
            this[swapPosition] = held;
        }
        return this;
    });
    defineMissing(Array.prototype, 'unique', function unique() { return Array.from(new Set(this)); });
    defineMissing(Array.prototype, 'findLastIndex', function findLastIndex(predicate) {
        for (let position = this.length - 1; position >= 0; position -= 1) {
            if (predicate(this[position], position, this)) return position;
        }
        return -1;
    });
    defineMissing(Math, 'clamp', function clamp(value, minimum, maximum) { return Math.min(Math.max(value, minimum), maximum); });
    defineMissing(Math, 'square', function square(value) { return value * value; });
    defineMissing(String, 'isString', function isString(candidate) { return typeof candidate === 'string' || candidate instanceof String; });
    defineMissing(String.prototype, 'contains', function contains(target) { return this.indexOf(target) !== -1; });
    defineMissing(String.prototype, 'format', function format(...replacements) {
        return this.replace(/{(\d+)}/g, (placeholder, argumentPosition) => {
            const replacement = replacements[Number(argumentPosition)];
            return replacement === undefined ? placeholder : replacement;
        });
    });
    defineMissing(Number, 'isNumber', function isNumber(candidate) { return typeof candidate === 'number'; });
    defineMissing(globalScope, 'isBoolean', function isBoolean(candidate) { return candidate === true || candidate === false; });

    const NodeType = globalScope.Node;
    const ElementType = globalScope.Element;
    const HTMLElementType = globalScope.HTMLElement;
    const SVGElementType = globalScope.SVGElement;
    const DocumentFragmentType = globalScope.DocumentFragment;
    const DocumentType = globalScope.Document;
    if (!NodeType || !ElementType) return;

    function applyElementInformation(element, information) {
        if (typeof information === 'string') {
            element.className = information;
            return;
        }
        if (!information) return;
        if (information.cls !== undefined) {
            const classNames = Array.isArray(information.cls) ? information.cls : String(information.cls).split(' ');
            element.addClass(...classNames.filter((className) => className.length > 0));
        }
        if (information.text !== undefined) element.setText(information.text);
        if (information.attr) {
            for (const attributeName of Object.keys(information.attr)) element.setAttr(attributeName, information.attr[attributeName]);
        }
        if (information.title !== undefined) element.title = information.title;
        if (information.value !== undefined && 'value' in element) element.value = information.value;
        if (information.type !== undefined) element.setAttribute('type', information.type);
        if (information.placeholder !== undefined) element.setAttribute('placeholder', information.placeholder);
        if (information.href !== undefined) element.setAttribute('href', information.href);
        if (information.parent) {
            if (information.prepend) information.parent.insertBefore(element, information.parent.firstChild);
            else information.parent.appendChild(element);
        }
    }

    function createElementIn(parent, tagName, information, callback) {
        const ownerDocument = parent && parent.nodeType === NodeType.DOCUMENT_NODE ? parent : (parent && parent.ownerDocument) || globalScope.document;
        const element = ownerDocument.createElement(tagName);
        applyElementInformation(element, information);
        if (parent && parent.nodeType !== NodeType.DOCUMENT_NODE && !(information && typeof information === 'object' && information.parent)) {
            if (information && typeof information === 'object' && information.prepend) parent.insertBefore(element, parent.firstChild);
            else parent.appendChild(element);
        }
        if (callback) callback(element);
        return element;
    }

    function createSvgElementIn(parent, tagName, information, callback) {
        const ownerDocument = (parent && parent.ownerDocument) || globalScope.document;
        const element = ownerDocument.createElementNS('http://www.w3.org/2000/svg', tagName);
        if (typeof information === 'string') element.setAttribute('class', information);
        else if (information) {
            if (information.cls !== undefined) {
                const classNames = Array.isArray(information.cls) ? information.cls : String(information.cls).split(' ');
                for (const className of classNames) { if (className) element.classList.add(className); }
            }
            if (information.attr) {
                for (const attributeName of Object.keys(information.attr)) {
                    const attributeValue = information.attr[attributeName];
                    if (attributeValue === null || attributeValue === undefined) element.removeAttribute(attributeName);
                    else element.setAttribute(attributeName, String(attributeValue));
                }
            }
            if (information.parent) {
                if (information.prepend) information.parent.insertBefore(element, information.parent.firstChild);
                else information.parent.appendChild(element);
            }
        }
        if (parent && !(information && typeof information === 'object' && information.parent)) {
            if (information && typeof information === 'object' && information.prepend) parent.insertBefore(element, parent.firstChild);
            else parent.appendChild(element);
        }
        if (callback) callback(element);
        return element;
    }

    // Node additions.
    const nodePrototype = NodeType.prototype;
    defineMissing(nodePrototype, 'detach', function detach() { if (this.parentNode) this.parentNode.removeChild(this); });
    defineMissing(nodePrototype, 'empty', function empty() { while (this.lastChild) this.removeChild(this.lastChild); });
    defineMissing(nodePrototype, 'insertAfter', function insertAfter(node, child) {
        this.insertBefore(node, child ? child.nextSibling : this.firstChild);
        return node;
    });
    defineMissing(nodePrototype, 'indexOf', function indexOf(other) { return Array.prototype.indexOf.call(this.childNodes, other); });
    defineMissing(nodePrototype, 'setChildrenInPlace', function setChildrenInPlace(children) {
        const wanted = new Set(children);
        for (const existingChild of Array.from(this.childNodes)) { if (!wanted.has(existingChild)) this.removeChild(existingChild); }
        let reference = this.firstChild;
        for (const child of children) {
            if (child === reference) reference = reference.nextSibling;
            else this.insertBefore(child, reference);
        }
    });
    defineMissing(nodePrototype, 'appendText', function appendText(text) { this.appendChild((this.ownerDocument || globalScope.document).createTextNode(text)); });
    defineMissing(nodePrototype, 'instanceOf', function instanceOf(type) { return this instanceof type; });
    defineGetter(nodePrototype, 'doc', function documentOfNode() { return this.ownerDocument || this; });
    defineGetter(nodePrototype, 'win', function windowOfNode() { return (this.ownerDocument || this).defaultView || globalScope; });
    defineGetter(nodePrototype, 'constructorWin', function constructorWindowOfNode() { return globalScope; });
    defineMissing(nodePrototype, 'createEl', function createEl(tagName, information, callback) { return createElementIn(this, tagName, information, callback); });
    defineMissing(nodePrototype, 'createDiv', function createDiv(information, callback) { return createElementIn(this, 'div', information, callback); });
    defineMissing(nodePrototype, 'createSpan', function createSpan(information, callback) { return createElementIn(this, 'span', information, callback); });
    defineMissing(nodePrototype, 'createSvg', function createSvg(tagName, information, callback) { return createSvgElementIn(this, tagName, information, callback); });

    // Element additions.
    const elementPrototype = ElementType.prototype;
    defineMissing(elementPrototype, 'getText', function getText() { return this.textContent || ''; });
    defineMissing(elementPrototype, 'setText', function setText(text) {
        if (DocumentFragmentType && text instanceof DocumentFragmentType) {
            this.empty();
            this.appendChild(text);
        } else {
            this.textContent = text === undefined || text === null ? '' : String(text);
        }
    });
    defineMissing(elementPrototype, 'addClass', function addClass(...classNames) {
        for (const className of classNames) { if (className) this.classList.add(...String(className).split(' ').filter(Boolean)); }
    });
    defineMissing(elementPrototype, 'addClasses', function addClasses(classNames) { this.addClass(...classNames); });
    defineMissing(elementPrototype, 'removeClass', function removeClass(...classNames) {
        for (const className of classNames) { if (className) this.classList.remove(...String(className).split(' ').filter(Boolean)); }
    });
    defineMissing(elementPrototype, 'removeClasses', function removeClasses(classNames) { this.removeClass(...classNames); });
    defineMissing(elementPrototype, 'toggleClass', function toggleClass(classNames, isPresent) {
        for (const className of Array.isArray(classNames) ? classNames : [classNames]) {
            if (className) this.classList.toggle(className, Boolean(isPresent));
        }
    });
    defineMissing(elementPrototype, 'hasClass', function hasClass(className) { return this.classList.contains(className); });
    defineMissing(elementPrototype, 'setAttr', function setAttr(attributeName, attributeValue) {
        if (attributeValue === null || attributeValue === undefined || attributeValue === false) this.removeAttribute(attributeName);
        else this.setAttribute(attributeName, attributeValue === true ? '' : String(attributeValue));
    });
    defineMissing(elementPrototype, 'setAttrs', function setAttrs(attributes) {
        for (const attributeName of Object.keys(attributes)) this.setAttr(attributeName, attributes[attributeName]);
    });
    defineMissing(elementPrototype, 'getAttr', function getAttr(attributeName) { return this.getAttribute(attributeName); });
    defineMissing(elementPrototype, 'matchParent', function matchParent(selector, lastParent) {
        let candidate = this;
        while (candidate && candidate !== lastParent) {
            if (candidate.matches && candidate.matches(selector)) return candidate;
            candidate = candidate.parentElement;
        }
        return null;
    });
    defineMissing(elementPrototype, 'getCssPropertyValue', function getCssPropertyValue(propertyName, pseudoElement) {
        return globalScope.getComputedStyle(this, pseudoElement).getPropertyValue(propertyName);
    });
    defineMissing(elementPrototype, 'isActiveElement', function isActiveElement() { return (this.ownerDocument || globalScope.document).activeElement === this; });
    defineMissing(elementPrototype, 'find', function find(selector) { return this.querySelector(selector); });
    defineMissing(elementPrototype, 'findAll', function findAll(selector) { return Array.from(this.querySelectorAll(selector)); });
    defineMissing(elementPrototype, 'findAllSelf', function findAllSelf(selector) {
        const matches = Array.from(this.querySelectorAll(selector));
        if (this.matches(selector)) matches.unshift(this);
        return matches;
    });

    function setStyles(element, styles) {
        for (const styleName of Object.keys(styles)) element.style[styleName] = styles[styleName];
    }
    function setCustomProperties(element, properties) {
        for (const propertyName of Object.keys(properties)) element.style.setProperty(propertyName, properties[propertyName]);
    }

    if (HTMLElementType) {
        const htmlElementPrototype = HTMLElementType.prototype;
        defineMissing(htmlElementPrototype, 'show', function show() { this.style.display = ''; });
        defineMissing(htmlElementPrototype, 'hide', function hide() { this.style.display = 'none'; });
        defineMissing(htmlElementPrototype, 'toggle', function toggle(isShown) { if (isShown) this.show(); else this.hide(); });
        defineMissing(htmlElementPrototype, 'toggleVisibility', function toggleVisibility(isVisible) { this.style.visibility = isVisible ? '' : 'hidden'; });
        defineMissing(htmlElementPrototype, 'isShown', function isShown() { return this.style.display !== 'none' && this.isConnected; });
        defineMissing(htmlElementPrototype, 'setCssStyles', function setCssStyles(styles) { setStyles(this, styles); });
        defineMissing(htmlElementPrototype, 'setCssProps', function setCssProps(properties) { setCustomProperties(this, properties); });
        defineGetter(htmlElementPrototype, 'innerWidth', function innerWidth() {
            const computedStyle = globalScope.getComputedStyle(this);
            return this.clientWidth - (parseFloat(computedStyle.paddingLeft) || 0) - (parseFloat(computedStyle.paddingRight) || 0);
        });
        defineGetter(htmlElementPrototype, 'innerHeight', function innerHeight() {
            const computedStyle = globalScope.getComputedStyle(this);
            return this.clientHeight - (parseFloat(computedStyle.paddingTop) || 0) - (parseFloat(computedStyle.paddingBottom) || 0);
        });
        defineMissing(htmlElementPrototype, 'onClickEvent', function onClickEvent(listener, options) {
            this.addEventListener('click', listener, options);
            this.addEventListener('auxclick', listener, options);
        });
        defineMissing(htmlElementPrototype, 'onNodeInserted', function onNodeInserted(listener, isOnce) {
            const element = this;
            let isListening = true;
            const observer = new globalScope.MutationObserver(() => {
                if (!isListening || !element.isConnected) return;
                listener();
                if (isOnce) stopObserving();
            });
            function stopObserving() { isListening = false; observer.disconnect(); }
            observer.observe((element.ownerDocument || globalScope.document).documentElement, { childList: true, subtree: true });
            if (element.isConnected) { listener(); if (isOnce) stopObserving(); }
            return stopObserving;
        });
        defineMissing(htmlElementPrototype, 'onWindowMigrated', function onWindowMigrated() {
            // Graphite shows plugin views in one web view, so an element never moves to another window.
            return function stopListening() {};
        });
        defineMissing(htmlElementPrototype, 'trigger', function trigger(eventType) {
            this.dispatchEvent(new globalScope.Event(eventType, { bubbles: true, cancelable: true }));
        });
    }
    if (SVGElementType) {
        defineMissing(SVGElementType.prototype, 'setCssStyles', function setCssStyles(styles) { setStyles(this, styles); });
        defineMissing(SVGElementType.prototype, 'setCssProps', function setCssProps(properties) { setCustomProperties(this, properties); });
    }
    if (DocumentFragmentType) {
        defineMissing(DocumentFragmentType.prototype, 'find', function find(selector) { return this.querySelector(selector); });
        defineMissing(DocumentFragmentType.prototype, 'findAll', function findAll(selector) { return Array.from(this.querySelectorAll(selector)); });
    }

    // Delegated listeners: `element.on('click', '.item', listener)`.
    function addDelegatedListener(eventType, selector, listener, options) {
        const target = this;
        const registry = target.delegatedEventListeners || (target.delegatedEventListeners = {});
        const listeners = registry[eventType] || (registry[eventType] = []);
        if (listeners.some((registered) => registered.selector === selector && registered.listener === listener)) return;
        const callback = function handleDelegatedEvent(event) {
            const eventTarget = event.target;
            if (!eventTarget || !eventTarget.matchParent) return;
            const delegateTarget = eventTarget.matchParent(selector, target === target.doc ? undefined : target);
            if (delegateTarget) listener.call(target, event, delegateTarget);
        };
        listeners.push({ selector, listener, options, callback });
        target.addEventListener(eventType, callback, options);
    }
    function removeDelegatedListener(eventType, selector, listener, options) {
        const registry = this.delegatedEventListeners;
        if (!registry || !registry[eventType]) return;
        const listeners = registry[eventType];
        for (let position = listeners.length - 1; position >= 0; position -= 1) {
            const registered = listeners[position];
            if (registered.selector === selector && registered.listener === listener) {
                this.removeEventListener(eventType, registered.callback, options);
                listeners.splice(position, 1);
            }
        }
    }
    if (HTMLElementType) {
        defineMissing(HTMLElementType.prototype, 'on', addDelegatedListener);
        defineMissing(HTMLElementType.prototype, 'off', removeDelegatedListener);
    }
    if (DocumentType) {
        defineMissing(DocumentType.prototype, 'on', addDelegatedListener);
        defineMissing(DocumentType.prototype, 'off', removeDelegatedListener);
    }

    if (globalScope.UIEvent) {
        defineGetter(globalScope.UIEvent.prototype, 'targetNode', function targetNode() { return this.target instanceof NodeType ? this.target : null; });
        defineGetter(globalScope.UIEvent.prototype, 'win', function windowOfEvent() { return this.view || globalScope; });
        defineGetter(globalScope.UIEvent.prototype, 'doc', function documentOfEvent() { return (this.view || globalScope).document; });
        defineMissing(globalScope.UIEvent.prototype, 'instanceOf', function instanceOf(type) { return this instanceof type; });
    }

    // Global functions.
    defineMissing(globalScope, 'createEl', function createEl(tagName, information, callback) { return createElementIn(null, tagName, information, callback); });
    defineMissing(globalScope, 'createDiv', function createDiv(information, callback) { return createElementIn(null, 'div', information, callback); });
    defineMissing(globalScope, 'createSpan', function createSpan(information, callback) { return createElementIn(null, 'span', information, callback); });
    defineMissing(globalScope, 'createSvg', function createSvg(tagName, information, callback) { return createSvgElementIn(null, tagName, information, callback); });
    defineMissing(globalScope, 'createFragment', function createFragment(callback) {
        const fragment = globalScope.document.createDocumentFragment();
        if (callback) callback(fragment);
        return fragment;
    });
    defineMissing(globalScope, 'fish', function fish(selector) { return globalScope.document.querySelector(selector); });
    defineMissing(globalScope, 'fishAll', function fishAll(selector) { return Array.from(globalScope.document.querySelectorAll(selector)); });
    defineMissing(globalScope, 'sleep', function sleep(milliseconds) { return new Promise((resolve) => globalScope.setTimeout(resolve, milliseconds)); });
    // WebKit draws no frames for a web view that is not on screen, which the plugin panel
    // usually is not, so a frame that does not come within 50 ms is not waited for.
    defineMissing(globalScope, 'nextFrame', function nextFrame() {
        return new Promise((resolve) => {
            let isResolved = false;
            const finish = () => { if (!isResolved) { isResolved = true; resolve(); } };
            if (globalScope.requestAnimationFrame) globalScope.requestAnimationFrame(finish);
            globalScope.setTimeout(finish, 50);
        });
    });
    defineMissing(globalScope, 'ready', function ready(callback) {
        if (globalScope.document.readyState !== 'loading') callback();
        else globalScope.document.addEventListener('DOMContentLoaded', () => callback(), { once: true });
    });
    defineMissing(globalScope, 'ajax', function ajax(options) {
        const request = options.req || new globalScope.XMLHttpRequest();
        request.open(options.method || 'GET', options.url, true);
        if (options.withCredentials) request.withCredentials = true;
        for (const headerName of Object.keys(options.headers || {})) request.setRequestHeader(headerName, options.headers[headerName]);
        request.onload = () => {
            if (request.status >= 200 && request.status < 300) { if (options.success) options.success(request.response, request); }
            else if (options.error) options.error(request.statusText, request);
        };
        request.onerror = (error) => { if (options.error) options.error(error, request); };
        const body = options.data;
        request.send(body === undefined ? null : (typeof body === 'object' && !(body instanceof ArrayBuffer) ? JSON.stringify(body) : body));
    });
    defineMissing(globalScope, 'ajaxPromise', function ajaxPromise(options) {
        return new Promise((resolve, reject) => {
            globalScope.ajax(Object.assign({}, options, { success: resolve, error: reject }));
        });
    });
    if (!('activeWindow' in globalScope)) globalScope.activeWindow = globalScope;
    if (!('activeDocument' in globalScope)) globalScope.activeDocument = globalScope.document;
})(globalThis);

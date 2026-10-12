// Measures what the vault's theme and snippets make of Obsidian's note elements, in light
// and dark, by reading WebKit's computed styles of probe elements laid out as Obsidian's
// reading view lays them out. WebKit resolves `var()` chains, `calc()`, `color-mix()` and
// the theme's own selectors; Graphite only reads the results.
(function installThemeProbe(globalScope) {
    'use strict';
    const document = globalScope.document;
    const calloutTypes = ['note', 'abstract', 'summary', 'tldr', 'info', 'todo', 'tip', 'hint', 'important', 'success', 'check', 'done',
        'question', 'help', 'faq', 'warning', 'caution', 'attention', 'failure', 'fail', 'missing', 'danger', 'error', 'bug', 'example',
        'quote', 'cite'];

    function element(tag, className, parent, text) {
        const created = document.createElement(tag);
        if (className) created.className = className;
        if (text) created.textContent = text;
        if (parent) parent.appendChild(created);
        return created;
    }

    function buildProbes() {
        const view = element('div', 'markdown-preview-view markdown-rendered', null);
        view.id = 'graphite-probes';
        const sizer = element('div', 'markdown-preview-sizer markdown-preview-section', view);
        element('div', 'inline-title', sizer, 'Title').id = 'probe-inline-title';
        for (let level = 1; level <= 6; level += 1) element('h' + level, null, sizer, 'Heading').id = 'probe-h' + level;
        const paragraph = element('p', null, sizer, 'Text ');
        paragraph.id = 'probe-p';
        element('strong', null, paragraph, 'bold').id = 'probe-strong';
        element('em', null, paragraph, 'italic').id = 'probe-em';
        const link = element('a', 'internal-link', paragraph, 'link'); link.id = 'probe-link'; link.setAttribute('href', 'Note');
        const unresolved = element('a', 'internal-link is-unresolved', paragraph, 'missing'); unresolved.id = 'probe-unresolved'; unresolved.setAttribute('href', 'Missing');
        const external = element('a', 'external-link', paragraph, 'web'); external.id = 'probe-external'; external.setAttribute('href', 'https://example.com');
        const tag = element('a', 'tag', paragraph, '#tag'); tag.id = 'probe-tag'; tag.setAttribute('href', '#tag');
        element('code', null, paragraph, 'code').id = 'probe-code';
        element('mark', null, paragraph, 'mark').id = 'probe-mark';
        const muted = element('span', null, paragraph, 'muted'); muted.id = 'probe-muted'; muted.style.color = 'var(--text-muted)';
        const faint = element('span', null, paragraph, 'faint'); faint.id = 'probe-faint'; faint.style.color = 'var(--text-faint)';
        const accent = element('span', null, paragraph, 'accent'); accent.id = 'probe-accent'; accent.style.color = 'var(--text-accent)';
        const lineWidth = element('div', null, sizer); lineWidth.id = 'probe-line-width'; lineWidth.style.width = 'var(--file-line-width)';
        const quote = element('blockquote', null, sizer); quote.id = 'probe-blockquote'; element('p', null, quote, 'Quote');
        element('hr', null, sizer).id = 'probe-hr';
        const table = element('table', null, sizer);
        const headerRow = element('tr', null, element('thead', null, table));
        element('th', null, headerRow, 'Header').id = 'probe-th';
        const tableBody = element('tbody', null, table);
        const bodyRow = element('tr', null, tableBody);
        element('td', null, bodyRow, 'Cell').id = 'probe-td';
        const stripedRow = element('tr', null, tableBody); stripedRow.id = 'probe-stripe-row';
        element('td', null, stripedRow, 'Cell').id = 'probe-stripe';
        element('td', null, element('tr', null, tableBody), 'Cell');
        const bullets = element('ul', null, sizer);
        element('li', null, bullets, 'Item').id = 'probe-li';
        const marker = element('span', null, sizer, 'marker'); marker.id = 'probe-checkmark'; marker.style.color = 'var(--checkbox-marker-color, transparent)';
        const pre = element('pre', null, sizer); pre.id = 'probe-pre'; element('code', null, pre, 'let x = 1');
        const list = element('ul', 'contains-task-list', sizer);
        const doneItem = element('li', 'task-list-item is-checked', list); doneItem.setAttribute('data-task', 'x');
        const checked = element('input', 'task-list-item-checkbox', doneItem); checked.type = 'checkbox'; checked.checked = true; checked.setAttribute('checked', ''); checked.id = 'probe-checked';
        const openItem = element('li', 'task-list-item', list); openItem.setAttribute('data-task', ' ');
        const unchecked = element('input', 'task-list-item-checkbox', openItem); unchecked.type = 'checkbox'; unchecked.id = 'probe-unchecked';
        for (const type of calloutTypes) {
            const callout = element('div', 'callout', sizer); callout.setAttribute('data-callout', type);
            if (type === 'note') callout.id = 'probe-callout';
            const title = element('div', 'callout-title', callout); title.id = 'probe-callout-' + type;
            element('div', 'callout-title-inner', title, type);
            element('p', null, element('div', 'callout-content', callout), 'Content');
        }
        document.body.appendChild(view);
    }

    function style(id) { return globalScope.getComputedStyle(document.getElementById(id)); }

    // A corner radius in pixels: a percentage (a round checkbox's 50%) is of the element's width.
    function radiusInPixels(id, corner) {
        const radius = style(id)['border' + corner + 'Radius'];
        if (!radius.endsWith('%')) return radius;
        return (parseFloat(radius) / 100 * document.getElementById(id).getBoundingClientRect().width) + 'px';
    }

    function readValues() {
        const values = {};
        const body = globalScope.getComputedStyle(document.body);
        const view = style('graphite-probes');
        values['body.background'] = body.backgroundColor;
        values['body.color'] = view.color;
        values['body.fontSize'] = view.fontSize;
        values['body.lineHeight'] = view.lineHeight;
        values['body.fontFamily'] = view.fontFamily;
        values['muted.color'] = style('probe-muted').color;
        values['faint.color'] = style('probe-faint').color;
        values['accent.color'] = style('probe-accent').color;
        values['strong.color'] = style('probe-strong').color;
        values['em.color'] = style('probe-em').color;
        for (let level = 1; level <= 6; level += 1) {
            const heading = style('probe-h' + level);
            const before = globalScope.getComputedStyle(document.getElementById('probe-h' + level), '::before');
            values['h' + level + '.borderBottomWidth'] = heading.borderBottomStyle === 'none' ? '0px' : heading.borderBottomWidth;
            values['h' + level + '.borderBottomColor'] = heading.borderBottomColor;
            values['h' + level + '.background'] = heading.backgroundColor;
            values['h' + level + '.beforeContent'] = before.content;
            values['h' + level + '.beforeColor'] = before.color;
            values['h' + level + '.textTransform'] = heading.textTransform;
            values['h' + level + '.color'] = heading.color;
            values['h' + level + '.fontSize'] = heading.fontSize;
            values['h' + level + '.fontWeight'] = heading.fontWeight;
            values['h' + level + '.fontFamily'] = heading.fontFamily;
            values['h' + level + '.fontStyle'] = heading.fontStyle;
        }
        for (const type of calloutTypes) values['callout.' + type] = style('probe-callout-' + type).color;
        const link = style('probe-link');
        values['link.color'] = link.color;
        values['link.textDecorationLine'] = link.textDecorationLine;
        values['unresolvedLink.color'] = style('probe-unresolved').color;
        values['unresolvedLink.opacity'] = style('probe-unresolved').opacity;
        values['externalLink.color'] = style('probe-external').color;
        const tag = style('probe-tag');
        values['tag.color'] = tag.color;
        values['tag.background'] = tag.backgroundColor;
        const checked = style('probe-checked');
        values['checkbox.checkedBackground'] = checked.backgroundColor;
        values['checkbox.borderRadius'] = radiusInPixels('probe-checked', 'TopLeft');
        values['checkbox.borderColor'] = style('probe-unchecked').borderTopColor;
        const code = style('probe-code');
        values['code.background'] = code.backgroundColor;
        values['code.color'] = code.color;
        values['code.fontFamily'] = code.fontFamily;
        const quote = style('probe-blockquote');
        values['blockquote.borderColor'] = quote.borderLeftColor;
        values['blockquote.borderWidth'] = quote.borderLeftWidth;
        values['mark.background'] = style('probe-mark').backgroundColor;
        const rule = style('probe-hr');
        values['hr.borderColor'] = rule.borderTopColor;
        values['hr.borderWidth'] = rule.borderTopWidth;
        values['td.borderColor'] = style('probe-td').borderTopColor;
        values['th.background'] = style('probe-th').backgroundColor;
        values['lineWidth.width'] = style('probe-line-width').width;
        values['blockquote.background'] = quote.backgroundColor;
        values['blockquote.borderRadius'] = radiusInPixels('probe-blockquote', 'TopRight');
        const callout = style('probe-callout');
        values['callout.borderRadius'] = radiusInPixels('probe-callout', 'TopLeft');
        values['callout.borderWidth'] = callout.borderTopStyle === 'none' ? '0px' : callout.borderTopWidth;
        values['callout.background'] = callout.backgroundColor;
        values['th.color'] = style('probe-th').color;
        const stripeRow = style('probe-stripe-row'), stripeCell = style('probe-stripe');
        values['stripe.background'] = stripeCell.backgroundColor !== 'rgba(0, 0, 0, 0)' ? stripeCell.backgroundColor : stripeRow.backgroundColor;
        values['marker.color'] = globalScope.getComputedStyle(document.getElementById('probe-li'), '::marker').color;
        values['tag.borderRadius'] = radiusInPixels('probe-tag', 'TopLeft');
        values['tag.borderWidth'] = tag.borderTopStyle === 'none' ? '0px' : tag.borderTopWidth;
        values['tag.borderColor'] = tag.borderTopColor;
        values['checkbox.borderWidth'] = style('probe-unchecked').borderTopWidth;
        values['checkbox.markerColor'] = style('probe-checkmark').color;
        values['hr.borderStyle'] = rule.borderTopStyle;
        const pre = style('probe-pre');
        values['pre.background'] = pre.backgroundColor;
        values['pre.borderRadius'] = radiusInPixels('probe-pre', 'TopLeft');
        values['pre.borderWidth'] = pre.borderTopStyle === 'none' ? '0px' : pre.borderTopWidth;
        values['pre.borderColor'] = pre.borderTopColor;
        const mark = style('probe-mark');
        values['mark.borderRadius'] = radiusInPixels('probe-mark', 'TopLeft');
        values['mark.color'] = mark.color;
        const title = style('probe-inline-title');
        values['inlineTitle.color'] = title.color;
        values['inlineTitle.fontSize'] = title.fontSize;
        values['inlineTitle.fontWeight'] = title.fontWeight;
        values['inlineTitle.fontFamily'] = title.fontFamily;
        return values;
    }

    function setMode(isDark, extraClasses, bodyStyle, accentStyle, isThemed) {
        const body = document.body;
        body.className = ['theme-' + (isDark ? 'dark' : 'light'), 'is-mobile', 'is-tablet', 'is-ios'].concat(isThemed ? extraClasses : []).join(' ');
        body.setAttribute('style', accentStyle + (isThemed ? bodyStyle : ''));
        const themed = document.getElementById('graphite-themed-styles');
        if (themed && themed.sheet) themed.sheet.disabled = !isThemed;
    }

    /// Values for light and dark, each with the theme and with Graphite's defaults alone.
    globalScope.GraphiteThemeProbe = {
        measure(extraClasses, bodyStyle, accentStyle) {
            if (!document.getElementById('graphite-probes')) buildProbes();
            const classes = String(extraClasses || '').split(' ').filter(Boolean);
            const result = {};
            for (const mode of ['light', 'dark']) {
                setMode(mode === 'dark', classes, bodyStyle || '', accentStyle || '', true);
                const themed = readValues();
                setMode(mode === 'dark', classes, bodyStyle || '', accentStyle || '', false);
                const defaults = readValues();
                result[mode] = { themed, defaults };
            }
            return result;
        },
    };
})(window);

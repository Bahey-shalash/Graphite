// Obsidian's Bases classes for plugins: the values of base formulas and the classes a
// plugin extends to offer its own base view. Graphite's bases are native (`BaseEvaluator`),
// so a plugin's view is not offered among a base's views; registering one is reported as
// unsupported. The classes exist so plugins that define such views at load still load.
(function installRuntimeBases(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Component } = exportedApi;

    // MARK: Values

    class Value {
        static equals(firstValue, secondValue) {
            if (!firstValue || !secondValue) return firstValue === secondValue;
            return firstValue.constructor === secondValue.constructor && firstValue.equals(secondValue);
        }
        static looseEquals(firstValue, secondValue) {
            if (!firstValue || !secondValue) return firstValue === secondValue;
            return firstValue.looseEquals(secondValue);
        }
        toString() { return ''; }
        isTruthy() { return false; }
        equals(other) { return this.toString() === other.toString(); }
        looseEquals(other) { return this.toString() === other.toString(); }
        renderTo(element) { element.setText(this.toString()); }
    }
    Value.type = 'value';

    class NullValue extends Value {
        toString() { return ''; }
        isTruthy() { return false; }
    }
    NullValue.type = 'null';
    NullValue.value = new NullValue();

    class NotNullValue extends Value {}

    class PrimitiveValue extends NotNullValue {
        constructor(value) {
            super();
            this.value = value;
        }
        toString() { return String(this.value); }
        isTruthy() { return Boolean(this.value); }
        equals(other) { return other instanceof PrimitiveValue && other.value === this.value; }
    }

    class StringValue extends PrimitiveValue {}
    StringValue.type = 'string';
    class NumberValue extends PrimitiveValue {}
    NumberValue.type = 'number';
    class BooleanValue extends PrimitiveValue {}
    BooleanValue.type = 'boolean';

    class DateValue extends NotNullValue {
        constructor(date) {
            super();
            this.date = date;
        }
        toString() { return globalScope.moment ? globalScope.moment(this.date).format('YYYY-MM-DD') : this.date.toISOString(); }
        isTruthy() { return true; }
    }
    DateValue.type = 'date';
    class RelativeDateValue extends DateValue {}
    class DurationValue extends NotNullValue {
        constructor(milliseconds) {
            super();
            this.milliseconds = milliseconds;
        }
        toString() { return String(this.milliseconds) + ' ms'; }
        isTruthy() { return this.milliseconds !== 0; }
    }
    DurationValue.type = 'duration';

    class ListValue extends NotNullValue {
        constructor(values) {
            super();
            this.values = (values || []).map((entry) => (entry instanceof Value ? entry : new StringValue(String(entry))));
        }
        toString() { return this.values.map((entry) => entry.toString()).join(', '); }
        isTruthy() { return this.values.length > 0; }
        includes(value) { return this.values.some((entry) => Value.equals(entry, value)); }
        length() { return this.values.length; }
        get(index) { return this.values[index] || NullValue.value; }
        concat(other) { return new ListValue(this.values.concat(other.values)); }
    }
    ListValue.type = 'list';

    class ObjectValue extends NotNullValue {
        constructor(entries) {
            super();
            this.entries = entries || {};
        }
        toString() { return JSON.stringify(this.entries); }
        isTruthy() { return Object.keys(this.entries).length > 0; }
    }
    ObjectValue.type = 'object';

    class FileValue extends NotNullValue {
        constructor(file) {
            super();
            this.file = file;
        }
        toString() { return this.file ? this.file.path : ''; }
        isTruthy() { return Boolean(this.file); }
    }
    FileValue.type = 'file';
    class LinkValue extends StringValue {}
    LinkValue.type = 'link';
    class UrlValue extends StringValue {}
    UrlValue.type = 'url';
    class TagValue extends StringValue {}
    TagValue.type = 'tag';
    class HTMLValue extends StringValue {}
    HTMLValue.type = 'html';
    class IconValue extends StringValue {}
    IconValue.type = 'icon';
    class ImageValue extends StringValue {}
    ImageValue.type = 'image';
    class RegExpValue extends NotNullValue {
        constructor(pattern) {
            super();
            this.pattern = pattern;
        }
        toString() { return String(this.pattern); }
        isTruthy() { return true; }
    }
    RegExpValue.type = 'regexp';

    // MARK: Views

    class RenderContext {
        constructor() { this.hoverPopover = null; }
    }

    class QueryController extends Component {}

    class BasesViewConfig {
        constructor(name) {
            this.name = name || '';
            this.options = {};
        }
        get(key) { return this.options[key]; }
        getAsPropertyId(key) { return typeof this.options[key] === 'string' ? this.options[key] : null; }
        getEvaluatedFormula() { return NullValue.value; }
        set(key, value) { this.options[key] = value; }
        getOrder() { return []; }
        getSort() { return []; }
        getDisplayName(propertyId) { return parsePropertyId(propertyId).name; }
    }

    class BasesEntry {
        constructor(file) { this.file = file; }
        getValue() { return null; }
    }

    class BasesEntryGroup {
        constructor() {
            this.key = null;
            this.entries = [];
        }
        hasKey() { return this.key !== null; }
    }

    class BasesQueryResult {
        constructor() { this.data = []; }
        get groupedData() { return []; }
        get properties() { return []; }
        getSummaryValue() { return NullValue.value; }
    }

    class BasesView extends Component {
        constructor(controller) {
            super();
            this.controller = controller;
            this.app = runtime.app;
            this.config = new BasesViewConfig();
            this.allProperties = [];
            this.data = new BasesQueryResult();
        }
        onDataUpdated() {}
        async createFileForView() {
            runtime.unsupported('BasesView.createFileForView', 'Graphite does not show plugin views in bases yet.');
        }
    }

    /// `note.status` → `{ type: 'note', name: 'status' }`, as Obsidian splits property identifiers.
    function parsePropertyId(propertyId) {
        const text = String(propertyId);
        const dotPosition = text.indexOf('.');
        if (dotPosition === -1) return { type: 'note', name: text };
        return { type: text.slice(0, dotPosition), name: text.slice(dotPosition + 1) };
    }

    Object.assign(exportedApi, {
        Value, NullValue, NotNullValue, PrimitiveValue, StringValue, NumberValue, BooleanValue, DateValue, RelativeDateValue,
        DurationValue, ListValue, ObjectValue, FileValue, LinkValue, UrlValue, TagValue, HTMLValue, IconValue, ImageValue, RegExpValue,
        RenderContext, QueryController, BasesViewConfig, BasesEntry, BasesEntryGroup, BasesQueryResult, BasesView, parsePropertyId,
    });
})(globalThis);

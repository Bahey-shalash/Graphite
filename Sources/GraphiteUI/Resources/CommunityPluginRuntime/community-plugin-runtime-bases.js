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

    /// A plain value from a note's frontmatter as one of Obsidian's Bases values.
    function wrapValue(value) {
        if (value === null || value === undefined) return NullValue.value;
        if (value instanceof Value) return value;
        if (Array.isArray(value)) return new ListValue(value.map(wrapValue));
        if (typeof value === 'number') return new NumberValue(value);
        if (typeof value === 'boolean') return new BooleanValue(value);
        if (value instanceof Date) return new DateValue(value);
        if (typeof value === 'object') return new ObjectValue(Object.entries(value).map(([key, entry]) => [key, wrapValue(entry)]));
        const text = String(value);
        if (/^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?$/.test(text)) {
            const date = new Date(text.length === 10 ? text + 'T00:00:00' : text);
            if (!isNaN(date.getTime())) return new DateValue(date);
        }
        if (/^\[\[[^\]]+\]\]$/.test(text)) return new LinkValue(text);
        return new StringValue(text);
    }

    /// One file of a base's results. Its values come from the vault's metadata cache, as
    /// Obsidian's do: note properties from the frontmatter, file properties from the file;
    /// formulas, which Graphite evaluates natively, are not given to plugins.
    class BasesEntry {
        constructor(file) { this.file = file; }
        getValue(propertyId) {
            const { type, name } = parsePropertyId(propertyId);
            const file = this.file;
            if (!file) return NullValue.value;
            if (type === 'file') {
                const app = runtime.app;
                const cache = app ? app.metadataCache.getFileCache(file) : null;
                switch (name) {
                case 'name': return new StringValue(file.name);
                case 'basename': return new StringValue(file.basename);
                case 'path': return new StringValue(file.path);
                case 'folder': return new StringValue(file.parent ? file.parent.path : '');
                case 'ext': return new StringValue(file.extension);
                case 'size': return new NumberValue(file.stat ? file.stat.size : 0);
                case 'ctime': return file.stat ? new DateValue(new Date(file.stat.ctime)) : NullValue.value;
                case 'mtime': return file.stat ? new DateValue(new Date(file.stat.mtime)) : NullValue.value;
                case 'file': return new FileValue(file);
                case 'tags': return new ListValue((cache && exportedApi.getAllTags ? exportedApi.getAllTags(cache) || [] : []).map((tag) => new TagValue(tag)));
                case 'links': return new ListValue((cache && cache.links ? cache.links : []).map((link) => new LinkValue('[[' + link.link + ']]')));
                default: return NullValue.value;
                }
            }
            if (type === 'note') {
                const cache = runtime.app ? runtime.app.metadataCache.getFileCache(file) : null;
                const frontmatter = cache && cache.frontmatter ? cache.frontmatter : {};
                return wrapValue(frontmatter[name]);
            }
            return NullValue.value;
        }
    }

    class BasesEntryGroup {
        constructor() {
            this.key = null;
            this.entries = [];
        }
        hasKey() { return this.key !== null; }
    }

    class BasesQueryResult {
        constructor(data, groups, properties) {
            this.data = data || [];
            this.groups = groups || null;
            this.propertyIds = properties || [];
        }
        get groupedData() {
            if (this.groups) return this.groups;
            const group = new BasesEntryGroup();
            group.entries = this.data;
            return this.data.length ? [group] : [];
        }
        get properties() { return this.propertyIds; }
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

    // MARK: Plugins' views in Graphite's bases

    /// The views plugins registered (`registerBasesView`), by type.
    runtime.basesViews = new Map();
    let isBasesNotificationScheduled = false;
    runtime.basesViewsChanged = function basesViewsChanged() {
        if (isBasesNotificationScheduled) return;
        isBasesNotificationScheduled = true;
        Promise.resolve().then(() => {
            isBasesNotificationScheduled = false;
            runtime.hostBridge.notify('basesViews.changed', {
                views: Array.from(runtime.basesViews.entries()).map(([viewType, registered]) => ({ viewType, name: registered.registration.name || viewType, pluginIdentifier: registered.pluginIdentifier })),
            });
        });
    };

    /// A base's view of a plugin's type, shown in a leaf Graphite shows live in the base's tab.
    class PluginBasesHostView extends exportedApi.ItemView {
        getViewType() { return 'graphite-bases-plugin-view'; }
        getDisplayText() { return this.viewName || 'Base'; }
    }

    function resultFrom(message) {
        const app = runtime.app;
        const fileOf = (path) => app.vault.getFileByPath(path);
        const groups = (message.groups || []).map((group) => {
            const entryGroup = new BasesEntryGroup();
            entryGroup.key = group.key === null || group.key === undefined ? null : wrapValue(group.key);
            entryGroup.entries = (group.paths || []).map(fileOf).filter(Boolean).map((file) => new BasesEntry(file));
            return entryGroup;
        });
        const data = groups.flatMap((group) => group.entries);
        const isGrouped = groups.some((group) => group.key !== null);
        return new BasesQueryResult(data, isGrouped ? groups : null, message.properties || []);
    }

    /// The view's settings as the `.base` file writes them: its keys are what the plugin's
    /// view reads with `config.get` (TaskNotes' date and status properties).
    async function baseDefinition(baseFilePath, baseYaml) {
        try {
            const app = runtime.app;
            let text = typeof baseYaml === 'string' ? baseYaml : null;
            if (text === null) {
                const file = app.vault.getFileByPath(baseFilePath);
                if (!file) return {};
                text = await app.vault.cachedRead(file);
            }
            return exportedApi.parseYaml(text) || {};
        } catch (error) {
            return {};
        }
    }

    /// The base's results grouped by the view's `groupBy`, as Obsidian gives a grouped view
    /// (Graphite's own result for a plugin's view type is not grouped).
    function groupedByView(result, groupBy) {
        const property = groupBy && typeof groupBy === 'object' ? groupBy.property : groupBy;
        if (!property || result.groups) return result;
        const groupsByKey = new Map();
        for (const entry of result.data) {
            const value = entry.getValue(String(property).includes('.') ? property : 'note.' + property);
            const key = value && !(value instanceof NullValue) ? value.toString() : '';
            if (!groupsByKey.has(key)) {
                const group = new BasesEntryGroup();
                group.key = key === '' ? null : value;
                groupsByKey.set(key, group);
            }
            groupsByKey.get(key).entries.push(entry);
        }
        return new BasesQueryResult(result.data, Array.from(groupsByKey.values()), result.propertyIds);
    }

    async function viewOptions(baseFilePath, viewIndex, baseYaml) {
        try {
            const app = runtime.app;
            let text = typeof baseYaml === 'string' ? baseYaml : null;
            if (text === null) {
                const file = app.vault.getFileByPath(baseFilePath);
                if (!file) return {};
                text = await app.vault.cachedRead(file);
            }
            const definition = exportedApi.parseYaml(text) || {};
            const view = Array.isArray(definition.views) ? definition.views[viewIndex] : null;
            return view && typeof view === 'object' ? view : {};
        } catch (error) {
            return {};
        }
    }

    /// Joined to the runtime's messages when the plugins' script installs them.
    runtime.basesMessageHandlers = ({
        /// Graphite's base shows a view of a plugin's type: the plugin's view is made in a leaf
        /// over the base's results, and Graphite shows the leaf live in the base's tab.
        async 'basesView.open'(message) {
            const app = runtime.app;
            const registered = app ? runtime.basesViews.get(message.viewType) : null;
            if (!registered) return { isOpened: false, message: 'No plugin shows “' + message.viewType + '” views now.' };
            const leaf = app.workspace.createPluginLeaf('bases');
            leaf.hasBeenShown = true;
            const hostView = new PluginBasesHostView(leaf);
            hostView.viewName = message.viewName || '';
            await leaf.open(hostView);
            const controller = new QueryController();
            controller.load();
            const options = await viewOptions(message.baseFilePath || '', Number(message.viewIndex) || 0, message.baseYaml);
            // Obsidian's controller knows the base's parsed views and the one shown (undocumented;
            // TaskNotes reads the Kanban's groupBy there).
            const definition = await baseDefinition(message.baseFilePath || '', message.baseYaml);
            controller.query = { views: Array.isArray(definition.views) ? definition.views : [] };
            controller.viewName = message.viewName || options.name || '';
            hostView.groupBy = options.groupBy;
            try {
                const view = registered.registration.factory(controller, hostView.contentEl);
                const config = new BasesViewConfig(message.viewName || options.name || '');
                Object.assign(config.options, options);
                const order = Array.isArray(options.order) ? options.order.map(String) : [];
                config.getOrder = () => order;
                config.getSort = () => (Array.isArray(options.sort) ? options.sort : []);
                view.config = config;
                view.allProperties = message.properties || order;
                view.data = groupedByView(resultFrom(message), options.groupBy);
                controller.addChild(view);
                hostView.basesView = view;
                hostView.controller = controller;
                hostView.register(() => controller.unload());
                view.onDataUpdated();
            } catch (error) {
                console.error(error);
                hostView.contentEl.empty();
                hostView.contentEl.createDiv({ cls: 'graphite-plugin-error', text: String(error && error.message ? error.message : error) });
                runtime.hostBridge.notify('plugin.failure', { pluginIdentifier: registered.pluginIdentifier, message: 'Its “' + message.viewType + '” view failed: ' + (error && error.message ? error.message : String(error)) });
            }
            return { isOpened: true, leafIdentifier: leaf.id };
        },
        /// The base's results changed (a file changed, a filter was edited).
        async 'basesView.update'(message) {
            const leaf = runtime.app ? runtime.app.workspace.getLeafById(message.leafIdentifier) : null;
            const view = leaf && leaf.view && leaf.view.basesView;
            if (!view) return { isUpdated: false };
            view.data = groupedByView(resultFrom(message), leaf.view.groupBy);
            try { view.onDataUpdated(); } catch (error) { console.error(error); }
            return { isUpdated: true };
        },
    });

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

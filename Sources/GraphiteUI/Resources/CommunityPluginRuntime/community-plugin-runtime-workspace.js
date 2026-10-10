// Obsidian's workspace for plugins. Graphite's own tabs show notes and PDFs natively; the
// runtime mirrors the focused note as the active `MarkdownView`, whose `Editor` works on a
// copy of the note's text that Graphite sends. Edits a plugin makes are sent back as one
// change, which Graphite's editor applies as one undoable edit, and only while the note
// still has the text the plugin saw. Views a plugin registers live in plugin leaves, which
// Graphite shows on the plugin panel.
(function installRuntimeWorkspace(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Events, Component, TFile, normalizePath, parseLinktext } = exportedApi;
    const hostBridge = runtime.hostBridge;

    let nextLeafNumber = 1;

    // MARK: Editor

    function comparePositions(firstPosition, secondPosition) {
        return firstPosition.line - secondPosition.line || firstPosition.ch - secondPosition.ch;
    }

    class Editor {
        getDoc() { return this; }
        refresh() {}
        focus() {}
        blur() {}
        hasFocus() { return true; }
        getScrollInfo() { return { top: 0, left: 0 }; }
        scrollTo() {}
        scrollIntoView() {}
        somethingSelected() { return this.listSelections().some((selection) => comparePositions(selection.anchor, selection.head) !== 0); }
        lastLine() { return this.lineCount() - 1; }
        setLine(lineNumber, text) {
            this.replaceRange(text, { line: lineNumber, ch: 0 }, { line: lineNumber, ch: this.getLine(lineNumber).length });
        }
        setCursor(positionOrLine, character) {
            const position = typeof positionOrLine === 'number' ? { line: positionOrLine, ch: character || 0 } : positionOrLine;
            this.setSelection(position, position);
        }
        processLines(read, write, isIgnoringEmpty) {
            const lineStates = [];
            for (let lineNumber = 0; lineNumber < this.lineCount(); lineNumber += 1) {
                const line = this.getLine(lineNumber);
                lineStates.push(isIgnoringEmpty && line.trim() === '' ? undefined : read(lineNumber, line));
            }
            const changes = [];
            for (let lineNumber = 0; lineNumber < this.lineCount(); lineNumber += 1) {
                if (lineStates[lineNumber] === undefined) continue;
                const change = write(lineNumber, lineStates[lineNumber]);
                if (change) changes.push(change);
            }
            if (changes.length > 0) this.transaction({ changes });
        }
    }

    /// An `Editor` over a copy of the open note's text.
    class SnapshotEditor extends Editor {
        constructor(snapshot) {
            super();
            this.adoptSnapshot(snapshot);
            this.pendingFlush = null;
        }

        adoptSnapshot(snapshot) {
            this.path = snapshot.path;
            this.snapshotIdentifier = snapshot.snapshotIdentifier;
            this.text = snapshot.text;
            this.isReadOnly = Boolean(snapshot.isReadOnly);
            this.lineStarts = null;
            const anchor = this.offsetToPos(snapshot.selectionAnchor || 0);
            const head = this.offsetToPos(snapshot.selectionHead === undefined ? snapshot.selectionAnchor || 0 : snapshot.selectionHead);
            this.selections = [{ anchor, head }];
            this.mainSelectionPosition = 0;
            this.hasUnsentChanges = false;
        }

        computeLineStarts() {
            if (this.lineStarts) return this.lineStarts;
            const starts = [0];
            for (let offset = 0; offset < this.text.length; offset += 1) { if (this.text.charCodeAt(offset) === 10) starts.push(offset + 1); }
            this.lineStarts = starts;
            return starts;
        }

        // Reading.

        getValue() { return this.text; }
        lineCount() { return this.computeLineStarts().length; }
        getLine(lineNumber) {
            const starts = this.computeLineStarts();
            if (lineNumber < 0 || lineNumber >= starts.length) return '';
            const end = lineNumber + 1 < starts.length ? starts[lineNumber + 1] - 1 : this.text.length;
            return this.text.slice(starts[lineNumber], end).replace(/\r$/, '');
        }
        posToOffset(position) {
            const starts = this.computeLineStarts();
            const lineNumber = Math.min(Math.max(position.line, 0), starts.length - 1);
            const lineLength = this.getLine(lineNumber).length;
            return starts[lineNumber] + Math.min(Math.max(position.ch, 0), lineLength);
        }
        offsetToPos(offset) {
            const starts = this.computeLineStarts();
            const clampedOffset = Math.min(Math.max(offset, 0), this.text.length);
            let low = 0;
            let high = starts.length - 1;
            while (low < high) {
                const middle = Math.ceil((low + high) / 2);
                if (starts[middle] <= clampedOffset) low = middle; else high = middle - 1;
            }
            return { line: low, ch: clampedOffset - starts[low] };
        }
        getRange(from, to) {
            const fromOffset = this.posToOffset(from);
            const toOffset = this.posToOffset(to);
            return this.text.slice(Math.min(fromOffset, toOffset), Math.max(fromOffset, toOffset));
        }
        listSelections() {
            return this.selections.map((selection) => ({ anchor: Object.assign({}, selection.anchor), head: Object.assign({}, selection.head) }));
        }
        mainSelection() { return this.selections[this.mainSelectionPosition] || this.selections[0]; }
        getSelection() {
            const selection = this.mainSelection();
            return this.getRange(selection.anchor, selection.head);
        }
        getCursor(side) {
            const selection = this.mainSelection();
            const ordered = comparePositions(selection.anchor, selection.head) <= 0;
            const from = ordered ? selection.anchor : selection.head;
            const to = ordered ? selection.head : selection.anchor;
            switch (side) {
            case 'from': return Object.assign({}, from);
            case 'to': return Object.assign({}, to);
            case 'anchor': return Object.assign({}, selection.anchor);
            default: return Object.assign({}, selection.head);
            }
        }
        wordAt(position) {
            const line = this.getLine(position.line);
            const isWordCharacter = (character) => /[\p{L}\p{N}_]/u.test(character);
            let start = position.ch;
            let end = position.ch;
            while (start > 0 && isWordCharacter(line[start - 1])) start -= 1;
            while (end < line.length && isWordCharacter(line[end])) end += 1;
            if (start === end) return null;
            return { from: { line: position.line, ch: start }, to: { line: position.line, ch: end } };
        }

        // Changing.

        /// Replaces `[fromOffset, toOffset)` and moves every selection past the change.
        replaceOffsets(fromOffset, toOffset, replacement) {
            if (this.isReadOnly) runtime.unsupported('Editing a note shown in reading view', 'Switch the note to editing first.');
            const start = Math.min(fromOffset, toOffset);
            const end = Math.max(fromOffset, toOffset);
            const selectionOffsets = this.selections.map((selection) => [this.posToOffset(selection.anchor), this.posToOffset(selection.head)]);
            this.text = this.text.slice(0, start) + replacement + this.text.slice(end);
            this.lineStarts = null;
            const lengthChange = replacement.length - (end - start);
            const moved = (offset) => (offset <= start ? offset : offset >= end ? offset + lengthChange : start + replacement.length);
            this.selections = selectionOffsets.map((offsets) => ({ anchor: this.offsetToPos(moved(offsets[0])), head: this.offsetToPos(moved(offsets[1])) }));
            this.scheduleFlush();
        }
        setValue(content) {
            this.replaceOffsets(0, this.text.length, content);
            this.selections = [{ anchor: { line: 0, ch: 0 }, head: { line: 0, ch: 0 } }];
        }
        replaceRange(replacement, from, to) {
            const fromOffset = this.posToOffset(from);
            this.replaceOffsets(fromOffset, to ? this.posToOffset(to) : fromOffset, replacement);
        }
        replaceSelection(replacement) {
            const selection = this.mainSelection();
            const fromOffset = Math.min(this.posToOffset(selection.anchor), this.posToOffset(selection.head));
            const toOffset = Math.max(this.posToOffset(selection.anchor), this.posToOffset(selection.head));
            this.replaceOffsets(fromOffset, toOffset, replacement);
            const cursor = this.offsetToPos(fromOffset + replacement.length);
            this.selections[this.mainSelectionPosition] = { anchor: cursor, head: cursor };
        }
        setSelection(anchor, head) {
            this.selections = [{ anchor: this.offsetToPos(this.posToOffset(anchor)), head: this.offsetToPos(this.posToOffset(head || anchor)) }];
            this.mainSelectionPosition = 0;
            this.scheduleFlush();
        }
        setSelections(ranges, mainPosition) {
            if (!ranges || ranges.length === 0) return;
            this.selections = ranges.map((range) => ({ anchor: this.offsetToPos(this.posToOffset(range.anchor)), head: this.offsetToPos(this.posToOffset(range.head || range.anchor)) }));
            this.mainSelectionPosition = Math.min(mainPosition || 0, this.selections.length - 1);
            if (this.selections.length > 1) runtime.reportUnsupportedFeature('Several selections at once (Graphite keeps the main one)');
            this.scheduleFlush();
        }
        transaction(transaction) {
            const changes = [];
            for (const change of transaction.changes || []) {
                changes.push({ from: this.posToOffset(change.from), to: this.posToOffset(change.to || change.from), text: change.text });
            }
            if (transaction.replaceSelection !== undefined) {
                const selection = this.mainSelection();
                changes.push({ from: this.posToOffset(selection.anchor), to: this.posToOffset(selection.head), text: transaction.replaceSelection });
            }
            // Every change is given in positions of the text before the transaction, so
            // they are applied from the end of the note backwards.
            changes.sort((firstChange, secondChange) => Math.min(secondChange.from, secondChange.to) - Math.min(firstChange.from, firstChange.to));
            for (const change of changes) this.replaceOffsets(change.from, change.to, change.text);
            if (transaction.selection) this.setSelection(transaction.selection.from, transaction.selection.to || transaction.selection.from);
            if (transaction.selections) this.setSelections(transaction.selections.map((range) => ({ anchor: range.from, head: range.to || range.from })));
        }
        exec(command) {
            const cursor = this.getCursor();
            switch (command) {
            case 'goStart': this.setCursor({ line: 0, ch: 0 }); return;
            case 'goEnd': this.setCursor(this.offsetToPos(this.text.length)); return;
            case 'goUp': this.setCursor({ line: Math.max(cursor.line - 1, 0), ch: cursor.ch }); return;
            case 'goDown': this.setCursor({ line: Math.min(cursor.line + 1, this.lastLine()), ch: cursor.ch }); return;
            case 'goLeft': this.setCursor(this.offsetToPos(this.posToOffset(cursor) - 1)); return;
            case 'goRight': this.setCursor(this.offsetToPos(this.posToOffset(cursor) + 1)); return;
            case 'newlineAndIndent': {
                const indentation = /^\s*/.exec(this.getLine(cursor.line))[0];
                this.replaceSelection('\n' + indentation);
                return;
            }
            case 'indentMore': case 'indentLess': {
                const from = this.getCursor('from');
                const to = this.getCursor('to');
                const changes = [];
                for (let lineNumber = from.line; lineNumber <= to.line; lineNumber += 1) {
                    const line = this.getLine(lineNumber);
                    if (command === 'indentMore') changes.push({ from: { line: lineNumber, ch: 0 }, text: '\t' });
                    else {
                        const removable = /^(\t| {1,4})/.exec(line);
                        if (removable) changes.push({ from: { line: lineNumber, ch: 0 }, to: { line: lineNumber, ch: removable[0].length }, text: '' });
                    }
                }
                this.transaction({ changes });
                return;
            }
            case 'deleteLine': {
                const lineNumber = cursor.line;
                const startOffset = this.posToOffset({ line: lineNumber, ch: 0 });
                const endOffset = lineNumber < this.lastLine() ? this.posToOffset({ line: lineNumber + 1, ch: 0 }) : this.text.length;
                this.replaceOffsets(lineNumber === this.lastLine() && lineNumber > 0 ? startOffset - 1 : startOffset, endOffset, '');
                return;
            }
            case 'swapLineUp': case 'swapLineDown': {
                const otherLine = command === 'swapLineUp' ? cursor.line - 1 : cursor.line + 1;
                if (otherLine < 0 || otherLine > this.lastLine()) return;
                const firstLine = Math.min(cursor.line, otherLine);
                const firstText = this.getLine(firstLine);
                const secondText = this.getLine(firstLine + 1);
                this.replaceRange(secondText + '\n' + firstText, { line: firstLine, ch: 0 }, { line: firstLine + 1, ch: secondText.length });
                this.setCursor({ line: otherLine, ch: cursor.ch });
                return;
            }
            default:
                runtime.unsupported('Editor command “' + command + '”');
            }
        }
        undo() { runtime.unsupported('Editor.undo', 'Use Graphite\'s Undo.'); }
        redo() { runtime.unsupported('Editor.redo', 'Use Graphite\'s Redo.'); }

        // Sending changes to Graphite.

        scheduleFlush() {
            this.hasUnsentChanges = true;
            // Read now: once the plugin's own code has returned, the stack no longer names it.
            if (!this.changingPluginIdentifier) this.changingPluginIdentifier = runtime.callingPluginIdentifier();
            if (this.pendingFlush) return;
            this.pendingFlush = Promise.resolve().then(() => this.flush());
        }

        /// Sends the text and selection to Graphite once the plugin's synchronous work is
        /// done, so edits made together become one undoable change.
        async flush() {
            this.pendingFlush = null;
            if (!this.hasUnsentChanges) return;
            this.hasUnsentChanges = false;
            const pluginIdentifier = this.changingPluginIdentifier;
            this.changingPluginIdentifier = null;
            const selection = this.mainSelection();
            try {
                const response = await hostBridge.send('editor.apply', {
                    path: this.path,
                    snapshotIdentifier: this.snapshotIdentifier,
                    text: this.text,
                    selectionAnchor: this.posToOffset(selection.anchor),
                    selectionHead: this.posToOffset(selection.head),
                    pluginIdentifier,
                });
                if (response.snapshot && !this.hasUnsentChanges) this.adoptSnapshot(response.snapshot);
            } catch (error) {
                console.error('Graphite did not apply a plugin\'s change to “' + this.path + '”.', error);
                if (error.snapshot) this.adoptSnapshot(error.snapshot);
            }
        }
    }

    // MARK: Leaves and views

    class WorkspaceItem extends Events {
        getRoot() { return runtime.app ? runtime.app.workspace.rootSplit : this; }
        getContainer() { return runtime.app ? runtime.app.workspace.rootSplit : this; }
    }
    class WorkspaceParent extends WorkspaceItem {}
    class WorkspaceSplit extends WorkspaceParent {}
    class WorkspaceRoot extends WorkspaceSplit {}
    class WorkspaceTabs extends WorkspaceParent {}
    class WorkspaceSidedock extends WorkspaceSplit {
        constructor(side) {
            super();
            this.side = side;
            this.collapsed = true;
            this.containerEl = createDiv({ cls: 'workspace-split mod-' + side + '-split' });
        }
        collapse() { this.collapsed = true; }
        expand() { this.collapsed = false; }
        toggle() { this.collapsed = !this.collapsed; }
    }
    class WorkspaceMobileDrawer extends WorkspaceSidedock {}
    class WorkspaceFloating extends WorkspaceParent {}
    class WorkspaceContainer extends WorkspaceSplit {}
    class WorkspaceWindow extends WorkspaceContainer {}
    class WorkspaceRibbon {
        constructor(side) { this.side = side; this.containerEl = createDiv({ cls: 'workspace-ribbon side-dock-ribbon mod-' + side }); }
    }

    class View extends Component {
        constructor(leaf) {
            super();
            this.leaf = leaf;
            this.app = leaf ? leaf.app : runtime.app;
            this.icon = 'document';
            this.navigation = false;
            this.closeable = true;
            this.scope = null;
            this.containerEl = createDiv({ cls: 'workspace-leaf-content' });
            this.headerEl = this.containerEl.createDiv({ cls: 'view-header' });
            this.titleEl = this.headerEl.createDiv({ cls: 'view-header-title' });
            this.actionsEl = this.headerEl.createDiv({ cls: 'view-actions' });
            this.containerEl.createDiv({ cls: 'view-content' });
        }
        getViewType() { return 'empty'; }
        getDisplayText() { return ''; }
        getIcon() { return this.icon; }
        getState() { return {}; }
        async setState() {}
        getEphemeralState() { return {}; }
        setEphemeralState() {}
        async onOpen() {}
        async onClose() {}
        onResize() {}
        onPaneMenu() {}
        onHeaderMenu() {}
        async open(parentElement) {
            this.load();
            parentElement.appendChild(this.containerEl);
            this.titleEl.setText(this.getDisplayText());
            await this.onOpen();
        }
        async close() {
            await this.onClose();
            this.unload();
            this.containerEl.detach();
        }
    }

    class ItemView extends View {
        constructor(leaf) {
            super(leaf);
            this.contentEl = this.containerEl.children[1];
        }
        addAction(icon, title, callback) {
            const actionElement = this.actionsEl.createEl('button', { cls: 'clickable-icon view-action', attr: { 'aria-label': title } });
            exportedApi.setIcon(actionElement, icon);
            actionElement.addEventListener('click', callback);
            return actionElement;
        }
    }

    class FileView extends ItemView {
        constructor(leaf) {
            super(leaf);
            this.file = null;
            this.allowNoFile = false;
        }
        getDisplayText() { return this.file ? this.file.basename : 'No file'; }
        canAcceptExtension() { return false; }
        async onLoadFile() {}
        async onUnloadFile() {}
        async onRename(file) { this.file = file; }
        getState() { return this.file ? { file: this.file.path } : {}; }
        async setState(state) {
            const file = state && state.file ? this.app.vault.getFileByPath(state.file) : null;
            if (file && file !== this.file) await this.loadFile(file);
        }
        async loadFile(file) {
            if (this.file) await this.onUnloadFile(this.file);
            this.file = file;
            await this.onLoadFile(file);
        }
    }

    class EditableFileView extends FileView {}

    class TextFileView extends EditableFileView {
        constructor(leaf) {
            super(leaf);
            this.data = '';
            this.requestSave = exportedApi.debounce(() => { this.save(); }, 2000, true);
        }
        async onLoadFile(file) {
            this.data = await this.app.vault.read(file);
            this.setViewData(this.data, true);
        }
        async onUnloadFile() {
            await this.save();
            this.clear();
        }
        async save() {
            if (!this.file) return;
            const viewData = this.getViewData();
            if (viewData === this.data) return;
            this.data = viewData;
            await this.app.vault.modify(this.file, viewData);
        }
        getViewData() { return this.data; }
        setViewData(data) { this.data = data; }
        clear() {}
    }

    /// The note Graphite has focused, as a plugin sees it.
    class MarkdownView extends TextFileView {
        constructor(leaf) {
            super(leaf);
            this.editor = null;
            this.currentMode = { type: 'source' };
            this.previewMode = { containerEl: createDiv({ cls: 'markdown-preview-view' }), rerender() {}, getScroll: () => 0, applyScroll() {} };
        }
        getViewType() { return 'markdown'; }
        getMode() { return this.mode === 'reading' ? 'preview' : 'source'; }
        getViewData() { return this.editor ? this.editor.getValue() : this.data; }
        setViewData(data) {
            if (this.editor) this.editor.setValue(data);
            else this.data = data;
        }
        showSearch() { runtime.unsupported('MarkdownView.showSearch', 'Use Search current file in Graphite.'); }
        async save() {}
    }

    class WorkspaceLeaf extends WorkspaceItem {
        constructor(app, kind) {
            super();
            this.app = app;
            this.kind = kind;
            this.id = 'graphite-leaf-' + nextLeafNumber;
            nextLeafNumber += 1;
            this.view = new EmptyView(this);
            this.pinned = false;
            this.isDeferred = false;
            this.containerEl = createDiv({ cls: 'workspace-leaf' });
            this.tabHeaderEl = createDiv({ cls: 'workspace-tab-header' });
            this.tabHeaderInnerIconEl = this.tabHeaderEl.createDiv({ cls: 'workspace-tab-header-inner-icon' });
            this.tabHeaderInnerTitleEl = this.tabHeaderEl.createDiv({ cls: 'workspace-tab-header-inner-title' });
        }
        getViewState() {
            return { type: this.view.getViewType(), state: this.view.getState(), active: this.app.workspace.activeLeaf === this, pinned: this.pinned };
        }
        async setViewState(viewState, ephemeralState) {
            const workspace = this.app.workspace;
            if (viewState.type === 'markdown' && viewState.state && viewState.state.file) {
                await hostBridge.send('workspace.openFile', { path: viewState.state.file, placement: this.kind === 'mirror' ? 'currentTab' : 'newTab' });
                return;
            }
            if (viewState.type === 'empty') {
                await this.replaceView(new EmptyView(this));
                return;
            }
            const viewCreator = workspace.viewCreatorsByType.get(viewState.type);
            if (!viewCreator) runtime.unsupported('Opening a view of type “' + viewState.type + '”', 'No plugin registered it.');
            const view = viewCreator(this);
            await this.replaceView(view);
            if (viewState.state) await view.setState(viewState.state, { history: false });
            if (ephemeralState) view.setEphemeralState(ephemeralState);
            if (viewState.active) await workspace.revealLeaf(this);
            workspace.notifyLeavesChanged();
        }
        async replaceView(view) {
            const previousView = this.view;
            this.view = view;
            if (previousView) await previousView.close();
            await view.open(this.containerEl);
            this.updateHeader();
            this.app.workspace.trigger('layout-change');
        }
        updateHeader() {
            this.tabHeaderInnerTitleEl.setText(this.getDisplayText());
            exportedApi.setIcon(this.tabHeaderInnerIconEl, this.getIcon());
        }
        async open(view) {
            await this.replaceView(view);
            this.app.workspace.notifyLeavesChanged();
            return view;
        }
        async openFile(file, openState) {
            await hostBridge.send('workspace.openFile', { path: file.path, placement: this.kind === 'mirror' ? 'currentTab' : 'newTab', subpath: openState && openState.eState && openState.eState.subpath ? openState.eState.subpath : null });
        }
        getDisplayText() { return this.view.getDisplayText(); }
        getIcon() { return this.view.getIcon(); }
        getEphemeralState() { return this.view.getEphemeralState(); }
        setEphemeralState(state) { this.view.setEphemeralState(state); }
        getRoot() { return this.app.workspace.rootSplit; }
        getContainer() { return this.app.workspace.rootSplit; }
        setPinned(isPinned) { this.pinned = Boolean(isPinned); this.trigger('pinned-change', this.pinned); }
        togglePinned() { this.setPinned(!this.pinned); }
        setGroup() { runtime.reportUnsupportedFeature('Linked view groups'); }
        setGroupMember() { runtime.reportUnsupportedFeature('Linked view groups'); }
        async loadIfDeferred() {}
        onResize() { this.view.onResize(); }
        detach() {
            const workspace = this.app.workspace;
            if (this.kind === 'mirror') return;
            workspace.pluginLeaves.remove(this);
            this.view.close();
            this.containerEl.detach();
            if (workspace.activeLeaf === this) workspace.activeLeaf = workspace.markdownLeaf.view instanceof MarkdownView && workspace.markdownLeaf.view.file ? workspace.markdownLeaf : null;
            workspace.notifyLeavesChanged();
            workspace.trigger('layout-change');
        }
    }

    class EmptyView extends ItemView {
        getViewType() { return 'empty'; }
        getDisplayText() { return 'New tab'; }
    }

    // MARK: Workspace

    class Workspace extends Events {
        constructor(app) {
            super();
            this.app = app;
            this.layoutReady = false;
            this.layoutReadyCallbacks = [];
            this.viewCreatorsByType = new Map();
            this.pluginLeaves = [];
            this.containerEl = createDiv({ cls: 'workspace' });
            this.rootSplit = new WorkspaceRoot();
            this.leftSplit = new WorkspaceMobileDrawer('left');
            this.rightSplit = new WorkspaceMobileDrawer('right');
            this.leftRibbon = new WorkspaceRibbon('left');
            this.rightRibbon = new WorkspaceRibbon('right');
            this.markdownLeaf = new WorkspaceLeaf(app, 'mirror');
            this.activeLeaf = null;
            this.activeEditor = null;
            this.activeFilePath = null;
            this.lastOpenFiles = [];
            this.revealedLeaf = null;
            this.requestSaveLayout = exportedApi.debounce(() => {}, 0);
            this.editorSuggest = { suggests: [] };
        }

        // State Graphite sends.

        /// The focused document changed: a note (with the text the editor holds), another
        /// file, or nothing.
        setActiveDocument(description) {
            const path = description && description.path ? normalizePath(description.path) : null;
            const file = path ? this.app.vault.getFileByPath(path) : null;
            const previousPath = this.activeFilePath;
            this.activeFilePath = path;
            if (file && file.extension === 'md') {
                if (!(this.markdownLeaf.view instanceof MarkdownView)) this.markdownLeaf.view = new MarkdownView(this.markdownLeaf);
                const view = this.markdownLeaf.view;
                view.file = file;
                view.mode = description.mode;
                view.currentMode = { type: description.mode === 'reading' ? 'preview' : 'source' };
                if (description.editorSnapshot) this.updateEditorSnapshot(description.editorSnapshot);
                else if (!view.editor || view.editor.path !== path) view.editor = null;
                this.activeLeaf = this.markdownLeaf;
                this.activeEditor = view.editor ? { editor: view.editor, file } : null;
            } else {
                this.markdownLeaf.view = new EmptyView(this.markdownLeaf);
                this.activeLeaf = this.revealedLeaf || null;
                this.activeEditor = null;
            }
            if (previousPath !== path) {
                this.trigger('file-open', file);
                this.trigger('active-leaf-change', this.activeLeaf);
            }
        }

        updateEditorSnapshot(snapshot) {
            const view = this.markdownLeaf.view;
            if (!(view instanceof MarkdownView) || !view.file || normalizePath(snapshot.path) !== view.file.path) return null;
            if (view.editor) view.editor.adoptSnapshot(snapshot);
            else view.editor = new SnapshotEditor(snapshot);
            this.activeEditor = { editor: view.editor, file: view.file };
            return view.editor;
        }

        markLayoutReady() {
            if (this.layoutReady) return;
            this.layoutReady = true;
            for (const callback of this.layoutReadyCallbacks.splice(0)) {
                try { callback(); } catch (error) { console.error(error); }
            }
            this.trigger('layout-ready');
        }

        notifyLeavesChanged() {
            hostBridge.notify('views.changed', {
                views: this.pluginLeaves.map((leaf) => ({ leafIdentifier: leaf.id, viewType: leaf.view.getViewType(), title: leaf.getDisplayText(), icon: leaf.getIcon() })),
            });
        }

        // Obsidian's public API.

        onLayoutReady(callback) {
            if (this.layoutReady) globalScope.setTimeout(callback, 0);
            else this.layoutReadyCallbacks.push(callback);
        }
        getActiveFile() {
            return this.activeFilePath ? this.app.vault.getFileByPath(this.activeFilePath) : null;
        }
        getActiveViewOfType(type) {
            const view = this.activeLeaf ? this.activeLeaf.view : null;
            return view instanceof type ? view : null;
        }
        getActiveFileView() {
            const view = this.activeLeaf ? this.activeLeaf.view : null;
            return view instanceof FileView ? view : null;
        }
        getLeaf(newLeaf) {
            if (!newLeaf || newLeaf === false) {
                if (this.activeLeaf && this.activeLeaf !== this.markdownLeaf && !this.activeLeaf.pinned) return this.activeLeaf;
                return this.markdownLeaf;
            }
            return this.createPluginLeaf('tab');
        }
        getUnpinnedLeaf() { return this.getLeaf(false); }
        getMostRecentLeaf() { return this.activeLeaf || this.markdownLeaf; }
        createLeafBySplit() { return this.createPluginLeaf('split'); }
        createLeafInParent() { return this.createPluginLeaf('tab'); }
        getRightLeaf() { return this.createPluginLeaf('right'); }
        getLeftLeaf() { return this.createPluginLeaf('left'); }
        async ensureSideLeaf(viewType, side, options) {
            let leaf = this.getLeavesOfType(viewType)[0];
            if (!leaf) {
                leaf = this.createPluginLeaf(side === 'left' ? 'left' : 'right');
                await leaf.setViewState({ type: viewType, state: options && options.state, active: options && options.active });
            } else if (options && options.reveal) await this.revealLeaf(leaf);
            return leaf;
        }
        createPluginLeaf(kind) {
            const leaf = new WorkspaceLeaf(this.app, kind);
            this.pluginLeaves.push(leaf);
            return leaf;
        }
        getLeavesOfType(viewType) {
            const leaves = this.pluginLeaves.filter((leaf) => leaf.view.getViewType() === viewType);
            if (viewType === 'markdown' && this.markdownLeaf.view instanceof MarkdownView && this.markdownLeaf.view.file) leaves.unshift(this.markdownLeaf);
            return leaves;
        }
        getLeafById(identifier) {
            if (this.markdownLeaf.id === identifier) return this.markdownLeaf;
            return this.pluginLeaves.find((leaf) => leaf.id === identifier) || null;
        }
        detachLeavesOfType(viewType) {
            for (const leaf of this.getLeavesOfType(viewType)) leaf.detach();
        }
        iterateAllLeaves(callback) {
            if (this.markdownLeaf.view instanceof MarkdownView && this.markdownLeaf.view.file) callback(this.markdownLeaf);
            for (const leaf of this.pluginLeaves.slice()) callback(leaf);
        }
        iterateRootLeaves(callback) { this.iterateAllLeaves(callback); }
        setActiveLeaf(leaf) {
            if (leaf === this.activeLeaf) return;
            this.activeLeaf = leaf;
            this.trigger('active-leaf-change', leaf);
        }
        /// Shows a plugin's leaf on Graphite's plugin panel.
        async revealLeaf(leaf) {
            if (leaf === this.markdownLeaf) return;
            if (!this.pluginLeaves.includes(leaf)) this.pluginLeaves.push(leaf);
            this.revealedLeaf = leaf;
            runtime.pluginSurface.showLeaf(leaf);
            this.setActiveLeaf(leaf);
            this.notifyLeavesChanged();
        }
        async openLinkText(linktext, sourcePath, newLeaf) {
            const { path, subpath } = parseLinktext(linktext);
            const destination = this.app.metadataCache.getFirstLinkpathDest(path, sourcePath || '');
            await hostBridge.send('workspace.openLinkText', {
                linktext,
                sourcePath: sourcePath || '',
                resolvedPath: destination ? destination.path : null,
                subpath: subpath || null,
                placement: newLeaf ? 'newTab' : 'currentTab',
            });
        }
        getLastOpenFiles() { return this.lastOpenFiles.slice(); }
        updateOptions() {}
        changeLayout() { return Promise.resolve(); }
        getLayout() { return {}; }
        duplicateLeaf() { runtime.unsupported('Workspace.duplicateLeaf'); }
        splitActiveLeaf() { return this.createPluginLeaf('split'); }
        getGroupLeaves() { return []; }
        /// Adds Obsidian's items for a link to a menu.
        handleLinkContextMenu(menu, linktext, sourcePath) {
            menu.addItem((item) => item.setTitle('Open link').setIcon('lucide-file').onClick(() => this.openLinkText(linktext, sourcePath, false)));
            menu.addItem((item) => item.setTitle('Open in new tab').setIcon('lucide-file-plus').onClick(() => this.openLinkText(linktext, sourcePath, true)));
            return true;
        }
        /// Hover previews (undocumented `registerHoverLinkSource`); Graphite has none yet.
        registerHoverLinkSource() { runtime.reportUnsupportedFeature('Hover previews'); }
        unregisterHoverLinkSource() {}
        moveLeafToPopout() { runtime.unsupported('Pop-out windows', 'Graphite runs plugins as Obsidian mobile does.'); }
        openPopoutLeaf() { runtime.unsupported('Pop-out windows', 'Graphite runs plugins as Obsidian mobile does.'); }
    }

    // MARK: Rendering Markdown

    /// A component tied to an element a plugin rendered into.
    class MarkdownRenderChild extends Component {
        constructor(containerElement) {
            super();
            this.containerEl = containerElement;
        }
    }

    class MarkdownRenderer extends MarkdownRenderChild {
        /// Renders Markdown into `element` with Graphite's Markdown reader, then runs the
        /// plugins' post-processors over it, as Obsidian does for plugin views.
        static async render(app, markdown, element, sourcePath, component) {
            const response = await hostBridge.send('markdown.render', { markdown: String(markdown), sourcePath: sourcePath || '' });
            const container = element.createDiv ? element : element;
            const fragment = exportedApi.sanitizeHTMLToDom(response.html || '');
            const wrapper = createDiv();
            wrapper.appendChild(fragment);
            convertInternalLinks(app, wrapper, sourcePath || '');
            while (wrapper.firstChild) container.appendChild(wrapper.firstChild);
            await runtime.runMarkdownPostProcessors(container, sourcePath || '', component, markdown);
        }
        static async renderMarkdown(markdown, element, sourcePath, component) {
            return MarkdownRenderer.render(runtime.app, markdown, element, sourcePath, component);
        }
    }

    /// Turns `[[links]]` that Graphite's reader left as text into Obsidian's internal links.
    function convertInternalLinks(app, container, sourcePath) {
        const walker = container.ownerDocument.createTreeWalker(container, 4);
        const textNodes = [];
        while (walker.nextNode()) {
            const node = walker.currentNode;
            if (node.parentElement && node.parentElement.closest('code, pre')) continue;
            if (node.textContent.includes('[[')) textNodes.push(node);
        }
        for (const node of textNodes) {
            const fragment = container.ownerDocument.createDocumentFragment();
            let lastEnd = 0;
            const text = node.textContent;
            const pattern = /(!?)\[\[([^\]\n]+?)\]\]/g;
            let match;
            while ((match = pattern.exec(text)) !== null) {
                fragment.appendText(text.slice(lastEnd, match.index));
                const inner = match[2];
                const pipePosition = inner.indexOf('|');
                const target = pipePosition === -1 ? inner : inner.slice(0, pipePosition);
                const label = pipePosition === -1 ? inner : inner.slice(pipePosition + 1);
                const destination = app.metadataCache.getFirstLinkpathDest(parseLinktext(target).path, sourcePath);
                const anchor = fragment.createEl('a', { cls: destination ? 'internal-link' : 'internal-link is-unresolved', text: label, attr: { 'data-href': target, href: target } });
                anchor.addEventListener('click', (event) => {
                    event.preventDefault();
                    app.workspace.openLinkText(target, sourcePath, false);
                });
                lastEnd = match.index + match[0].length;
            }
            fragment.appendText(text.slice(lastEnd));
            node.parentNode.replaceChild(fragment, node);
        }
    }

    class MarkdownPreviewView extends MarkdownRenderer {
        constructor(containerElement) {
            super(containerElement || createDiv({ cls: 'markdown-preview-view' }));
            this.markdown = '';
            this.scroll = 0;
        }
        get() { return this.markdown; }
        set(markdown) {
            this.markdown = markdown;
            this.rerender();
        }
        clear() {
            this.markdown = '';
            this.containerEl.empty();
        }
        rerender() {
            this.containerEl.empty();
            MarkdownRenderer.render(runtime.app, this.markdown, this.containerEl, '', this);
        }
        getScroll() { return this.scroll; }
        applyScroll(scroll) { this.scroll = scroll; }
    }

    /// Obsidian's editing mode of a note view; Graphite's editor is native.
    class MarkdownEditView {
        constructor(view) {
            this.view = view;
            runtime.reportUnsupportedFeature('MarkdownEditView');
        }
    }
    class MarkdownPreviewRenderer {
        static registerPostProcessor(postProcessor, sortOrder) {
            runtime.markdownPostProcessors.push({ postProcessor, sortOrder: sortOrder || 0, pluginIdentifier: null });
        }
        static unregisterPostProcessor(postProcessor) {
            runtime.markdownPostProcessors = runtime.markdownPostProcessors.filter((registered) => registered.postProcessor !== postProcessor);
        }
        static createCodeBlockPostProcessor(language, handler) {
            return (element, context) => runtime.runCodeBlockProcessor(language, handler, element, context);
        }
    }

    Object.assign(exportedApi, {
        Editor, Workspace, WorkspaceLeaf, WorkspaceItem, WorkspaceParent, WorkspaceSplit, WorkspaceRoot, WorkspaceTabs,
        WorkspaceSidedock, WorkspaceMobileDrawer, WorkspaceFloating, WorkspaceContainer, WorkspaceWindow, WorkspaceRibbon,
        View, ItemView, FileView, EditableFileView, TextFileView, MarkdownView, MarkdownRenderChild, MarkdownRenderer,
        MarkdownPreviewView, MarkdownPreviewRenderer, MarkdownEditView,
    });
    runtime.SnapshotEditor = SnapshotEditor;
    runtime.EmptyView = EmptyView;
})(globalThis);

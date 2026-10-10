// Obsidian's vault for plugins: the file tree (`TFile`, `TFolder`), `Vault`, the low-level
// `DataAdapter`, and `FileManager`. Contents are never kept here: every read asks Graphite,
// and every write goes through Graphite's coordinated, revision-checked writer.
(function installRuntimeVault(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Events, normalizePath, arrayBufferToBase64, base64ToArrayBuffer, parseYaml, stringifyYaml, getFrontMatterInfo } = exportedApi;
    const hostBridge = runtime.hostBridge;

    // MARK: Files and folders

    class TAbstractFile {
        constructor(vault, path, parent) {
            this.vault = vault;
            this.path = path;
            this.name = path === '/' ? '' : path.slice(path.lastIndexOf('/') + 1);
            this.parent = parent || null;
        }
    }

    class TFile extends TAbstractFile {
        constructor(vault, path, parent, stat) {
            super(vault, path, parent);
            this.stat = stat || { ctime: 0, mtime: 0, size: 0 };
            this.updateNameParts();
        }
        updateNameParts() {
            const dotPosition = this.name.lastIndexOf('.');
            this.basename = dotPosition > 0 ? this.name.slice(0, dotPosition) : this.name;
            this.extension = dotPosition > 0 ? this.name.slice(dotPosition + 1) : '';
        }
    }

    /// A file outside the vault (Obsidian desktop opens them). Graphite has none.
    class TExternalFile extends TFile {
        getRealPath() { return this.path; }
    }

    class TFolder extends TAbstractFile {
        constructor(vault, path, parent) {
            super(vault, path, parent);
            this.children = [];
        }
        isRoot() {
            return this.path === '/';
        }
    }

    function parentPath(path) {
        const separatorPosition = path.lastIndexOf('/');
        return separatorPosition === -1 ? '/' : path.slice(0, separatorPosition);
    }

    function isHiddenPath(path) {
        return path.split('/').some((component) => component.startsWith('.'));
    }

    function statFromHost(hostStat) {
        if (!hostStat) return null;
        return { ctime: hostStat.created || hostStat.modified || 0, mtime: hostStat.modified || 0, size: hostStat.size || 0 };
    }

    function textFromData(data) {
        if (typeof data === 'string') return data;
        throw new TypeError('Expected text to write.');
    }

    function conflictError(path) {
        return new Error('“' + path + '” changed outside this plugin after the plugin read it, so Graphite did not overwrite it. Read the file again and retry.');
    }

    /// Obsidian's values for settings `.obsidian/app.json` does not hold, for the keys
    /// plugins read most (`vault.getConfig`).
    const obsidianDefaultConfiguration = {
        attachmentFolderPath: '/', newLinkFormat: 'shortest', useMarkdownLinks: false, newFileLocation: 'root', newFileFolderPath: '/',
        alwaysUpdateLinks: false, trashOption: 'system', promptDelete: true, showInlineTitle: true, readableLineLength: true,
        strictLineBreaks: false, useTab: true, tabSize: 4, spellcheck: true, autoPairBrackets: true, autoPairMarkdown: true,
        smartIndentList: true, foldHeading: true, foldIndent: true, showLineNumber: false, livePreview: true, defaultViewMode: 'source',
        showFrontmatter: false, propertiesInDocument: 'visible', userIgnoreFilters: [], fileSortOrder: 'alphabetical', vimMode: false,
    };

    // MARK: Data adapter

    /// The vault's file system as Obsidian mobile's adapter exposes it: paths relative to the
    /// vault, including hidden ones such as the configuration folder.
    class DataAdapter {
        constructor(vault) {
            this.vault = vault;
            this.revisionsByPath = new Map();
            this.processCallsByPath = new Map();
        }
        getName() {
            return this.vault.vaultName;
        }
        async exists(path, isCaseSensitive) {
            const normalizedPath = normalizePath(path);
            const response = await hostBridge.send('vault.stat', { path: normalizedPath });
            if (!response.stat) return false;
            if (isCaseSensitive && response.storedPath && response.storedPath !== normalizedPath) return false;
            return true;
        }
        async stat(path) {
            const response = await hostBridge.send('vault.stat', { path: normalizePath(path) });
            if (!response.stat) return null;
            return { type: response.stat.isFolder ? 'folder' : 'file', ctime: response.stat.created || 0, mtime: response.stat.modified || 0, size: response.stat.size || 0 };
        }
        async list(path) {
            const normalizedPath = normalizePath(path);
            const response = await hostBridge.send('vault.listFolder', { path: normalizedPath === '/' ? '' : normalizedPath });
            return { files: response.files || [], folders: response.folders || [] };
        }
        async read(path) {
            const normalizedPath = normalizePath(path);
            const response = await hostBridge.send('vault.read', { path: normalizedPath, encoding: 'text' });
            this.revisionsByPath.set(normalizedPath, response.revision);
            return response.text;
        }
        async readBinary(path) {
            const normalizedPath = normalizePath(path);
            const response = await hostBridge.send('vault.read', { path: normalizedPath, encoding: 'binary' });
            this.revisionsByPath.set(normalizedPath, response.revision);
            return base64ToArrayBuffer(response.base64);
        }
        /// The revision a write expects: the one this runtime last read or wrote, so a file
        /// changed since then is not overwritten, or whatever is there now otherwise.
        writeExpectation(path) {
            const revision = this.revisionsByPath.get(path);
            return revision ? { kind: 'revision', revision } : { kind: 'replace' };
        }
        /// Writes `payload` (`{ text }` or `{ base64 }`). `isReportingConflict` is false while
        /// `process` can still read and try again. The plugin is named by the caller when the
        /// write follows an `await`, after which the stack no longer shows the plugin's code.
        async writeData(path, payload, expectation, isReportingConflict = true, pluginIdentifier = runtime.callingPluginIdentifier()) {
            let response;
            try {
                response = await hostBridge.send('vault.write', Object.assign({ path, expectation }, payload));
            } catch (error) {
                if (error.kind === 'conflict') {
                    if (expectation.kind === 'absent') throw new Error('File already exists.');
                    if (isReportingConflict) hostBridge.notify('plugin.writeConflict', { path, pluginIdentifier });
                    throw conflictError(path);
                }
                throw error;
            }
            this.revisionsByPath.set(path, response.revision);
            this.vault.reconcileWrittenPath(path, response.stat);
            return response;
        }
        async write(path, data, options) {
            const normalizedPath = normalizePath(path);
            await this.writeData(normalizedPath, { text: textFromData(data) }, this.writeExpectation(normalizedPath));
            if (options) await this.applyTimes(normalizedPath, options);
        }
        async writeBinary(path, data, options) {
            const normalizedPath = normalizePath(path);
            await this.writeData(normalizedPath, { base64: arrayBufferToBase64(data) }, this.writeExpectation(normalizedPath));
            if (options) await this.applyTimes(normalizedPath, options);
        }
        async applyTimes(path, options) {
            if (options.mtime === undefined && options.ctime === undefined) return;
            runtime.reportUnsupportedFeature('Setting file times (DataWriteOptions)');
        }
        async append(path, data, options) {
            await this.process(path, (existingText) => existingText + textFromData(data), options);
        }
        async appendBinary(path, data, options) {
            const normalizedPath = normalizePath(path);
            const existing = (await this.exists(normalizedPath)) ? new Uint8Array(await this.readBinary(normalizedPath)) : new Uint8Array(0);
            const addition = new Uint8Array(data);
            const combined = new Uint8Array(existing.length + addition.length);
            combined.set(existing, 0);
            combined.set(addition, existing.length);
            await this.writeData(normalizedPath, { base64: arrayBufferToBase64(combined.buffer) }, this.writeExpectation(normalizedPath));
            if (options) await this.applyTimes(normalizedPath, options);
        }
        getFullPath(path) {
            runtime.unsupported('DataAdapter.getFullPath (“' + path + '”)', 'Plugins reach vault files through the vault, not by their place on the device.');
        }
        /// Calls for the same file run one after another, as in Obsidian, where `process` reads
        /// and writes in one step: each transform sees the text the one before it wrote.
        async process(path, transform, options) {
            const normalizedPath = normalizePath(path);
            const pluginIdentifier = runtime.callingPluginIdentifier();
            const previousCall = this.processCallsByPath.get(normalizedPath) || Promise.resolve();
            const call = previousCall.catch(() => {}).then(() => this.processNow(normalizedPath, transform, options, pluginIdentifier));
            this.processCallsByPath.set(normalizedPath, call);
            try {
                return await call;
            } finally {
                if (this.processCallsByPath.get(normalizedPath) === call) this.processCallsByPath.delete(normalizedPath);
            }
        }
        async processNow(normalizedPath, transform, options, pluginIdentifier) {
            // A file changed between the read and the write is read and transformed again,
            // so the transform always applies to the file as it is.
            for (let attempt = 0; attempt < 3; attempt += 1) {
                const response = await hostBridge.send('vault.read', { path: normalizedPath, encoding: 'text' });
                this.revisionsByPath.set(normalizedPath, response.revision);
                const existingText = response.text;
                const transformedText = transform(existingText);
                if (transformedText === existingText) return transformedText;
                // The write expects the revision this attempt read, whatever other reads of the
                // file recorded meanwhile.
                const expectation = { kind: 'revision', revision: response.revision };
                try {
                    await this.writeData(normalizedPath, { text: transformedText }, expectation, attempt === 2, pluginIdentifier);
                    if (options) await this.applyTimes(normalizedPath, options);
                    return transformedText;
                } catch (error) {
                    if (attempt === 2 || !/changed outside this plugin/.test(error.message)) throw error;
                }
            }
            throw conflictError(normalizedPath);
        }
        getResourcePath(path) {
            return exportedApi.Platform.resourcePathPrefix + normalizePath(path).split('/').map(encodeURIComponent).join('/');
        }
        async mkdir(path) {
            const normalizedPath = normalizePath(path);
            const response = await hostBridge.send('vault.createFolder', { path: normalizedPath });
            this.vault.reconcileWrittenPath(normalizedPath, response.stat);
        }
        async trashSystem(path) {
            const normalizedPath = normalizePath(path);
            const response = await hostBridge.send('vault.remove', { path: normalizedPath, method: 'system' });
            this.forgetRemovedPath(normalizedPath);
            return response.outcome === 'systemTrash';
        }
        async trashLocal(path) {
            const normalizedPath = normalizePath(path);
            await hostBridge.send('vault.remove', { path: normalizedPath, method: 'local' });
            this.forgetRemovedPath(normalizedPath);
        }
        async rmdir(path, isRecursive) {
            const normalizedPath = normalizePath(path);
            await hostBridge.send('vault.remove', { path: normalizedPath, method: 'permanent', isRecursive: Boolean(isRecursive), isFolderExpected: true });
            this.forgetRemovedPath(normalizedPath);
        }
        async remove(path) {
            const normalizedPath = normalizePath(path);
            await hostBridge.send('vault.remove', { path: normalizedPath, method: 'permanent', isFolderExpected: false });
            this.forgetRemovedPath(normalizedPath);
        }
        async rename(path, newPath) {
            const normalizedPath = normalizePath(path);
            const normalizedNewPath = normalizePath(newPath);
            await hostBridge.send('vault.rename', { path: normalizedPath, destinationPath: normalizedNewPath });
            this.moveRevisions(normalizedPath, normalizedNewPath);
            this.vault.reconcileMovedPath(normalizedPath, normalizedNewPath);
        }
        async copy(path, newPath) {
            const normalizedNewPath = normalizePath(newPath);
            const response = await hostBridge.send('vault.copy', { path: normalizePath(path), destinationPath: normalizedNewPath });
            this.vault.reconcileWrittenPath(normalizedNewPath, response.stat);
        }
        forgetRemovedPath(path) {
            for (const knownPath of Array.from(this.revisionsByPath.keys())) {
                if (knownPath === path || knownPath.startsWith(path + '/')) this.revisionsByPath.delete(knownPath);
            }
            this.vault.reconcileRemovedPath(path);
        }
        moveRevisions(oldPath, newPath) {
            for (const knownPath of Array.from(this.revisionsByPath.keys())) {
                if (knownPath === oldPath || knownPath.startsWith(oldPath + '/')) {
                    const revision = this.revisionsByPath.get(knownPath);
                    this.revisionsByPath.delete(knownPath);
                    this.revisionsByPath.set(newPath + knownPath.slice(oldPath.length), revision);
                }
            }
        }
    }

    /// Obsidian mobile's adapter class. Graphite's adapter is one, so plugins that check
    /// `instanceof CapacitorAdapter` take their mobile path.
    class CapacitorAdapter extends DataAdapter {}

    /// Obsidian's desktop adapter. Graphite never creates one; plugins test against it.
    class FileSystemAdapter extends DataAdapter {
        constructor() {
            super(null);
            runtime.unsupported('FileSystemAdapter', 'Graphite runs plugins as Obsidian mobile does, without direct file system access.');
        }
    }

    // MARK: Vault

    class Vault extends Events {
        constructor() {
            super();
            this.vaultName = '';
            this.configDir = '.obsidian';
            this.configuration = {};
            this.adapter = new CapacitorAdapter(this);
            this.abstractFilesByPath = new Map();
            this.root = new TFolder(this, '/', null);
            this.abstractFilesByPath.set('/', this.root);
        }

        // Loading and reconciling the tree.

        /// Reads the vault's file tree from Graphite: names and sizes only.
        async loadFileTree() {
            const response = await hostBridge.send('vault.list', {});
            this.addHostEntries(response.entries || [], false);
            if (response.isTruncated) {
                console.warn('Graphite listed only part of this vault to plugins, because it holds more files than the plugin runtime keeps in its file list.');
            }
        }

        addHostEntries(entries, isTriggeringEvents) {
            const sortedEntries = entries.slice().sort((firstEntry, secondEntry) => firstEntry.path.split('/').length - secondEntry.path.split('/').length);
            for (const entry of sortedEntries) {
                if (isHiddenPath(entry.path)) continue;
                this.addAbstractFile(entry.path, entry.isFolder, statFromHost(entry), isTriggeringEvents);
            }
        }

        addAbstractFile(path, isFolder, stat, isTriggeringEvents) {
            const existing = this.abstractFilesByPath.get(path);
            if (existing) return existing;
            const parent = this.ensureFolder(parentPath(path), isTriggeringEvents);
            const abstractFile = isFolder ? new TFolder(this, path, parent) : new TFile(this, path, parent, stat);
            parent.children.push(abstractFile);
            this.abstractFilesByPath.set(path, abstractFile);
            if (isTriggeringEvents) this.trigger('create', abstractFile);
            return abstractFile;
        }

        ensureFolder(path, isTriggeringEvents) {
            if (path === '/' || path === '') return this.root;
            const existing = this.abstractFilesByPath.get(path);
            if (existing instanceof TFolder) return existing;
            return this.addAbstractFile(path, true, null, isTriggeringEvents);
        }

        removeAbstractFile(abstractFile, isTriggeringEvents) {
            if (abstractFile instanceof TFolder) {
                for (const child of abstractFile.children.slice()) this.removeAbstractFile(child, isTriggeringEvents);
            }
            if (abstractFile.parent) abstractFile.parent.children.remove(abstractFile);
            this.abstractFilesByPath.delete(abstractFile.path);
            if (isTriggeringEvents) this.trigger('delete', abstractFile);
        }

        /// After a write by a plugin: the file is created or updated in the tree, with the
        /// events Obsidian sends for it.
        reconcileWrittenPath(path, hostStat) {
            if (isHiddenPath(path)) return;
            const existing = this.abstractFilesByPath.get(path);
            const stat = statFromHost(hostStat);
            if (existing instanceof TFile) {
                if (stat) existing.stat = stat;
                this.trigger('modify', existing);
            } else if (!existing) {
                this.addAbstractFile(path, Boolean(hostStat && hostStat.isFolder), stat, true);
            }
        }

        reconcileRemovedPath(path) {
            const existing = this.abstractFilesByPath.get(path);
            if (existing) this.removeAbstractFile(existing, true);
        }

        reconcileMovedPath(oldPath, newPath) {
            const abstractFile = this.abstractFilesByPath.get(oldPath);
            if (!abstractFile) {
                if (!isHiddenPath(newPath)) this.reconcileChangedPaths([{ path: newPath, stat: null, isReloadNeeded: true }]);
                return;
            }
            if (isHiddenPath(newPath)) {
                this.removeAbstractFile(abstractFile, true);
                return;
            }
            const newParent = this.ensureFolder(parentPath(newPath), true);
            if (abstractFile.parent) abstractFile.parent.children.remove(abstractFile);
            newParent.children.push(abstractFile);
            abstractFile.parent = newParent;
            const movedFiles = [];
            const collect = (item) => { movedFiles.push(item); if (item instanceof TFolder) item.children.forEach(collect); };
            collect(abstractFile);
            const oldPaths = new Map(movedFiles.map((item) => [item, item.path]));
            for (const item of movedFiles) {
                this.abstractFilesByPath.delete(item.path);
                item.path = newPath + item.path.slice(oldPath.length);
                item.name = item.path.slice(item.path.lastIndexOf('/') + 1);
                if (item instanceof TFile) item.updateNameParts();
                this.abstractFilesByPath.set(item.path, item);
            }
            for (const item of movedFiles) this.trigger('rename', item, oldPaths.get(item));
        }

        /// Changes Graphite reports: other apps, Graphite's own editors, file providers.
        /// Each path comes with what is there now (nothing when it is gone).
        async reconcileChangedPaths(changes) {
            for (const change of changes) {
                const path = normalizePath(change.path);
                if (isHiddenPath(path)) continue;
                const existing = this.abstractFilesByPath.get(path);
                // The revision a plugin read stays: a write based on that read must not
                // replace what changed since, even though the plugin was told of the change.
                if (!change.stat && !change.isReloadNeeded) {
                    if (existing) this.removeAbstractFile(existing, true);
                    continue;
                }
                let hostStat = change.stat;
                if (!hostStat) hostStat = (await hostBridge.send('vault.stat', { path })).stat;
                if (!hostStat) { if (existing) this.removeAbstractFile(existing, true); continue; }
                if (existing instanceof TFile && !hostStat.isFolder) {
                    existing.stat = statFromHost(hostStat);
                    this.trigger('modify', existing);
                } else if (existing && Boolean(hostStat.isFolder) !== (existing instanceof TFolder)) {
                    this.removeAbstractFile(existing, true);
                    this.addAbstractFile(path, hostStat.isFolder, statFromHost(hostStat), true);
                } else if (!existing) {
                    this.addAbstractFile(path, hostStat.isFolder, statFromHost(hostStat), true);
                    if (hostStat.isFolder) {
                        const response = await hostBridge.send('vault.list', { folder: path });
                        this.addHostEntries(response.entries || [], true);
                    }
                }
            }
        }

        // Obsidian's public API.

        getName() { return this.vaultName; }
        getRoot() { return this.root; }
        getAbstractFileByPath(path) {
            return this.abstractFilesByPath.get(normalizePath(path)) || null;
        }
        getAbstractFileByPathInsensitive(path) {
            const exact = this.getAbstractFileByPath(path);
            if (exact) return exact;
            const lowercasedPath = normalizePath(path).toLowerCase();
            for (const [knownPath, abstractFile] of this.abstractFilesByPath) { if (knownPath.toLowerCase() === lowercasedPath) return abstractFile; }
            return null;
        }
        getFileByPath(path) {
            const abstractFile = this.getAbstractFileByPath(path);
            return abstractFile instanceof TFile ? abstractFile : null;
        }
        getFolderByPath(path) {
            const abstractFile = this.getAbstractFileByPath(path);
            return abstractFile instanceof TFolder ? abstractFile : null;
        }
        getAllLoadedFiles() { return Array.from(this.abstractFilesByPath.values()); }
        getAllFolders(isIncludingRoot) {
            return Array.from(this.abstractFilesByPath.values()).filter((abstractFile) => abstractFile instanceof TFolder && (isIncludingRoot || !abstractFile.isRoot()));
        }
        getFiles() {
            return Array.from(this.abstractFilesByPath.values()).filter((abstractFile) => abstractFile instanceof TFile);
        }
        getMarkdownFiles() {
            return this.getFiles().filter((file) => file.extension === 'md');
        }
        static recurseChildren(folder, callback) {
            callback(folder);
            if (folder instanceof TFolder) for (const child of folder.children) Vault.recurseChildren(child, callback);
        }

        async read(file) { return this.adapter.read(file.path); }
        async cachedRead(file) { return this.adapter.read(file.path); }
        async readBinary(file) { return this.adapter.readBinary(file.path); }

        async create(path, data, options) {
            const normalizedPath = normalizePath(path);
            if (this.abstractFilesByPath.has(normalizedPath)) throw new Error('File already exists.');
            await this.adapter.writeData(normalizedPath, { text: textFromData(data) }, { kind: 'absent' });
            if (options) await this.adapter.applyTimes(normalizedPath, options);
            return this.getFileByPath(normalizedPath);
        }
        async createBinary(path, data, options) {
            const normalizedPath = normalizePath(path);
            if (this.abstractFilesByPath.has(normalizedPath)) throw new Error('File already exists.');
            await this.adapter.writeData(normalizedPath, { base64: arrayBufferToBase64(data) }, { kind: 'absent' });
            if (options) await this.adapter.applyTimes(normalizedPath, options);
            return this.getFileByPath(normalizedPath);
        }
        async createFolder(path) {
            const normalizedPath = normalizePath(path);
            if (this.abstractFilesByPath.has(normalizedPath)) throw new Error('Folder already exists.');
            await this.adapter.mkdir(normalizedPath);
            return this.getFolderByPath(normalizedPath);
        }
        async modify(file, data, options) { await this.adapter.write(file.path, data, options); }
        async modifyBinary(file, data, options) { await this.adapter.writeBinary(file.path, data, options); }
        async append(file, data, options) { await this.adapter.append(file.path, data, options); }
        async appendBinary(file, data, options) {
            const existing = new Uint8Array(await this.readBinary(file));
            const addition = new Uint8Array(data);
            const combined = new Uint8Array(existing.length + addition.length);
            combined.set(existing, 0);
            combined.set(addition, existing.length);
            await this.adapter.writeData(file.path, { base64: arrayBufferToBase64(combined.buffer) }, this.adapter.writeExpectation(file.path));
            if (options) await this.adapter.applyTimes(file.path, options);
        }
        async process(file, transform, options) { return this.adapter.process(file.path, transform, options); }
        async delete(file) {
            await hostBridge.send('vault.remove', { path: file.path, method: 'permanent', isRecursive: true, isFolderExpected: file instanceof TFolder });
            this.adapter.forgetRemovedPath(file.path);
        }
        async trash(file, isUsingSystemTrash) {
            await hostBridge.send('vault.remove', { path: file.path, method: isUsingSystemTrash ? 'system' : 'local' });
            this.adapter.forgetRemovedPath(file.path);
        }
        async rename(file, newPath) {
            const normalizedNewPath = normalizePath(newPath);
            if (this.abstractFilesByPath.has(normalizedNewPath) && normalizedNewPath.toLowerCase() !== file.path.toLowerCase()) throw new Error('Destination file already exists!');
            await this.adapter.rename(file.path, normalizedNewPath);
        }
        async copy(file, newPath) {
            const normalizedNewPath = normalizePath(newPath);
            if (this.abstractFilesByPath.has(normalizedNewPath)) throw new Error('Destination file already exists!');
            await this.adapter.copy(file.path, normalizedNewPath);
            return this.getAbstractFileByPath(normalizedNewPath);
        }
        getResourcePath(file) {
            return this.adapter.getResourcePath(file.path) + '?' + (file.stat ? file.stat.mtime : 0);
        }
        /// Obsidian's settings from `.obsidian/app.json` (undocumented but widely used).
        getConfig(key) {
            if (Object.prototype.hasOwnProperty.call(this.configuration, key)) return this.configuration[key];
            return Object.prototype.hasOwnProperty.call(obsidianDefaultConfiguration, key) ? obsidianDefaultConfiguration[key] : null;
        }
        setConfig(key) {
            runtime.unsupported('Vault.setConfig (“' + key + '”)', 'Change Obsidian settings in Graphite\'s Settings.');
        }
    }

    // MARK: File manager

    class FileManager {
        constructor(app) {
            this.app = app;
            this.vault = app.vault;
        }

        getNewFileParent(sourcePath) {
            const location = this.vault.getConfig('newFileLocation') || 'root';
            if (location === 'current' && sourcePath) {
                const sourceFile = this.vault.getAbstractFileByPath(sourcePath);
                if (sourceFile && sourceFile.parent) return sourceFile.parent;
            }
            if (location === 'folder') {
                const folder = this.vault.getFolderByPath(this.vault.getConfig('newFileFolderPath') || '/');
                if (folder) return folder;
            }
            return this.vault.getRoot();
        }

        async renameFile(file, newPath) {
            // Graphite renames the file and rewrites links to it per the vault's
            // "Automatically update internal links" setting, as Obsidian does here.
            const normalizedNewPath = normalizePath(newPath);
            await hostBridge.send('workspace.renameFile', { path: file.path, destinationPath: normalizedNewPath });
            this.vault.adapter.moveRevisions(file.path, normalizedNewPath);
            this.vault.reconcileMovedPath(file.path, normalizedNewPath);
        }

        async trashFile(file) {
            await hostBridge.send('vault.remove', { path: file.path, method: 'vaultSetting' });
            this.vault.adapter.forgetRemovedPath(file.path);
        }

        async promptForDeletion(file) {
            await this.trashFile(file);
            return true;
        }

        generateMarkdownLink(file, sourcePath, subpath, alias) {
            const useMarkdownLinks = Boolean(this.vault.getConfig('useMarkdownLinks'));
            const linktext = this.app.metadataCache.fileToLinktext(file, sourcePath, !useMarkdownLinks);
            const embedPrefix = file.extension !== 'md' ? '!' : '';
            const subpathText = subpath || '';
            if (useMarkdownLinks) {
                const markdownPath = encodeURI(linktext.endsWith('.md') || file.extension !== 'md' ? linktext : linktext + '.md').replace(/\(/g, '%28').replace(/\)/g, '%29');
                return embedPrefix + '[' + (alias || file.basename) + '](' + markdownPath + encodeURI(subpathText) + ')';
            }
            return embedPrefix + '[[' + linktext + subpathText + (alias ? '|' + alias : '') + ']]';
        }

        /// Where an attachment named `filename` goes for the note at `sourcePath`, from the
        /// vault's "Default location for new attachments", with a number added when taken.
        async getAvailablePathForAttachment(filename, sourcePath) {
            const configuredFolder = this.vault.getConfig('attachmentFolderPath') || '/';
            const sourceFolder = sourcePath ? parentPath(normalizePath(sourcePath)) : '/';
            let folder;
            if (configuredFolder === '/' || configuredFolder === '') folder = '';
            else if (configuredFolder === './' || configuredFolder === '.') folder = sourceFolder === '/' ? '' : sourceFolder;
            else if (configuredFolder.startsWith('./')) folder = normalizePath((sourceFolder === '/' ? '' : sourceFolder + '/') + configuredFolder.slice(2));
            else folder = normalizePath(configuredFolder);
            if (folder === '/') folder = '';
            const dotPosition = filename.lastIndexOf('.');
            const stem = dotPosition > 0 ? filename.slice(0, dotPosition) : filename;
            const extension = dotPosition > 0 ? filename.slice(dotPosition) : '';
            for (let suffix = 0; suffix < 100000; suffix += 1) {
                const candidateName = suffix === 0 ? stem + extension : stem + ' ' + suffix + extension;
                const candidatePath = folder ? folder + '/' + candidateName : candidateName;
                if (!(await this.vault.adapter.exists(candidatePath))) {
                    if (folder && !this.vault.getFolderByPath(folder) && !(await this.vault.adapter.exists(folder))) await this.vault.createFolder(folder);
                    return candidatePath;
                }
            }
            throw new Error('Choose another name.');
        }

        /// Obsidian's `processFrontMatter`: the frontmatter as an object, changed in place by
        /// `transform`, then written back. An unchanged object leaves the note untouched.
        async processFrontMatter(file, transform, options) {
            await this.vault.adapter.process(file.path, (existingText) => {
                const information = getFrontMatterInfo(existingText);
                const frontmatter = (information.exists ? parseYaml(information.frontmatter) : null) || {};
                const before = JSON.stringify(frontmatter);
                transform(frontmatter);
                if (JSON.stringify(frontmatter) === before) return existingText;
                const lineEnding = existingText.includes('\r\n') ? '\r\n' : '\n';
                const yaml = Object.keys(frontmatter).length === 0 ? '' : stringifyYaml(frontmatter).replace(/\n/g, lineEnding);
                if (information.exists) {
                    const openingEnd = information.from;
                    return existingText.slice(0, openingEnd) + yaml + existingText.slice(information.to);
                }
                return '---' + lineEnding + yaml + '---' + lineEnding + existingText;
            }, options);
        }

        getAllProperties() {
            return this.app.metadataCache.getAllPropertyInfos();
        }
    }

    Object.assign(exportedApi, { TAbstractFile, TFile, TExternalFile, TFolder, Vault, DataAdapter, CapacitorAdapter, FileSystemAdapter, FileManager });
    runtime.isHiddenPath = isHiddenPath;
    runtime.parentPath = parentPath;
})(globalThis);

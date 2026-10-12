// Answers the plugin runtime's messages from a vault folder on disk, as Graphite's native
// bridge (`CommunityPluginVaultBridge` and `CommunityPluginHost`) does in the app. The two
// follow one contract: the same operations, answers, revisions (SHA-256 and size) and
// failure kinds, and a write is refused when the file is not at the expected revision.
'use strict';

const fileSystem = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const byteOrderMark = Buffer.from([0xEF, 0xBB, 0xBF]);

function revisionOf(bytes) {
    return { digest: crypto.createHash('sha256').update(bytes).digest('hex'), size: bytes.length };
}

function isHidden(vaultPath) {
    return vaultPath.split('/').some((component) => component.startsWith('.'));
}

class HostFailure extends Error {
    constructor(kind, message) {
        super(message);
        this.kind = kind;
    }
}

class TestVaultHost {
    constructor(vaultFolder) {
        this.vaultFolder = path.resolve(vaultFolder);
        this.notifications = [];
        this.requests = [];
        this.openedFiles = [];
        this.editorSessions = new Map();
        this.menuChoice = null;
        this.networkResponder = null;
        this.notDownloadedPaths = new Set();
    }

    /// The location of a vault path, refusing anything outside the vault.
    location(vaultPath) {
        const normalized = String(vaultPath || '').replace(/^\/+/, '');
        const resolved = path.resolve(this.vaultFolder, normalized);
        if (resolved !== this.vaultFolder && !resolved.startsWith(this.vaultFolder + path.sep)) throw new HostFailure('outsideVault', 'This path is outside the selected vault.');
        return resolved;
    }

    stat(location) {
        try {
            const status = fileSystem.statSync(location);
            return { isFolder: status.isDirectory(), size: status.isDirectory() ? 0 : status.size, modified: status.mtimeMs, created: status.birthtimeMs || status.mtimeMs };
        } catch (error) {
            return null;
        }
    }

    vaultPathOf(location) {
        return path.relative(this.vaultFolder, location).split(path.sep).join('/');
    }

    /// The transport the runtime calls.
    transport() {
        return async (message) => {
            this.requests.push(message);
            try {
                return await this.handle(message);
            } catch (error) {
                if (error instanceof HostFailure) return { failure: { kind: error.kind, message: error.message } };
                return { failure: { kind: 'failed', message: error.message } };
            }
        };
    }

    async handle(message) {
        switch (message.operation) {
        case 'vault.list': return this.listVault(message.folder || '');
        case 'vault.listFolder': return this.listFolder(message.path || '');
        case 'vault.stat': {
            const stat = this.stat(this.location(message.path));
            return { stat, storedPath: stat ? message.path : null };
        }
        case 'vault.read': return this.read(message);
        case 'vault.write': return this.write(message);
        case 'vault.createFolder': {
            const location = this.location(message.path);
            fileSystem.mkdirSync(location, { recursive: true });
            return { stat: this.stat(location) };
        }
        case 'vault.remove': return this.remove(message);
        case 'vault.rename': {
            const source = this.location(message.path);
            const destination = this.location(message.destinationPath);
            if (!fileSystem.existsSync(source)) throw new HostFailure('missing', '“' + message.path + '” is no longer in the vault.');
            if (fileSystem.existsSync(destination) && source.toLowerCase() !== destination.toLowerCase()) throw new HostFailure('exists', '“' + message.destinationPath + '” already exists.');
            fileSystem.mkdirSync(path.dirname(destination), { recursive: true });
            fileSystem.renameSync(source, destination);
            return { stat: this.stat(destination) };
        }
        case 'vault.copy': {
            const source = this.location(message.path);
            const destination = this.location(message.destinationPath);
            if (fileSystem.existsSync(destination)) throw new HostFailure('exists', '“' + message.destinationPath + '” already exists.');
            fileSystem.mkdirSync(path.dirname(destination), { recursive: true });
            fileSystem.cpSync(source, destination, { recursive: true });
            return { stat: this.stat(destination) };
        }
        case 'workspace.renameFile': {
            this.notifications.push(message);
            return this.handle(Object.assign({}, message, { operation: 'vault.rename' }));
        }
        case 'workspace.openFile':
        case 'workspace.openLinkText':
            this.openedFiles.push(message);
            return {};
        case 'editor.apply': return this.applyEditorChange(message);
        case 'markdown.render': return { html: renderMarkdownForTests(message.markdown) };
        case 'menu.show':
            this.notifications.push(message);
            return { chosenPosition: this.menuChoice };
        case 'network.request':
            if (!this.networkResponder) throw new HostFailure('offline', 'The test host has no network.');
            return this.networkResponder(message);
        case 'plugins.setEnabled':
            this.notifications.push(message);
            return {};
        default:
            this.notifications.push(message);
            return {};
        }
    }

    listVault(folder) {
        const entries = [];
        const start = this.location(folder);
        const visit = (location) => {
            for (const name of fileSystem.readdirSync(location)) {
                if (name.startsWith('.')) continue;
                const childLocation = path.join(location, name);
                const stat = this.stat(childLocation);
                if (!stat) continue;
                entries.push(Object.assign({ path: this.vaultPathOf(childLocation) }, stat));
                if (stat.isFolder) visit(childLocation);
            }
        };
        visit(start);
        return { entries, isTruncated: false };
    }

    listFolder(folder) {
        const location = this.location(folder);
        const files = [];
        const folders = [];
        for (const name of fileSystem.readdirSync(location)) {
            const childPath = folder ? folder + '/' + name : name;
            if (fileSystem.statSync(path.join(location, name)).isDirectory()) folders.push(childPath); else files.push(childPath);
        }
        return { files, folders };
    }

    read(message) {
        const location = this.location(message.path);
        const stat = this.stat(location);
        if (!stat || stat.isFolder) throw new HostFailure('missing', '“' + message.path + '” does not exist.');
        if (message.isSkippingCloudFiles && this.notDownloadedPaths.has(message.path)) return { isNotDownloaded: true };
        if (message.maximumBytes && stat.size > message.maximumBytes) return { isTooLarge: true };
        const bytes = fileSystem.readFileSync(location);
        const answer = { revision: revisionOf(bytes), stat };
        if (message.encoding === 'binary') answer.base64 = bytes.toString('base64');
        else answer.text = (bytes.subarray(0, 3).equals(byteOrderMark) ? bytes.subarray(3) : bytes).toString('utf8');
        return answer;
    }

    write(message) {
        const location = this.location(message.path);
        const exists = fileSystem.existsSync(location);
        let bytes;
        if (typeof message.text === 'string') {
            // A file that starts with a byte order mark keeps it, as in Graphite.
            const keepsByteOrderMark = exists && fileSystem.readFileSync(location).subarray(0, 3).equals(byteOrderMark) && !message.text.startsWith('\uFEFF');
            bytes = Buffer.concat([keepsByteOrderMark ? byteOrderMark : Buffer.alloc(0), Buffer.from(message.text, 'utf8')]);
        } else if (typeof message.base64 === 'string') {
            bytes = Buffer.from(message.base64, 'base64');
        } else {
            throw new HostFailure('invalidData', 'The plugin sent nothing to write to “' + message.path + '”.');
        }
        const expectation = message.expectation || { kind: 'replace' };
        if (expectation.kind === 'absent' && exists) throw new HostFailure('conflict', '“' + message.path + '” already exists.');
        if (expectation.kind === 'revision') {
            const current = exists ? revisionOf(fileSystem.readFileSync(location)) : null;
            if (!current || current.digest !== expectation.revision.digest || current.size !== expectation.revision.size) {
                throw new HostFailure('conflict', '“' + message.path + '” changed since it was read.');
            }
        }
        fileSystem.mkdirSync(path.dirname(location), { recursive: true });
        fileSystem.writeFileSync(location, bytes);
        return { revision: revisionOf(bytes), stat: this.stat(location) };
    }

    remove(message) {
        const location = this.location(message.path);
        const stat = this.stat(location);
        if (!stat) throw new HostFailure('missing', '“' + message.path + '” is no longer in the vault.');
        if (message.method === 'local' || message.method === 'vaultSetting') {
            const trashLocation = path.join(this.vaultFolder, '.trash', path.basename(location));
            fileSystem.mkdirSync(path.dirname(trashLocation), { recursive: true });
            fileSystem.renameSync(location, trashLocation);
            return { outcome: 'vaultTrash', trashPath: this.vaultPathOf(trashLocation) };
        }
        if (stat.isFolder && message.isRecursive === false && fileSystem.readdirSync(location).length > 0) throw new HostFailure('notEmpty', 'The folder is not empty.');
        fileSystem.rmSync(location, { recursive: true, force: true });
        return { outcome: message.method === 'system' ? 'systemTrash' : 'deleted' };
    }

    // The note editor, as Graphite's session would hold it.

    openNote(vaultPath, selectionAnchor, selectionHead) {
        const text = fileSystem.readFileSync(this.location(vaultPath), 'utf8');
        const snapshotIdentifier = 'snapshot-' + crypto.randomUUID();
        this.editorSessions.set(vaultPath, { text, snapshotIdentifier, appliedChanges: [] });
        return { path: vaultPath, snapshotIdentifier, text, selectionAnchor: selectionAnchor || 0, selectionHead: selectionHead === undefined ? selectionAnchor || 0 : selectionHead };
    }

    applyEditorChange(message) {
        const session = this.editorSessions.get(message.path);
        if (!session || session.snapshotIdentifier !== message.snapshotIdentifier) throw new HostFailure('conflict', 'The note is not open.');
        session.text = message.text;
        session.appliedChanges.push(message);
        return { snapshot: { path: message.path, snapshotIdentifier: session.snapshotIdentifier, text: session.text, selectionAnchor: message.selectionAnchor, selectionHead: message.selectionHead } };
    }

    notificationsOf(operation) {
        return this.notifications.filter((notification) => notification.operation === operation);
    }
}

/// Enough Markdown for tests of `MarkdownRenderer`: paragraphs, headings and code blocks.
function renderMarkdownForTests(markdown) {
    const escape = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const blocks = [];
    const fencePattern = /^```(\w*)\n([\s\S]*?)\n```$/gm;
    let lastEnd = 0;
    let match;
    const pushText = (text) => {
        for (const paragraph of text.split(/\n{2,}/)) {
            const trimmed = paragraph.trim();
            if (!trimmed) continue;
            const heading = /^(#{1,6})\s+(.*)$/.exec(trimmed);
            blocks.push(heading ? '<h' + heading[1].length + '>' + escape(heading[2]) + '</h' + heading[1].length + '>' : '<p>' + escape(trimmed) + '</p>');
        }
    };
    while ((match = fencePattern.exec(markdown)) !== null) {
        pushText(markdown.slice(lastEnd, match.index));
        blocks.push('<pre><code class="language-' + match[1] + '">' + escape(match[2]) + '\n</code></pre>');
        lastEnd = match.index + match[0].length;
    }
    pushText(markdown.slice(lastEnd));
    return blocks.join('\n');
}

module.exports = { TestVaultHost, HostFailure, revisionOf, isHidden };

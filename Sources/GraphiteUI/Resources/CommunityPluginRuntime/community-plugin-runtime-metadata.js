// Obsidian's `MetadataCache` for plugins: the headings, links, embeds, tags, sections,
// list items, blocks and frontmatter of every note, with Obsidian's positions (line,
// column, and offset in UTF-16 code units), and the vault's resolved and unresolved links.
// Notes are read once in the background and again when they change; only the metadata
// is kept, never the text. Notes a file provider has not downloaded are not read.
(function installRuntimeMetadata(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Events, TFile, normalizePath, parseLinktext, parseYaml, getFrontMatterInfo, stripHeading } = exportedApi;
    const hostBridge = runtime.hostBridge;

    /// Notes larger than this are not read for metadata, so one huge file cannot hold
    /// the background reading up or fill memory.
    const maximumIndexedNoteBytes = 4 * 1024 * 1024;
    /// How many notes are read at once while the cache fills.
    const concurrentNoteReads = 4;

    // MARK: Parsing one note

    function lineStartOffsets(text) {
        const offsets = [0];
        for (let offset = 0; offset < text.length; offset += 1) {
            if (text.charCodeAt(offset) === 10) offsets.push(offset + 1);
        }
        return offsets;
    }

    class NoteParser {
        constructor(text) {
            this.text = text;
            this.lineOffsets = lineStartOffsets(text);
            this.lines = text.split('\n').map((line) => line.replace(/\r$/, ''));
        }

        location(offset) {
            let low = 0;
            let high = this.lineOffsets.length - 1;
            while (low < high) {
                const middle = Math.ceil((low + high) / 2);
                if (this.lineOffsets[middle] <= offset) low = middle; else high = middle - 1;
            }
            return { line: low, col: offset - this.lineOffsets[low], offset };
        }

        position(startOffset, endOffset) {
            return { start: this.location(startOffset), end: this.location(endOffset) };
        }

        lineEndOffset(lineNumber) {
            return this.lineOffsets[lineNumber] + this.lines[lineNumber].length;
        }

        linePosition(firstLine, lastLine) {
            return this.position(this.lineOffsets[firstLine], this.lineEndOffset(lastLine));
        }

        parse() {
            const metadata = {};
            let bodyStartLine = 0;
            const frontmatterInformation = getFrontMatterInfo(this.text);
            if (frontmatterInformation.exists) {
                const closingLine = this.location(frontmatterInformation.to).line;
                bodyStartLine = closingLine + 1;
                metadata.frontmatterPosition = this.linePosition(0, closingLine);
                metadata.sections = [{ type: 'yaml', position: metadata.frontmatterPosition }];
                try {
                    const frontmatter = parseYaml(frontmatterInformation.frontmatter);
                    if (frontmatter && typeof frontmatter === 'object' && !Array.isArray(frontmatter)) {
                        metadata.frontmatter = frontmatter;
                        const frontmatterLinks = [];
                        collectFrontmatterLinks(frontmatter, '', frontmatterLinks);
                        if (frontmatterLinks.length > 0) metadata.frontmatterLinks = frontmatterLinks;
                    }
                } catch (error) {
                    // Obsidian keeps the position of frontmatter it cannot read, without values.
                }
            }
            this.parseBody(bodyStartLine, metadata);
            for (const key of ['links', 'embeds', 'tags', 'headings', 'sections', 'listItems', 'footnotes', 'footnoteRefs', 'referenceLinks']) {
                if (metadata[key] && metadata[key].length === 0) delete metadata[key];
            }
            if (metadata.blocks && Object.keys(metadata.blocks).length === 0) delete metadata.blocks;
            return metadata;
        }

        parseBody(startLine, metadata) {
            const sections = metadata.sections || (metadata.sections = []);
            const headings = metadata.headings = [];
            const listItems = metadata.listItems = [];
            const blocks = metadata.blocks = {};
            const inline = { links: metadata.links = [], embeds: metadata.embeds = [], tags: metadata.tags = [], footnoteRefs: metadata.footnoteRefs = [] };
            const footnotes = metadata.footnotes = [];
            const referenceLinks = metadata.referenceLinks = [];
            let currentSection = null;
            let fence = null;
            let isInMathBlock = false;
            let isInComment = false;
            const listParents = [];
            let listFirstLine = null;
            const endList = () => { listParents.length = 0; listFirstLine = null; };

            const closeSection = (lastLine) => {
                if (!currentSection) return;
                currentSection.position = this.linePosition(currentSection.firstLine, lastLine);
                const blockIdentifier = currentSection.blockIdentifier;
                const section = { type: currentSection.type, position: currentSection.position };
                if (blockIdentifier) {
                    section.id = blockIdentifier;
                    blocks[blockIdentifier.toLowerCase()] = { id: blockIdentifier, position: currentSection.position };
                }
                sections.push(section);
                currentSection = null;
            };
            const openSection = (type, lineNumber) => {
                closeSection(lineNumber - 1);
                currentSection = { type, firstLine: lineNumber, blockIdentifier: null };
            };

            for (let lineNumber = startLine; lineNumber < this.lines.length; lineNumber += 1) {
                const line = this.lines[lineNumber];
                const lineOffset = this.lineOffsets[lineNumber];

                if (fence) {
                    const closingFence = new RegExp('^\\s{0,3}' + fence.marker[0] + '{' + fence.marker.length + ',}\\s*$');
                    if (closingFence.test(line)) { fence = null; closeSection(lineNumber); }
                    continue;
                }
                if (isInMathBlock) {
                    if (/\$\$\s*$/.test(line)) { isInMathBlock = false; closeSection(lineNumber); }
                    continue;
                }
                if (isInComment) {
                    if (line.includes('%%')) { isInComment = false; closeSection(lineNumber); }
                    continue;
                }

                const fenceMatch = /^(\s{0,3})(`{3,}|~{3,})/.exec(line);
                if (fenceMatch) {
                    openSection('code', lineNumber);
                    fence = { marker: fenceMatch[2] };
                    continue;
                }
                if (/^\s{0,3}\$\$/.test(line)) {
                    openSection('math', lineNumber);
                    if (!/^\s{0,3}\$\$.*\$\$\s*$/.test(line) || line.trim() === '$$') isInMathBlock = true;
                    else closeSection(lineNumber);
                    continue;
                }
                if (/^\s{0,3}%%/.test(line)) {
                    openSection('comment', lineNumber);
                    if ((line.match(/%%/g) || []).length === 1) isInComment = true;
                    else closeSection(lineNumber);
                    continue;
                }
                if (line.trim() === '') {
                    closeSection(lineNumber - 1);
                    if (listFirstLine !== null && !this.continuesList(lineNumber)) endList();
                    continue;
                }

                const headingMatch = /^\s{0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$|^\s{0,3}(#{1,6})$/.exec(line);
                if (headingMatch) {
                    openSection('heading', lineNumber);
                    const level = (headingMatch[1] || headingMatch[3]).length;
                    const headingText = (headingMatch[2] || '').trim();
                    headings.push({ heading: headingText, level, position: this.linePosition(lineNumber, lineNumber) });
                    this.parseInline(line, lineOffset, inline);
                    closeSection(lineNumber);
                    endList();
                    continue;
                }

                const setextMatch = /^\s{0,3}(=+|-+)\s*$/.exec(line);
                if (setextMatch && currentSection && currentSection.type === 'paragraph' && currentSection.firstLine === lineNumber - 1) {
                    currentSection.type = 'heading';
                    const headingLine = lineNumber - 1;
                    headings.push({ heading: this.lines[headingLine].trim(), level: setextMatch[1][0] === '=' ? 1 : 2, position: this.linePosition(headingLine, lineNumber) });
                    closeSection(lineNumber);
                    continue;
                }

                if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) {
                    openSection('thematicBreak', lineNumber);
                    closeSection(lineNumber);
                    endList();
                    continue;
                }

                const footnoteMatch = /^\[\^([^\]\s]+)\]:\s?/.exec(line);
                if (footnoteMatch) {
                    openSection('footnoteDefinition', lineNumber);
                    footnotes.push({ id: footnoteMatch[1], position: this.linePosition(lineNumber, lineNumber) });
                    this.parseInline(line.slice(footnoteMatch[0].length), lineOffset + footnoteMatch[0].length, inline);
                    continue;
                }

                const referenceMatch = /^\s{0,3}\[([^\]^][^\]]*)\]:\s*(<[^>]*>|\S+)/.exec(line);
                if (referenceMatch && !(currentSection && currentSection.type === 'paragraph')) {
                    const destination = referenceMatch[2].replace(/^<|>$/g, '');
                    referenceLinks.push({ id: referenceMatch[1], link: destination, original: line.trim(), displayText: referenceMatch[1], position: this.linePosition(lineNumber, lineNumber) });
                    continue;
                }

                const listMatch = /^(\s*)([-*+]|\d{1,9}[.)])(\s+|$)(\[(.)\](?:\s|$))?/.exec(line);
                if (listMatch) {
                    if (!currentSection || currentSection.type !== 'list') openSection('list', lineNumber);
                    if (listParents.length === 0 && listFirstLine === null) listFirstLine = lineNumber;
                    const indentation = listMatch[1].replace(/\t/g, '    ').length;
                    while (listParents.length > 0 && listParents[listParents.length - 1].indentation >= indentation) listParents.pop();
                    // A top-level item's parent is minus the line of the list's first item.
                    const parent = listParents.length > 0 ? listParents[listParents.length - 1].line : -listFirstLine;
                    const listItem = { parent, position: this.linePosition(lineNumber, lineNumber) };
                    if (listMatch[4] !== undefined) listItem.task = listMatch[5];
                    const blockMatch = /\s\^([A-Za-z0-9-]+)\s*$/.exec(line);
                    if (blockMatch) {
                        listItem.id = blockMatch[1];
                        blocks[blockMatch[1].toLowerCase()] = { id: blockMatch[1], position: listItem.position };
                    }
                    listItems.push(listItem);
                    listParents.push({ indentation, line: lineNumber });
                    this.parseInline(line, lineOffset, inline);
                    continue;
                }
                if (currentSection && currentSection.type === 'list' && /^\s+\S/.test(line)) {
                    const lastItem = listItems[listItems.length - 1];
                    if (lastItem) lastItem.position = this.position(lastItem.position.start.offset, this.lineEndOffset(lineNumber));
                    this.parseInline(line, lineOffset, inline);
                    continue;
                }

                if (/^\s{0,3}>/.test(line)) {
                    if (!currentSection || (currentSection.type !== 'blockquote' && currentSection.type !== 'callout')) {
                        openSection(/^\s{0,3}>\s*\[![^\]]+\]/.test(line) ? 'callout' : 'blockquote', lineNumber);
                    }
                    this.parseInline(line, lineOffset, inline);
                    continue;
                }
                if (/^\s{0,3}\|/.test(line) || (currentSection && currentSection.type === 'table')) {
                    if (!currentSection || currentSection.type !== 'table') {
                        const nextLine = this.lines[lineNumber + 1] || '';
                        if (/^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(nextLine)) openSection('table', lineNumber);
                    }
                }
                if (/^\s{0,3}<[A-Za-z!/]/.test(line) && (!currentSection || currentSection.type === 'html')) {
                    if (!currentSection) openSection('html', lineNumber);
                    continue;
                }
                if (!currentSection || ['heading', 'list', 'blockquote', 'callout', 'thematicBreak', 'html'].includes(currentSection.type)) {
                    if (currentSection && currentSection.type === 'list' && !/^\s/.test(line)) {
                        // A lazy continuation line of the last list item.
                        const lastItem = listItems[listItems.length - 1];
                        if (lastItem) lastItem.position = this.position(lastItem.position.start.offset, this.lineEndOffset(lineNumber));
                        this.parseInline(line, lineOffset, inline);
                        continue;
                    }
                    openSection('paragraph', lineNumber);
                }
                this.parseInline(line, lineOffset, inline);
            }
            if (fence || isInMathBlock || isInComment) closeSection(this.lines.length - 1);
            else closeSection(this.lines.length - 1);
            // A paragraph's block identifier is the `^id` at the end of its last line.
            for (const section of sections) {
                if (section.id || !['paragraph', 'blockquote', 'callout', 'table', 'heading'].includes(section.type)) continue;
                const lastLine = this.lines[section.position.end.line];
                const blockMatch = /(?:^|\s)\^([A-Za-z0-9-]+)\s*$/.exec(lastLine);
                if (blockMatch) {
                    section.id = blockMatch[1];
                    blocks[blockMatch[1].toLowerCase()] = { id: blockMatch[1], position: section.position };
                }
            }
        }

        continuesList(blankLineNumber) {
            for (let lineNumber = blankLineNumber + 1; lineNumber < this.lines.length; lineNumber += 1) {
                const line = this.lines[lineNumber];
                if (line.trim() === '') continue;
                return /^(\s*)([-*+]|\d{1,9}[.)])(\s|$)/.test(line) || /^\s+\S/.test(line);
            }
            return false;
        }

        /// Links, embeds, tags and footnote references on one line, outside code and math.
        parseInline(line, lineOffset, inline) {
            const masked = maskCodeAndMath(line);
            const wikilinkPattern = /(!?)\[\[([^\]\n]+?)\]\]/g;
            let match;
            const linkRanges = [];
            while ((match = wikilinkPattern.exec(masked)) !== null) {
                const original = line.slice(match.index, match.index + match[0].length);
                const inner = line.slice(match.index + match[1].length + 2, match.index + match[0].length - 2);
                const pipePosition = inner.indexOf('|');
                const link = (pipePosition === -1 ? inner : inner.slice(0, pipePosition)).trim();
                const reference = { link, original, position: this.position(lineOffset + match.index, lineOffset + match.index + match[0].length) };
                if (pipePosition !== -1) reference.displayText = inner.slice(pipePosition + 1);
                else reference.displayText = link;
                (match[1] ? inline.embeds : inline.links).push(reference);
                linkRanges.push([match.index, match.index + match[0].length]);
            }
            const markdownLinkPattern = /(!?)\[((?:[^\]\\\n]|\\.)*)\]\(\s*(<[^>\n]*>|(?:[^()\s]|\([^()\s]*\))+)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g;
            while ((match = markdownLinkPattern.exec(masked)) !== null) {
                if (linkRanges.some((range) => match.index >= range[0] && match.index < range[1])) continue;
                let destination = match[3].replace(/^<|>$/g, '');
                if (/^[a-z][a-z0-9+.-]*:/i.test(destination)) continue;
                try { destination = decodeURIComponent(destination); } catch (error) { /* keep as written */ }
                const original = line.slice(match.index, match.index + match[0].length);
                const reference = { link: destination, original, displayText: match[2], position: this.position(lineOffset + match.index, lineOffset + match.index + match[0].length) };
                (match[1] ? inline.embeds : inline.links).push(reference);
                linkRanges.push([match.index, match.index + match[0].length]);
            }
            const tagPattern = /(^|[\s,;!?()[\]{}"'])#([^\s#!"$%&'()*+,.:;<=>?@^`{|}~[\]\\]+)/gu;
            while ((match = tagPattern.exec(masked)) !== null) {
                const tagStart = match.index + match[1].length;
                if (linkRanges.some((range) => tagStart >= range[0] && tagStart < range[1])) continue;
                const tagName = match[2];
                if (/^[0-9]+$/.test(tagName) || tagName.startsWith('/')) continue;
                inline.tags.push({ tag: '#' + tagName, position: this.position(lineOffset + tagStart, lineOffset + tagStart + 1 + tagName.length) });
            }
            const footnoteReferencePattern = /\[\^([^\]\s]+)\](?!:)/g;
            while ((match = footnoteReferencePattern.exec(masked)) !== null) {
                inline.footnoteRefs.push({ id: match[1], position: this.position(lineOffset + match.index, lineOffset + match.index + match[0].length) });
            }
        }
    }

    /// The line with code spans and inline math replaced by spaces, so their contents
    /// are never read as links or tags while every position stays where it was.
    function maskCodeAndMath(line) {
        let masked = line.replace(/(`+)([\s\S]*?[^`])\1(?!`)/g, (span) => ' '.repeat(span.length));
        masked = masked.replace(/(^|[^\\$])\$(?!\s)([^$\n]*?[^\s\\$])\$(?!\d)/g, (span, before) => before + ' '.repeat(span.length - before.length));
        masked = masked.replace(/%%[\s\S]*?%%/g, (span) => ' '.repeat(span.length));
        return masked;
    }

    function collectFrontmatterLinks(value, keyPath, frontmatterLinks) {
        if (typeof value === 'string') {
            const wikilinkPattern = /^\s*\[\[([^\]\n]+?)\]\]\s*$/.exec(value);
            if (wikilinkPattern) {
                const inner = wikilinkPattern[1];
                const pipePosition = inner.indexOf('|');
                const link = (pipePosition === -1 ? inner : inner.slice(0, pipePosition)).trim();
                frontmatterLinks.push({ key: keyPath, link, original: value.trim(), displayText: pipePosition === -1 ? link : inner.slice(pipePosition + 1) });
            }
            return;
        }
        if (Array.isArray(value)) {
            value.forEach((entry, entryPosition) => collectFrontmatterLinks(entry, keyPath + '.' + entryPosition, frontmatterLinks));
            return;
        }
        if (value && typeof value === 'object') {
            for (const key of Object.keys(value)) collectFrontmatterLinks(value[key], keyPath ? keyPath + '.' + key : key, frontmatterLinks);
        }
    }

    // MARK: The cache

    class MetadataCache extends Events {
        constructor(app) {
            super();
            this.app = app;
            this.vault = app.vault;
            this.metadataByPath = new Map();
            this.resolvedLinks = {};
            this.unresolvedLinks = {};
            this.filesByLowercasedName = new Map();
            this.isInitialReadComplete = false;
            this.resolutionTimer = null;
            this.readQueue = [];
            this.activeReadCount = 0;
        }

        // Obsidian's public API.

        getFileCache(file) {
            return file ? this.metadataByPath.get(file.path) || null : null;
        }
        getCache(path) {
            return this.metadataByPath.get(normalizePath(path)) || null;
        }
        /// The paths of every note read so far (undocumented, widely used).
        getCachedFiles() {
            return Array.from(this.metadataByPath.keys());
        }
        isUserIgnored() {
            return false;
        }
        fileToLinktext(file, sourcePath, isOmittingMarkdownExtension) {
            const isOmitting = isOmittingMarkdownExtension !== false;
            const linkPath = isOmitting && file.extension === 'md' ? file.path.slice(0, -3) : file.path;
            const linkName = isOmitting && file.extension === 'md' ? file.basename : file.name;
            const format = this.vault.getConfig('newLinkFormat') || 'shortest';
            if (format === 'absolute') return linkPath;
            if (format === 'relative') return relativeLinkPath(sourcePath || '', linkPath);
            const sameNamed = this.filesByLowercasedName.get(file.name.toLowerCase()) || [];
            return sameNamed.length <= 1 ? linkName : linkPath;
        }
        getFirstLinkpathDest(linkpath, sourcePath) {
            return this.resolveLinkpath(linkpath, sourcePath);
        }
        getLinkpathDest(linkpath, sourcePath) {
            const destination = this.resolveLinkpath(linkpath, sourcePath);
            return destination ? [destination] : [];
        }
        getTags() {
            const counts = {};
            for (const metadata of this.metadataByPath.values()) {
                for (const tag of exportedApi.getAllTags(metadata) || []) counts[tag] = (counts[tag] || 0) + 1;
            }
            return counts;
        }
        getBacklinksForFile(file) {
            const data = new Map();
            for (const [sourcePath, metadata] of this.metadataByPath) {
                const references = [].concat(metadata.links || [], metadata.embeds || [], metadata.frontmatterLinks || []);
                const linking = references.filter((reference) => this.resolveLinkpath(parseLinktext(reference.link).path, sourcePath) === file);
                if (linking.length > 0) data.set(sourcePath, linking);
            }
            return { data, keys: () => Array.from(data.keys()), get: (key) => data.get(key) || null, count: () => data.size };
        }
        getAllPropertyInfos() {
            const properties = {};
            for (const metadata of this.metadataByPath.values()) {
                for (const key of Object.keys(metadata.frontmatter || {})) {
                    const lowercasedKey = key.toLowerCase();
                    const information = properties[lowercasedKey] || (properties[lowercasedKey] = { name: key, type: propertyType(metadata.frontmatter[key]), occurrences: 0 });
                    information.occurrences += 1;
                }
            }
            return properties;
        }
        getFrontmatterPropertyValuesForKey(key) {
            const values = new Set();
            for (const metadata of this.metadataByPath.values()) {
                const value = metadata.frontmatter ? metadata.frontmatter[key] : undefined;
                if (value === undefined || value === null) continue;
                for (const entry of Array.isArray(value) ? value : [value]) values.add(String(entry));
            }
            return Array.from(values);
        }

        // Link resolution, as Obsidian does it: beside the note, then from the vault root,
        // then by name or the end of a path, ignoring case.

        resolveLinkpath(linkpath, sourcePath) {
            const target = normalizeLinkTarget(linkpath);
            if (target === '') return sourcePath ? this.vault.getFileByPath(sourcePath) : null;
            const sourceFolder = sourcePath && sourcePath.includes('/') ? sourcePath.slice(0, sourcePath.lastIndexOf('/')) : '';
            const candidates = [];
            if (target.startsWith('./') || target.startsWith('../')) candidates.push(joinRelative(sourceFolder, target));
            else {
                if (sourceFolder) candidates.push(sourceFolder + '/' + target);
                candidates.push(target);
            }
            for (const candidate of candidates) {
                const file = this.findFileIgnoringCase(candidate) || this.findFileIgnoringCase(candidate + '.md');
                if (file) return file;
            }
            const lowercasedTarget = target.toLowerCase();
            const lastComponent = lowercasedTarget.slice(lowercasedTarget.lastIndexOf('/') + 1);
            const sameNamed = (this.filesByLowercasedName.get(lastComponent) || []).concat(this.filesByLowercasedName.get(lastComponent + '.md') || []);
            const matching = sameNamed.filter((file) => {
                const lowercasedPath = file.path.toLowerCase();
                return lowercasedPath === lowercasedTarget || lowercasedPath === lowercasedTarget + '.md'
                    || lowercasedPath.endsWith('/' + lowercasedTarget) || lowercasedPath.endsWith('/' + lowercasedTarget + '.md');
            });
            if (matching.length === 0) return null;
            matching.sort((firstFile, secondFile) => firstFile.path.length - secondFile.path.length || (firstFile.path < secondFile.path ? -1 : 1));
            return matching[0];
        }

        findFileIgnoringCase(path) {
            const exact = this.vault.getFileByPath(path);
            if (exact) return exact;
            const lowercasedPath = path.toLowerCase();
            const name = lowercasedPath.slice(lowercasedPath.lastIndexOf('/') + 1);
            return (this.filesByLowercasedName.get(name) || []).find((file) => file.path.toLowerCase() === lowercasedPath) || null;
        }

        rebuildNameIndex() {
            this.filesByLowercasedName.clear();
            for (const file of this.vault.getFiles()) this.addToNameIndex(file);
        }
        addToNameIndex(file) {
            const key = file.name.toLowerCase();
            const files = this.filesByLowercasedName.get(key) || [];
            if (!files.includes(file)) files.push(file);
            this.filesByLowercasedName.set(key, files);
        }
        removeFromNameIndex(file, name) {
            const key = (name || file.name).toLowerCase();
            const files = (this.filesByLowercasedName.get(key) || []).filter((candidate) => candidate !== file);
            if (files.length > 0) this.filesByLowercasedName.set(key, files); else this.filesByLowercasedName.delete(key);
        }

        resolveLinksOf(sourcePath) {
            const metadata = this.metadataByPath.get(sourcePath);
            const resolved = {};
            const unresolved = {};
            if (metadata) {
                const references = [].concat(metadata.links || [], metadata.embeds || [], metadata.frontmatterLinks || []);
                for (const reference of references) {
                    const linkpath = parseLinktext(reference.link).path;
                    const destination = this.resolveLinkpath(linkpath, sourcePath);
                    if (destination) resolved[destination.path] = (resolved[destination.path] || 0) + 1;
                    else if (linkpath) unresolved[linkpath] = (unresolved[linkpath] || 0) + 1;
                }
            }
            this.resolvedLinks[sourcePath] = resolved;
            this.unresolvedLinks[sourcePath] = unresolved;
        }

        resolveAllLinks() {
            this.resolvedLinks = {};
            this.unresolvedLinks = {};
            for (const file of this.vault.getMarkdownFiles()) {
                this.resolveLinksOf(file.path);
                this.trigger('resolve', file);
            }
            this.trigger('resolved');
        }

        scheduleLinkResolution() {
            if (this.resolutionTimer !== null) globalScope.clearTimeout(this.resolutionTimer);
            this.resolutionTimer = globalScope.setTimeout(() => {
                this.resolutionTimer = null;
                if (this.isInitialReadComplete) this.resolveAllLinks();
            }, 200);
        }

        // Reading notes.

        /// Starts reading every note in the background; `resolved` fires when done.
        startInitialRead() {
            this.rebuildNameIndex();
            const notes = this.vault.getMarkdownFiles();
            if (notes.length === 0) {
                this.isInitialReadComplete = true;
                this.resolveAllLinks();
                return Promise.resolve();
            }
            return new Promise((resolve) => {
                let remaining = notes.length;
                const finishOne = () => {
                    remaining -= 1;
                    if (remaining === 0) {
                        this.isInitialReadComplete = true;
                        this.resolveAllLinks();
                        resolve();
                    }
                };
                for (const note of notes) this.enqueueRead(note, false, finishOne);
            });
        }

        enqueueRead(file, isChange, completion) {
            this.readQueue.push({ file, isChange, completion });
            this.pumpReadQueue();
        }

        pumpReadQueue() {
            while (this.activeReadCount < concurrentNoteReads && this.readQueue.length > 0) {
                const queued = this.readQueue.shift();
                this.activeReadCount += 1;
                this.readNote(queued.file, queued.isChange).catch((error) => console.warn('Graphite could not read “' + queued.file.path + '” for plugins.', error)).finally(() => {
                    this.activeReadCount -= 1;
                    if (queued.completion) queued.completion();
                    this.pumpReadQueue();
                });
            }
        }

        async readNote(file, isChange) {
            if (file.extension !== 'md' || this.vault.getFileByPath(file.path) !== file) return;
            const response = await hostBridge.send('vault.read', { path: file.path, encoding: 'text', isSkippingCloudFiles: true, maximumBytes: maximumIndexedNoteBytes });
            if (response.isNotDownloaded || response.isTooLarge || typeof response.text !== 'string') return;
            if (this.vault.getFileByPath(file.path) !== file) return;
            const metadata = new NoteParser(response.text).parse();
            this.metadataByPath.set(file.path, metadata);
            if (isChange) {
                this.resolveLinksOf(file.path);
                this.trigger('changed', file, response.text, metadata);
                this.trigger('resolve', file);
                this.trigger('resolved');
            }
        }

        // Following the vault.

        observeVault() {
            this.vault.on('create', (abstractFile) => {
                if (!(abstractFile instanceof TFile)) return;
                this.addToNameIndex(abstractFile);
                if (abstractFile.extension === 'md') this.enqueueRead(abstractFile, true);
                this.scheduleLinkResolution();
            });
            this.vault.on('modify', (abstractFile) => {
                if (abstractFile instanceof TFile && abstractFile.extension === 'md') this.enqueueRead(abstractFile, true);
            });
            this.vault.on('delete', (abstractFile) => {
                if (!(abstractFile instanceof TFile)) return;
                this.removeFromNameIndex(abstractFile);
                const previousMetadata = this.metadataByPath.get(abstractFile.path) || null;
                this.metadataByPath.delete(abstractFile.path);
                delete this.resolvedLinks[abstractFile.path];
                delete this.unresolvedLinks[abstractFile.path];
                this.trigger('deleted', abstractFile, previousMetadata);
                this.scheduleLinkResolution();
            });
            this.vault.on('rename', (abstractFile, oldPath) => {
                if (!(abstractFile instanceof TFile)) return;
                this.removeFromNameIndex(abstractFile, oldPath.slice(oldPath.lastIndexOf('/') + 1));
                this.addToNameIndex(abstractFile);
                const metadata = this.metadataByPath.get(oldPath);
                if (metadata) {
                    this.metadataByPath.delete(oldPath);
                    this.metadataByPath.set(abstractFile.path, metadata);
                }
                delete this.resolvedLinks[oldPath];
                delete this.unresolvedLinks[oldPath];
                this.scheduleLinkResolution();
            });
        }
    }

    function normalizeLinkTarget(linkpath) {
        let target = String(linkpath || '').trim();
        if (target.startsWith('/')) target = target.replace(/^\/+/, '');
        return target.normalize('NFC');
    }

    function joinRelative(folder, relativePath) {
        const components = folder ? folder.split('/') : [];
        for (const component of relativePath.split('/')) {
            if (component === '..') components.pop();
            else if (component !== '.' && component !== '') components.push(component);
        }
        return components.join('/');
    }

    function relativeLinkPath(sourcePath, targetPath) {
        const sourceComponents = sourcePath.split('/').slice(0, -1);
        const targetComponents = targetPath.split('/');
        let sharedCount = 0;
        while (sharedCount < sourceComponents.length && sharedCount < targetComponents.length - 1 && sourceComponents[sharedCount] === targetComponents[sharedCount]) sharedCount += 1;
        const upward = sourceComponents.slice(sharedCount).map(() => '..');
        return upward.concat(targetComponents.slice(sharedCount)).join('/');
    }

    function propertyType(value) {
        if (Array.isArray(value)) return value.some((entry) => typeof entry === 'string' && entry.startsWith('#')) ? 'tags' : 'multitext';
        if (typeof value === 'number') return 'number';
        if (typeof value === 'boolean') return 'checkbox';
        if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) return 'date';
        if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) return 'datetime';
        return 'text';
    }

    /// Obsidian's `resolveSubpath`: the heading or block a `#subpath` names in a note.
    function resolveSubpath(cache, subpath) {
        if (!cache || !subpath) return null;
        const parts = subpath.replace(/^#/, '').split('#').filter((part) => part.length > 0);
        if (parts.length === 0) return null;
        if (parts[0].startsWith('^')) {
            const blockIdentifier = parts[0].slice(1).toLowerCase();
            const block = cache.blocks ? cache.blocks[blockIdentifier] : null;
            const listItem = (cache.listItems || []).find((item) => item.id && item.id.toLowerCase() === blockIdentifier);
            return block ? { type: 'block', block, list: listItem || null, start: block.position.start, end: block.position.end } : null;
        }
        const headings = cache.headings || [];
        let searchStart = 0;
        let found = null;
        for (const part of parts) {
            const wanted = stripHeading(part).toLowerCase();
            const position = headings.findIndex((heading, headingPosition) => headingPosition >= searchStart && stripHeading(heading.heading).toLowerCase() === wanted);
            if (position === -1) return null;
            found = position;
            searchStart = position + 1;
        }
        const current = headings[found];
        const next = headings.slice(found + 1).find((heading) => heading.level <= current.level) || null;
        return { type: 'heading', current, next, start: current.position.start, end: next ? next.position.start : null };
    }

    function iterateRefs(references, callback) {
        for (const reference of references || []) { if (callback(reference)) return true; }
        return false;
    }

    function iterateCacheRefs(cache, callback) {
        if (!cache) return false;
        return iterateRefs(cache.links, callback) || iterateRefs(cache.embeds, callback) || iterateRefs(cache.frontmatterLinks, callback);
    }

    Object.assign(exportedApi, { MetadataCache, resolveSubpath, iterateRefs, iterateCacheRefs });
    runtime.NoteParser = NoteParser;
})(globalThis);

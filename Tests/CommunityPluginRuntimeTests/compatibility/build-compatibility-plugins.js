// Builds real Obsidian community plugins from their sources at fixed commits, the way
// their authors build release bundles, for the compatibility tests. Each plugin is cloned
// into a cache folder, its own dependencies are installed with its own package manager,
// and its own build runs; `main.js`, `manifest.json` and `styles.css` are then copied to
// `compatibility/built/<plugin id>/`. Nothing built is committed.
//
// A plugin's entry in compatibility-plugins.json can list `filesBeforeBuilding`, files its
// README asks a developer to create before building (name → contents).
//
// Usage: node compatibility/build-compatibility-plugins.js [cache folder]
'use strict';

const fileSystem = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');

const compatibilityPlugins = require('./compatibility-plugins.json');
const requestedCacheFolder = path.resolve(process.argv[2] || path.join(os.tmpdir(), 'graphite-compatibility-plugin-sources'));
const builtFolder = path.join(__dirname, 'built');

function run(command, commandArguments, workingFolder) {
    return execFileSync(command, commandArguments, { cwd: workingFolder, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 15 * 60 * 1000 });
}

/// Installs with the plugin's own package manager and lockfile, so the build uses the
/// versions its author built with: newer releases within package.json's ranges can break an
/// old build (picomatch 2.3.2 no longer reads the pattern Rollup's TypeScript plugin 8 uses to
/// find source files). When that fails (yarn's and pnpm's lockfiles name their own hosts),
/// npm resolves the dependency ranges from package.json instead.
function installDependencies(sourceFolder) {
    try {
        if (fileSystem.existsSync(path.join(sourceFolder, 'pnpm-lock.yaml'))) { run('npx', ['--yes', 'pnpm@10', 'install', '--no-frozen-lockfile'], sourceFolder); return; }
        if (fileSystem.existsSync(path.join(sourceFolder, 'yarn.lock'))) { run('npx', ['--yes', 'yarn@1', 'install', '--ignore-engines'], sourceFolder); return; }
        if (fileSystem.existsSync(path.join(sourceFolder, 'package-lock.json'))) { run('npm', ['ci', '--no-audit', '--no-fund', '--legacy-peer-deps'], sourceFolder); return; }
    } catch (error) {
        console.warn('  the plugin\'s package manager failed; installing with npm from package.json');
    }
    run('npm', ['install', '--no-audit', '--no-fund', '--legacy-peer-deps', '--no-package-lock'], sourceFolder);
}

function build(sourceFolder, plugin) {
    for (const buildCommand of plugin.buildCommands) {
        try {
            run(buildCommand[0], buildCommand.slice(1), sourceFolder);
            return;
        } catch (error) {
            console.warn('  ' + buildCommand.join(' ') + ' failed: ' + String(error.stderr || error.message).split('\n').slice(-5).join(' | '));
        }
    }
    throw new Error('Every build command failed.');
}

function findBuiltFile(sourceFolder, plugin, fileName) {
    for (const candidate of (plugin.outputFolders || ['.']).map((folder) => path.join(sourceFolder, folder, fileName))) {
        if (fileSystem.existsSync(candidate)) return candidate;
    }
    return null;
}

/// A plugin built from the same commit before is not built again.
function isAlreadyBuilt(plugin) {
    if (!fileSystem.existsSync(builtFolder)) return false;
    return fileSystem.readdirSync(builtFolder).some((folderName) => {
        const sourceDescription = path.join(builtFolder, folderName, 'source.json');
        if (!fileSystem.existsSync(sourceDescription)) return false;
        const source = JSON.parse(fileSystem.readFileSync(sourceDescription, 'utf8'));
        return source.repository === plugin.repository && source.commit === plugin.commit;
    });
}

fileSystem.mkdirSync(requestedCacheFolder, { recursive: true });
// Plugins build in the folder's real path. macOS's temporary folder is behind a symbolic link
// (/var is /private/var), and Rollup's TypeScript plugin, which matches source files against
// the working folder's path, would then skip every one of them. A cache folder whose path has
// a hidden component (`~/.cache`) fails the same way, so the default is the temporary folder.
const cacheFolder = fileSystem.realpathSync(requestedCacheFolder);
fileSystem.mkdirSync(builtFolder, { recursive: true });
const report = [];
for (const plugin of compatibilityPlugins) {
    const sourceFolder = path.join(cacheFolder, plugin.repository.replace('/', '__'));
    console.log(plugin.repository + ' at ' + plugin.commit);
    try {
        if (isAlreadyBuilt(plugin)) {
            report.push({ repository: plugin.repository, isBuilt: true, isReused: true });
            console.log('  already built');
            continue;
        }
        if (!fileSystem.existsSync(sourceFolder)) {
            run('git', ['clone', '--quiet', 'https://github.com/' + plugin.repository + '.git', sourceFolder], cacheFolder);
        }
        run('git', ['fetch', '--quiet', '--depth', '1', 'origin', plugin.commit], sourceFolder);
        run('git', ['checkout', '--quiet', plugin.commit], sourceFolder);
        installDependencies(sourceFolder);
        for (const [fileName, contents] of Object.entries(plugin.filesBeforeBuilding || {})) {
            fileSystem.writeFileSync(path.join(sourceFolder, fileName), contents);
        }
        build(sourceFolder, plugin);
        const mainScript = findBuiltFile(sourceFolder, plugin, 'main.js');
        const manifestFile = findBuiltFile(sourceFolder, plugin, 'manifest.json') || path.join(sourceFolder, 'manifest.json');
        if (!mainScript) throw new Error('The build made no main.js.');
        const manifest = JSON.parse(fileSystem.readFileSync(manifestFile, 'utf8'));
        const destination = path.join(builtFolder, manifest.id);
        fileSystem.mkdirSync(destination, { recursive: true });
        fileSystem.copyFileSync(mainScript, path.join(destination, 'main.js'));
        fileSystem.copyFileSync(manifestFile, path.join(destination, 'manifest.json'));
        const styles = findBuiltFile(sourceFolder, plugin, 'styles.css');
        if (styles) fileSystem.copyFileSync(styles, path.join(destination, 'styles.css'));
        fileSystem.writeFileSync(path.join(destination, 'source.json'), JSON.stringify({ repository: plugin.repository, commit: plugin.commit }, null, 2));
        report.push({ repository: plugin.repository, pluginIdentifier: manifest.id, isBuilt: true });
        console.log('  built ' + manifest.id);
    } catch (error) {
        report.push({ repository: plugin.repository, isBuilt: false, reason: String(error.message).split('\n')[0] });
        console.warn('  not built: ' + String(error.message).split('\n')[0]);
    }
}
fileSystem.writeFileSync(path.join(builtFolder, 'build-report.json'), JSON.stringify(report, null, 2));

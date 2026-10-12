// Connects the runtime to Graphite inside its web view. The message handler answers each
// message (`WKScriptMessageHandlerWithReply`), so `postMessage` returns a promise of the
// reply. Outside the app (the Node tests), the test host sets the transport instead.
(function connectToGraphite(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const messageHandlers = globalScope.webkit && globalScope.webkit.messageHandlers;
    const graphiteHandler = messageHandlers && messageHandlers.graphitePlugins;
    if (!graphiteHandler) return;
    // Graphite answers vault reads and listings as JSON text, parsed here rather than on the
    // app's main thread; other answers arrive as objects.
    runtime.hostBridge.transport = (message) => graphiteHandler.postMessage(message).then((reply) => (typeof reply === 'string' ? JSON.parse(reply) : reply));

    // The clipboard, which WebKit refuses the hidden plugins' page (no gesture reaches it):
    // plugins read and write text through Graphite, as they do on Obsidian mobile.
    const clipboard = globalScope.navigator.clipboard;
    if (clipboard) {
        const readText = async () => (await runtime.hostBridge.send('clipboard.readText', {})).text || '';
        const writeText = async (text) => { await runtime.hostBridge.send('clipboard.writeText', { text: String(text) }); };
        try {
            Object.defineProperty(clipboard, 'readText', { value: readText, configurable: true });
            Object.defineProperty(clipboard, 'writeText', { value: writeText, configurable: true });
        } catch (error) {
            console.warn('Graphite could not give plugins the clipboard.', error);
        }
    }

    // Web and mail links plugins open with `window.open` (Smart Connections' and Admonition's
    // links, Permalink Opener) go to the browser or Mail, as Obsidian opens them; WebKit opens
    // no windows of its own for the runtime's page.
    globalScope.open = function openForPlugin(address) {
        let destination = null;
        try { destination = new URL(String(address), globalScope.location.href); } catch (error) { return null; }
        if (['http:', 'https:', 'mailto:'].includes(destination.protocol)) {
            runtime.hostBridge.notify('workspace.openExternalLink', { address: destination.href });
        } else {
            console.warn('Graphite opens only web and mail links for plugins: ' + destination.href);
        }
        return null;
    };

    // Plugin errors that nothing caught reach Graphite's log of the plugin's problems.
    globalScope.addEventListener('error', (event) => {
        runtime.hostBridge.notify('plugin.failure', {
            pluginIdentifier: runtime.pluginIdentifierOfSource(event.filename) || runtime.pluginIdentifierInStack(event.error && event.error.stack) || runtime.callingPluginIdentifier(),
            message: event.message || 'An error nothing handled.',
        });
    });
    globalScope.addEventListener('unhandledrejection', (event) => {
        const reason = event.reason;
        const stack = reason && reason.stack ? String(reason.stack) : '';
        runtime.hostBridge.notify('plugin.failure', {
            pluginIdentifier: runtime.pluginIdentifierInStack(stack),
            message: reason && reason.message ? reason.message : String(reason),
        });
    });
})(globalThis);

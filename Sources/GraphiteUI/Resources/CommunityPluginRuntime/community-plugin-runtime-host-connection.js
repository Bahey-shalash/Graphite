// Connects the runtime to Graphite inside its web view. The message handler answers each
// message (`WKScriptMessageHandlerWithReply`), so `postMessage` returns a promise of the
// reply. Outside the app (the Node tests), the test host sets the transport instead.
(function connectToGraphite(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const messageHandlers = globalScope.webkit && globalScope.webkit.messageHandlers;
    const graphiteHandler = messageHandlers && messageHandlers.graphitePlugins;
    if (!graphiteHandler) return;
    runtime.hostBridge.transport = (message) => graphiteHandler.postMessage(message);

    // Plugin errors that nothing caught reach Graphite's log of the plugin's problems.
    globalScope.addEventListener('error', (event) => {
        runtime.hostBridge.notify('plugin.failure', {
            pluginIdentifier: /plugin:([^/\s:)]+)\//.exec(event.filename || '') ? /plugin:([^/\s:)]+)\//.exec(event.filename)[1] : runtime.callingPluginIdentifier(),
            message: event.message || 'An error nothing handled.',
        });
    });
    globalScope.addEventListener('unhandledrejection', (event) => {
        const reason = event.reason;
        const stack = reason && reason.stack ? String(reason.stack) : '';
        const match = /plugin:([^/\s:)]+)\//.exec(stack);
        runtime.hostBridge.notify('plugin.failure', {
            pluginIdentifier: match ? match[1] : null,
            message: reason && reason.message ? reason.message : String(reason),
        });
    });
})(globalThis);

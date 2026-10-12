import * as XMLDOM from '@xmldom/xmldom';
import XPath from 'wicked-good-xpath';

// JavaScriptCore has neither a browser DOM nor Node I/O. Supply only the XML
// facilities SRE requires, without adding file, URL, script, or network loaders.
const xpathWindow = { document: {}, XPathResult: {} };
XPath.install(xpathWindow);
xpathWindow.document.XPathResult = xpathWindow.XPathResult;
export const SystemExternal = {
  windowSupported: false,
  documentSupported: false,
  xmldom: XMLDOM,
  document: new XMLDOM.DOMImplementation().createDocument(null, null),
  xpath: xpathWindow.document,
  fs: null,
  jsonPath: '',
  url: '',
  WGXpath: '',
  wgxpath: null,
  mathmapsIePath: ''
};
export default SystemExternal;

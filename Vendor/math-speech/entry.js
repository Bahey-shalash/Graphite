import { mathjax } from '@mathjax/src/js/mathjax.js';
import { TeX } from '@mathjax/src/js/input/tex.js';
import { liteAdaptor } from '@mathjax/src/js/adaptors/liteAdaptor.js';
import { RegisterHTMLHandler } from '@mathjax/src/js/handlers/html.js';
import { SerializedMmlVisitor } from '@mathjax/src/js/core/MmlTree/SerializedMmlVisitor.js';
import { STATE } from '@mathjax/src/js/core/MathItem.js';
import '@mathjax/src/js/input/tex/ams/AmsConfiguration.js';
import '@mathjax/src/js/input/tex/boldsymbol/BoldsymbolConfiguration.js';
import '@mathjax/src/js/input/tex/color/ColorConfiguration.js';
import { setup } from 'speech-rule-engine/js/common/engine_setup.js';
import { Engine } from 'speech-rule-engine/js/common/engine.js';
import { process as processExpression } from 'speech-rule-engine/js/common/processor_factory.js';
import baseRules from 'speech-rule-engine/lib/mathmaps/base.json';
import englishRules from 'speech-rule-engine/lib/mathmaps/en.json';

RegisterHTMLHandler(liteAdaptor());
const visitor = new SerializedMmlVisitor();
const engine = Engine.getInstance();
engine.init = false;
export let isReady = false;
const rules = { base: baseRules, en: englishRules };
setup({ locale: 'en', domain: 'clearspeak', style: 'default', markup: 'none',
        custom: locale => Promise.resolve(rules[locale] || {}) }).then(() => { isReady = true; });

function hasSafeSourceDepth(source) {
  let groupDepth = 0;
  let delimiterDepth = 0;
  for (let position = 0; position < source.length; position++) {
    const character = source[position];
    if (character === '%') {
      while (position < source.length && source[position] !== '\n' && source[position] !== '\r') position++;
    } else if (character === '\\') {
      const start = ++position;
      while (position < source.length && /[a-zA-Z]/.test(source[position])) position++;
      const command = source.slice(start, position);
      if (command === 'left') delimiterDepth++;
      if (command === 'right') delimiterDepth--;
      if (command.length > 0) position--;
      if (delimiterDepth < 0 || delimiterDepth > 32) return false;
    } else if (character === '{') {
      if (++groupDepth > 32) return false;
    } else if (character === '}') {
      if (--groupDepth < 0) return false;
    }
  }
  return groupDepth === 0 && delimiterDepth === 0;
}

function hasSafeTreeSize(expression) {
  const pending = [{ node: expression, depth: 0 }];
  let nodeCount = 0;
  while (pending.length > 0) {
    const { node, depth } = pending.pop();
    if (++nodeCount > 4096 || depth > 64) return false;
    for (const child of node.childNodes || []) pending.push({ node: child, depth: depth + 1 });
  }
  return true;
}

export function speech(source, detailed = true) {
  if (!isReady || typeof source !== 'string' || source.length > 8192 || !hasSafeSourceDepth(source)) return null;
  try {
    // A fresh parser isolates equation labels and user definitions across requests.
    const input = new TeX({ packages: ['base', 'ams', 'boldsymbol', 'color'], maxBuffer: 8192, maxMacros: 256,
      formatError: (_parser, error) => { throw error; } });
    const document = mathjax.document('', { InputJax: input });
    const expression = document.convert(source, { display: true, end: STATE.COMPILED });
    if (!hasSafeTreeSize(expression)) return null;
    const mathml = visitor.visitTree(expression);
    if (mathml.length > 65536 || mathml.includes('<merror')) return null;
    engine.domain = detailed ? 'mathspeak' : 'clearspeak';
    engine.style = 'default';
    engine.setDynamicCstr();
    const description = processExpression('speech', mathml);
    return typeof description === 'string' && description.length > 0 && description.length <= 32768 ? description : null;
  } catch (_) { return null; }
}

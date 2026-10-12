import * as esbuild from 'esbuild';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { copyFile, writeFile } from 'node:fs/promises';

const buildDirectory = dirname(fileURLToPath(import.meta.url));
const resourceDirectory = resolve(buildDirectory, '../../Sources/GraphiteApple/Resources/MathSpeech');
const build = await esbuild.build({
  absWorkingDir: buildDirectory,
  entryPoints: ['entry.js'], bundle: true, platform: 'browser', format: 'iife', globalName: 'GraphiteMathSpeech',
  define: { global: 'globalThis' }, outfile: resolve(resourceDirectory, 'math-speech.js'),
  minify: true, legalComments: 'eof', metafile: true,
  plugins: [{ name: 'offline-speech-environment', setup(configuration) {
    configuration.onResolve({ filter: /system_external\.js$/ }, dependency => {
      if (dependency.importer.includes('speech-rule-engine')) return { path: resolve(buildDirectory, 'system-external.js') };
    });
  }}]
});
await writeFile(resolve(buildDirectory, 'bundle-inputs.json'), JSON.stringify(Object.keys(build.metafile.inputs).sort(), null, 2) + '\n');
for (const [packageName, licenseName] of [['@mathjax/src', 'MathJax-LICENSE'], ['speech-rule-engine', 'SpeechRuleEngine-LICENSE'],
                                        ['@xmldom/xmldom', 'XMLDOM-LICENSE'], ['wicked-good-xpath', 'WickedGoodXPath-LICENSE']]) {
  await copyFile(resolve(buildDirectory, 'node_modules', packageName, 'LICENSE'), resolve(resourceDirectory, licenseName));
}

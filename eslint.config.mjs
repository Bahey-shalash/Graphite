// ESLint flat configuration for Graphite's own plugin-runtime scripts (Docs/solid/rewrite-foundations.md section 12.5 step 6).
//
// It lints Sources/GraphiteUI/Resources/CommunityPluginRuntime and never Vendor/ (minified libraries). It imports
// nothing, so it runs wherever ESLint 9.24 or newer is installed (CI installs it; see .github/workflows/ci.yml).
// The scripts are classic browser scripts, each one an immediately invoked function, so `sourceType` is "script" and a
// bare browser global is an error: a script reaches the page through `globalScope`, as the existing ones do.
//
// Existing violations are recorded by ESLint's bulk suppressions in scripts/eslint-suppressions.json, which the first CI run
// writes (`eslint --suppress-all --suppressions-location scripts/eslint-suppressions.json`); after that only new
// violations fail, and `--prune-suppressions` lowers the file as they are fixed.

const runtimeFolder = "Sources/GraphiteUI/Resources/CommunityPluginRuntime";

export default [
  {
    ignores: [`${runtimeFolder}/Vendor/**`, "**/node_modules/**"],
  },
  {
    files: [`${runtimeFolder}/**/*.js`],
    linterOptions: {
      reportUnusedDisableDirectives: "error",
    },
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: {
        // Bare browser globals the runtime uses today (found by resolving each identifier against lib.dom).
        console: "readonly",
        URL: "readonly",
        TextEncoder: "readonly",
        TextDecoder: "readonly",
        CSS: "readonly",
        MutationObserver: "readonly",
        // Defined on the page by community-plugin-dom-extensions.js, which loads first (Obsidian's DOM helpers).
        createDiv: "readonly",
        createSpan: "readonly",
      },
    },
    rules: {
      // Correctness (the ESLint recommended set, written out because the config imports nothing).
      "no-undef": "error",
      "no-unused-vars": ["error", { args: "none", caughtErrors: "none" }],
      "no-redeclare": "error",
      "no-dupe-keys": "error",
      "no-dupe-class-members": "error",
      "no-dupe-else-if": "error",
      "no-duplicate-case": "error",
      "no-unreachable": "error",
      "no-empty": ["error", { allowEmptyCatch: true }],
      "no-self-assign": "error",
      "no-fallthrough": "error",
      "no-unsafe-finally": "error",
      "no-cond-assign": "error",
      "no-const-assign": "error",
      "no-constant-condition": ["error", { checkLoops: false }],
      "no-shadow-restricted-names": "error",
      "no-prototype-builtins": "error",
      "no-case-declarations": "error",
      "no-sparse-arrays": "error",
      "no-unsafe-negation": "error",
      "no-unsafe-optional-chaining": "error",
      "no-useless-escape": "error",
      "no-empty-pattern": "error",
      "no-extra-boolean-cast": "error",
      "getter-return": "error",
      "no-setter-return": "error",
      "use-isnan": "error",
      "valid-typeof": "error",
      // Style that keeps scripts reviewable.
      eqeqeq: ["error", "always", { null: "ignore" }],
      "no-var": "error",
      "prefer-const": "error",
      // The architecture rules of the plugin runtime (FR-16, FR-25, FR-57; SRP 19, OCP 12, DIP 16).
      "no-restricted-syntax": [
        "error",
        {
          selector: "CallExpression[callee.object.name='Object'][callee.property.name='assign'][arguments.0.property.name=/[mM]essageHandlers$/]",
          message: "FR-25: add handlers through one registration call; never copy into another file's handler table.",
        },
        {
          selector: "CallExpression[callee.object.name='Object'][callee.property.name='assign'][arguments.0.name=/[mM]essageHandlers$/]",
          message: "FR-25: add handlers through one registration call; never copy into another file's handler table.",
        },
        {
          selector: "AssignmentExpression[left.type='MemberExpression'][left.object.property.name=/[mM]essageHandlers$/]",
          message: "FR-25: add handlers through one registration call; never assign into another file's handler table.",
        },
        {
          selector: "AssignmentExpression[left.type='MemberExpression'][left.object.property.name='prototype']",
          message: "FR-57: a page-wide patch of a prototype is named and scoped in one patch file, never made by a feature file.",
        },
        {
          selector: "AssignmentExpression[left.type='MemberExpression'][left.object.name='runtime']",
          message: "FR-16: a runtime file owns its fields in its own class; it does not register itself by assigning into the global runtime.",
        },
      ],
    },
  },
];

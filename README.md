# Graphite

Graphite is a native Apple Pencil-first knowledge and study app for ordinary Obsidian-compatible folders. Markdown, PDFs, images, and recordings remain usable outside the app. [OBJECTIVE.md](OBJECTIVE.md) defines the product and storage contracts. [RULES.md](RULES.md) defines the engineering standard.

## Following the SOLID standard

Last reviewed: 2026-09-30, against the current working tree, including uncommitted code.

**Overall: partially followed.** The module boundaries, value types, actor ownership, and focused adapters provide a sound foundation. Broad workspace responsibilities and direct dependencies on shared mutable services are the largest remaining gaps. Full compliance is not established.

| Principle | Assessment | What follows the rule | What still needs work |
| --- | --- | --- | --- |
| Single responsibility | Partial | Core, Index, Apple adapters, and UI have separate module responsibilities. Attachment policy and atomic writes have dedicated components. | `WorkspaceModel` combines vault lifecycle, indexing/search, document creation, drawing/attachment publication, recording destinations, and external changes. Splitting its extensions across files does not separate ownership. |
| Open/closed | Partial | `DocumentKind` centralizes classification. Bases providers and video capture have real substitution boundaries. | Adding document kinds requires changes to classification, loading, and rendering. Templates and drawing formats still rely on enum switches. Keep extension points focused when adding actual capabilities. |
| Liskov substitution | Partial; validation incomplete | Conflict and video adapters declare safety/lifecycle contracts. Tests exercise local file versions and synthetic capture through production writing code. | The conflict test store has weaker coordination-failure handling than production. Bases lookup failures require a check outside the provider interface. Real camera and file-provider behavior remains unverified by those tests. |
| Interface segregation | Partial | Bases lookups, editor retention, and PDF canvas queries use small interfaces. | Navigation views receive the broad workspace model. Document sessions receive a store that also exposes settings, moves, and deletion. Conflict discovery shares an interface with replacement/removal operations. |
| Dependency inversion | Partial; substantial UI gaps | Core has no dependency on the UI or adapter modules. Evaluation/capture accept providers, and sessions receive storage dependencies. | Workspace constructs several services directly. Pencil tools, embedded PDF sessions, and drawing drafts are accessed through shared mutable instances. Some persistence uses `UserDefaults.standard` directly. |

The [detailed SOLID tracker](Docs/SOLID.md) links these findings to source and tests, explains the contract limitations, and records completion criteria. Concrete types and enum switches are judged by their actual consumers and extension needs. The standard does not require a protocol per class or speculative infrastructure.

## Prioritized remaining work

1. **High:** align conflict test-adapter failure handling with production so tests cannot report success or resolve a version after a failed operation.
2. **High:** inject workspace and shared Pencil/PDF/draft services at composition boundaries, preserving intentional sharing, retained edits, and vault-switch cleanup.
3. **Medium:** give coherent workspace workflows separate ownership as those areas change, and narrow navigation, discovery, and persistence capabilities.
4. **Medium:** include Bases lookup failures in the provider/evaluation contract and compare implementations with shared contract fixtures.
5. **Medium:** consolidate document/template/format dispatch when real extension work needs it, without adding a speculative plugin registry.
6. **Validation:** record physical camera and real file-provider lifecycle checks alongside synthetic/local evidence.

All items remain open. Preserve ordinary files, coordinated writes, recoverable work, and native undo throughout this work.

## Evidence and implementation status

This update reviewed source and existing test assertions. It did not run builds, tests, simulator interactions, or physical-device checks. The assessment covers the reviewed architectural boundaries, not every line of the repository, and makes no fresh passing-test or numerical compliance claim.

- [Architecture](Docs/Architecture.md): module direction, ownership, storage, and technical risks.
- [Implementation coverage](Docs/Coverage.md): implemented behavior, dated validation, and incomplete or unverified work.
- [SOLID compliance tracker](Docs/SOLID.md): supporting source references, contract gaps, and completion evidence.
- [Community plugins](Docs/Community-plugins.md): how Graphite runs Obsidian community plugins, what works, what does not yet, and how it was checked.

Update this README and the detailed tracker when responsibilities, dependency boundaries, or contract evidence change. Feature completeness and test counts alone do not establish SOLID compliance.

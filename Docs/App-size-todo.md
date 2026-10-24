# App size: TODO

Created: 2026-10-24. Issue: [#105](https://github.com/Graphite-Note/Graphite/issues/105).

Status: main is over its size budget on both platforms, so `scripts/archive-for-testflight.sh` stops before the next upload. Nothing below is done.

## Request

The owner, 2026-10-21: Graphite stays a small, light core; extras are downloads, and a feature costs nothing while it is off. `scripts/app-size-budget.json` holds the sizes of builds 20261022.0042 (iOS) and 20261022.0051 (Mac), and the archive script refuses an upload that grew past them.

## Measured

Release archives of main f6725107 (2026-10-23), `scripts/archive-for-testflight.sh <folder> [--macos] --archive-only`, 2026-10-24:

| | Budget | Main | Growth |
| --- | --- | --- | --- |
| iOS app | 90.0 MB | 103.5 MB | +13.5 MB |
| iOS binary | 47.8 MB | 61.2 MB | +13.4 MB |
| Mac app | 61.5 MB | 75.0 MB | +13.5 MB |
| Mac binary | 46.6 MB | 60.1 MB | +13.5 MB |

The growth is all in the binary; assets and resource bundles did not change. Symbol sizes in the iOS dSYM (code and constants of named symbols only, so a lower bound) put it at:

- at least 5.6 MB for the PostgreSQL Mirror's client, linked whether the plugin is on or off: PostgresNIO 0.6, SwiftNIO (NIOCore 0.9, NIOPosix 0.6, NIOSSL 0.2, NIOTransportServices 0.2), BoringSSL 1.3, AsyncAlgorithms 0.9 MB, and smaller modules;
- 1.3 MB for `MermaidDiagrams`, against its target of 60 kB per architecture for every type (`Docs/Native-diagrams-todo.md`);
- the rest, about 6.5 MB, not yet named: `GraphiteUI` (11.4 MB in all) grew with the graph view, tabs, hover previews and Mac plugins.

## Scope

### 1. Back under the budget

- [ ] The PostgreSQL Mirror's client costs nothing in the app while the plugin is off, or the owner accepts its size. The mirror feeds desktop apps such as QGIS; one option is to build it only into the Mac app.
- [ ] `MermaidDiagrams` within its size target, or a new target agreed in `Docs/Native-diagrams-todo.md`.
- [ ] The remaining growth named by module (a link map of the Release build) and each part kept or moved out.
- [ ] The budget recorded again (`scripts/app-size-budget.py --record`) only for growth the owner accepts, and the next TestFlight upload passes without `--allow-size-growth`.

## Decisions

None yet.

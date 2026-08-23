# Cuesheet

A podcast player built around one claim: **the listening queue is an authored
document, not an accident.**

Every podcast app I've used mutates the queue as a side effect of tapping
things. You tap an episode and something happens to your queue that you didn't
ask for, can't name, and can't undo. Cuesheet's design follows from refusing
that. Two rules carry most of the weight:

1. Nothing mutates the queue except an explicit, named intent.
2. Every intent is a pure function over an immutable value, so every intent is
   undoable.

The features you'd list first — richer sorting, multi-axis filtering, relisten
tracking, custom categories, ephemeral *and* saved playlists — mostly fall out
of getting the data model and the intent algebra right. They aren't independent
features and aren't built as such.

## Status

Early. Phase 1 of 5.

| Phase | | |
|---|---|---|
| 0 | Scope and architecture | done |
| 1 | `cuesheet_domain` — pure Dart, test-first | in progress |
| 2 | `cuesheet_data` — Drift schema, repositories | |
| 3 | Feed ingestion and directory search | |
| 4 | `cuesheet_playback` — audio | |
| 5 | `cuesheet_ui` / `cuesheet_app` | |

The intent algebra is implemented and tested. Filtering, sorting,
listening-state semantics, and the entities are next.

## Why it's built this way

This project doubles as a deliberate Flutter case study — I write native iOS,
and Flutter is my primary platform at work now. So the build order front-loads
everything unit-testable and defers everything that isn't: pure domain logic
first, persistence second, audio fourth, UI last. You learn Dart before you
learn Flutter, rather than both at once, and by the time there's a UI the
engine underneath it already works.

A consequence worth naming: there is no runnable app yet, and won't be for a
while. A deliberately ugly debug UI arrives at the end of Phase 2.

## Layout

A pub workspace. Dependency arrows point inward only, toward `cuesheet_domain`,
which depends on no Flutter, no database, and no I/O.

```
packages/
  cuesheet_domain/     entities, the playback intent algebra, filter vocabulary
  cuesheet_data/       Drift schema, repositories, feed parsing, search      (todo)
  cuesheet_playback/   just_audio, behind interfaces the domain owns         (todo)
  cuesheet_ui/         design tokens and components                          (todo)
  cuesheet_app/        the Flutter app; Riverpod wiring lives here           (todo)
```

## Running the tests

Flutter is pinned with [fvm](https://fvm.app) via `.fvmrc` (3.41.6 / Dart 3.11.4).

```sh
dart pub get
cd packages/cuesheet_domain && dart test
```

The domain suite needs no simulator, no database, and no audio session, and
runs in under a second. That's the point of the layering.

## Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — scope, layering, the intent
  algebra, episode identity, the filter model, and what's deliberately out of
  scope. Start at §5.
- **[docs/notes/](docs/notes/)** — Dart and Flutter concepts explained from a
  Swift/iOS starting point, including where the analogies break down. Written
  in the same commit as the code that motivated them.

## License

Not yet chosen.

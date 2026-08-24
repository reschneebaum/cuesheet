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

Early. Phase 4 of 5 complete.

| Phase | | |
|---|---|---|
| 0 | Scope and architecture | done |
| 1 | `cuesheet_domain` — pure Dart, test-first | done |
| 2 | `cuesheet_data` — Drift schema, repositories | done |
| 3 | Feed ingestion and directory search | done |
| 4 | `cuesheet_playback` — audio | done |
| 5 | `cuesheet_ui` / `cuesheet_app` | |

The engine works, and it makes noise: the intent algebra, filtering and
sorting, listening-state semantics, persistence, real feeds going in one end
and identified episodes coming out the other, and audio with lock-screen
controls. What is left is the part this project has been deferring on purpose —
an actual interface.

## Why it's built this way

This project doubles as a deliberate Flutter case study — I write native iOS,
and Flutter is my primary platform at work now. So the build order front-loads
everything unit-testable and defers everything that isn't: pure domain logic
first, persistence second, audio fourth, UI last. You learn Dart before you
learn Flutter, rather than both at once, and by the time there's a UI the
engine underneath it already works.

A consequence worth naming: the app you can run is a deliberately ugly debug
harness — lists and buttons, no design — which arrived at the end of Phase 2,
grew a Feeds tab in Phase 3 and transport controls in Phase 4. You can subscribe
to a real podcast, watch what ingestion did to your library, and listen to it.
It is not pleasant to look at, and that is still deliberate.

## Layout

A pub workspace. Dependency arrows point inward only, toward `cuesheet_domain`,
which depends on no Flutter, no database, and no I/O.

```
packages/
  cuesheet_domain/     entities, the playback intent algebra, filter vocabulary
  cuesheet_data/       Drift schema, repositories, feed parsing, search
  cuesheet_playback/   just_audio, behind interfaces the domain owns
  cuesheet_ui/         design tokens and components                          (todo)
  cuesheet_app/        the Flutter app; Riverpod wiring lives here           (todo)
```

## Running the tests

Flutter is pinned with [fvm](https://fvm.app) via `.fvmrc` (3.41.6 / Dart 3.11.4).

```sh
dart pub get
cd packages/cuesheet_domain && dart test   # 227
cd ../cuesheet_data && dart test           # 277
cd ../cuesheet_playback && flutter test    # 10
cd ../cuesheet_app && flutter test         # 35
```

The domain suite needs no simulator, no database, and no audio session. The
data suite adds real SQLite in memory and a corpus of real podcast feeds, and
still touches no network. All three together run in a couple of seconds. That's
the point of the layering.

## Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — scope, layering, the intent
  algebra, episode identity, the filter model, and what's deliberately out of
  scope. Start at §5.
- **[docs/notes/](docs/notes/)** — Dart and Flutter concepts explained from a
  Swift/iOS starting point, including where the analogies break down. Written
  in the same commit as the code that motivated them.

## License

Not yet chosen.

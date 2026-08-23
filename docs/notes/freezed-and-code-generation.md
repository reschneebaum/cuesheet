# freezed and code generation

## What it is

Dart has no macro system in general use, so the ecosystem does boilerplate
elimination by **generating source files on disk**. You write a declaration,
run a build tool, and a sibling file appears containing the code you would
otherwise have typed.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'episode.freezed.dart';        // the generated file, joined to this one

@freezed
abstract class Episode with _$Episode {
  const factory Episode({
    required EpisodeId id,
    required String title,
    @Default(false) bool isOrphaned,
  }) = _Episode;
}
```

Then:

```sh
dart run build_runner build          # once
dart run build_runner watch          # or continuously
```

`episode.freezed.dart` appears with `==`, `hashCode`, `copyWith`, `toString`,
and the concrete `_Episode` class the factory redirects to.

## Closest Swift/iOS analogue

Swift's synthesised conformances: declare `struct Episode: Equatable, Hashable,
Codable` and the compiler writes `==`, `hash(into:)`, and the coding machinery
for you. Same problem, same motivation — stop hand-writing mechanical code that
goes stale when you add a field.

Swift macros (`@attached(member)`) are the closer modern analogue, since they
are also user-authored code generation.

## Where the analogy breaks down

**The generated code is a file you can open.** Swift's synthesis happens inside
the compiler and you never see it. Freezed writes `episode.freezed.dart` next
to your source, and reading it is the fastest way to understand what you
actually got. Genuinely useful — do it once.

**It is a separate build step you have to remember.** Nothing runs
`build_runner` for you. Add a field, forget to regenerate, and you get errors
about a constructor that does not match — confusing until you recognise the
shape of it. `watch` is the usual answer during active work.

**`part` is not `import`.** `part 'episode.freezed.dart';` splices another file
into *this* library rather than referencing a separate one. The generated file
starts with `part of 'episode.dart';`, sees this file's private members, and
shares its imports — which is why the generated code can refer to `EpisodeId`
without importing `ids.dart` itself. There is no Swift equivalent; the closest
is being in the same file, not the same module.

**The class must be `abstract` and mix in `_$Episode`.** In freezed 3.x the
declaration is a shell: `abstract class Episode with _$Episode` plus a
`const factory` that redirects to a generated `_Episode`. You never instantiate
`Episode` directly — the factory hands you the generated subclass. This is why
adding a plain method requires also adding a private constructor
(`const Episode._();`), which is otherwise unnecessary.

**`@Default` only works inside the factory constructor.** It is an annotation
read by the generator, not a language feature, so it is meaningless anywhere
else.

**Generated files are build output.** They are gitignored here, matching work's
`MobileToolboxFlutter`. A fresh clone does not compile until someone runs
`build_runner`.

**The payoff includes a thing hand-written code cannot easily do:** freezed's
`copyWith` distinguishes "argument omitted" from "argument was null", using a
private sentinel as each nullable parameter's default. So
`copyWith(finishedAt: null)` genuinely clears the field — see
[value equality and the copyWith-null problem](value-equality-and-copywith.md).

## Minimal example

```dart
// thing.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'thing.freezed.dart';

@freezed
abstract class Thing with _$Thing {
  const factory Thing({required int a, String? b}) = _Thing;
}

// after `dart run build_runner build`:
const x = Thing(a: 1, b: 'hi');
print(x == const Thing(a: 1, b: 'hi'));  // true
print(x.copyWith(b: null).b);            // null — not 'hi'
```

## Where it's used here

- `packages/cuesheet_domain/lib/src/episode.dart`,
  `podcast.dart`, `listening_state.dart`, `episode_view.dart` — the entities.
- `packages/cuesheet_domain/lib/src/listening.dart` — `markUnplayed` uses
  `copyWith(finishedAt: null)`, which only works because of the sentinel.
- `packages/cuesheet_domain/lib/src/cuesheet.dart` — deliberately *not*
  freezed. It was written by hand first so the generated code has something to
  be compared against.

# Strings: code units, runes, and characters

## What it is

A Dart `String` is a sequence of **UTF-16 code units**. `length` counts code
units. `s[i]` returns a one-code-unit `String`. Iterating a string with an
index walks code units, not characters.

Three views sit on top of that:

| View | Element | Type |
|---|---|---|
| the string itself | UTF-16 code unit | `String` of length 1 |
| `s.runes` | Unicode code point | `int` |
| `s.characters` | grapheme cluster | `String` |

`characters` is **not in the core library**. It comes from
`package:characters`, which Flutter re-exports but pure Dart does not.

## Closest Swift/iOS analogue

Swift's `String` and its views: `String.UTF16View`, `String.UnicodeScalarView`,
and the string itself as a collection of `Character`.

The three levels are the same three levels. The mapping is:

| Dart | Swift |
|---|---|
| `String` (default) | `s.utf16` |
| `s.runes` | `s.unicodeScalars` |
| `s.characters` | `s` |

## Where the analogy breaks down

**The defaults are at opposite ends.** Swift's default view is the safest one —
`Character`, a grapheme cluster — and you opt *down* into `utf16` when you need
it. Dart's default view is the least safe one, and you opt *up*. Every habit
built on `s.count` and `for c in s` being grapheme-correct is wrong in Dart,
and wrong silently.

```dart
'👍'.length            // 2  — one emoji, two code units
'👍'.runes.length      // 1
'👍'[0]                // half a surrogate pair; prints as garbage
'e\u0301'.length  // 2  — "é" written as e + combining acute
```

In Swift, `"👍".count` is 1 and `"👍".first` is the whole emoji.

**No integer indexing in Swift, all integer indexing in Dart.** Swift's
`String.Index` exists precisely to stop you slicing mid-character. Dart hands
you `substring(int, int)` with no such protection, so `substring` and `[]` can
split a surrogate pair and produce an invalid string. There is no compile
error, no exception, and no runtime complaint — just a broken character
downstream.

**Reversing a string is a trap.** `s.split('').reversed.join()` corrupts every
non-BMP character and every combining sequence. The Swift habit
(`String(s.reversed())`) is correct there and wrong when transliterated.

**`String.fromCharCode` takes a code point, not a code unit.** Despite the
name, it accepts values above `0xFFFF` and emits the surrogate pair for you —
so `String.fromCharCode(0x1F600)` is a whole emoji, and produces a string of
`length` 2. This is the one place the naming misleads in the *helpful*
direction.

**Regexes work on code units.** A character class with a literal astral
character in it does not do what you want; `.` matches one code unit. This is
the same as `NSRegularExpression`, and unlike Swift's native `Regex`.

## Minimal example

```dart
const s = 'Piñata 👍';

s.length;                  // 9  — code units
s.runes.length;            // 8  — code points
s.substring(0, 8);         // 'Piñata ' + half an emoji

// Safe: rebuild from code points.
String reverse(String s) => String.fromCharCodes(s.runes.toList().reversed);

// Decoding &#x1F44D; — fromCharCode takes the code *point*.
String.fromCharCode(0x1F44D);   // '👍', length 2
```

## Where it's used here

- `packages/cuesheet_data/lib/src/feed/plain_text.dart` — decoding numeric HTML
  entities. `&#128077;` is above the BMP, and `String.fromCharCode` is the
  reason that one line needs no surrogate arithmetic. The bounds check rejects
  anything above `0x10FFFF`, which is not a valid code point and would throw.
- The same file's whitespace collapsing runs on code units by design: every
  character it looks for (space, tab, U+00A0) is in the BMP, so the cheap
  view is also the correct one. Worth knowing *why* it is safe rather than
  assuming it.

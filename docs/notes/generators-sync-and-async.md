# Generators: `sync*` and `async*`

## What it is

A **generator function** produces a sequence lazily from ordinary control flow.
Instead of building a whole collection and returning it, you write a normal
loop and `yield` values one at a time. Dart has two forms, distinguished by a
marker after the parameter list:

| Marker | Returns | Can `await` inside |
|---|---|---|
| `sync*` | `Iterable<T>` | no |
| `async*` | `Stream<T>` | yes |

```dart
Stream<int> countdown(int from) async* {
  for (var i = from; i > 0; i--) {
    await Future<void>.delayed(const Duration(seconds: 1));
    yield i;
  }
  yield 0;
}
```

`yield` emits one value. `yield*` delegates to another sequence of the same
kind, splicing all of its values in:

```dart
Stream<Episode> everything(List<Podcast> podcasts) async* {
  for (final podcast in podcasts) {
    yield* episodesOf(podcast);   // a Stream<Episode>
  }
}
```

The function keeps its local variables and its position in the loop across
yields. It is a coroutine, not a callback.

## Closest Swift/iOS analogue

`AsyncStream` with a continuation:

```swift
func countdown(from: Int) -> AsyncStream<Int> {
    AsyncStream { continuation in
        Task {
            for i in stride(from: from, through: 1, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                continuation.yield(i)
            }
            continuation.yield(0)
            continuation.finish()
        }
    }
}
```

Consuming side is nearly identical — Swift's `for await` is Dart's `await for`.

## Where the analogy breaks down

**Swift has no generator functions; Dart does.** This is the real difference.
Swift makes you construct a stream object and push into a continuation from
inside a closure, which means an extra layer of nesting, a `Task` to own the
work, and remembering to call `finish()`. Dart's version is a normal function
body with a marker on it. Nothing to close, nothing to nest.

**The body does not run until someone listens.** Calling an `async*` function
returns a `Stream` and executes none of it:

```dart
Stream<int> noisy() async* {
  print('starting');    // not yet
  yield 1;
}

final s = noisy();      // prints nothing
await s.first;          // now prints "starting"
```

The classic `AsyncStream { continuation in … }` builder runs its closure
immediately, so this is backwards from the Swift habit. Laziness also means a
generator that is never listened to has no side effects at all, which is
occasionally a bug and occasionally exactly what you want.

**You get real backpressure, for free.** If the subscriber pauses, `yield`
suspends and the loop stops. Contrast a `StreamController`, where `add()`
buffers without limit and a slow consumer just accumulates memory. This is the
strongest practical reason to reach for `async*` over a controller.

**Cancellation unwinds the function.** When the subscriber cancels, the
generator is terminated at its suspension point and `finally` blocks run — so
cleanup is written where the resource is acquired:

```dart
Stream<Chunk> read(File file) async* {
  final handle = await file.open();
  try {
    while (true) {
      yield await handle.readChunk();
    }
  } finally {
    await handle.close();   // runs on cancel
  }
}
```

**Single-subscription.** The returned stream accepts exactly one listener, and
a second `listen` throws at runtime. Calling the function again gives a fresh
stream that re-runs the body from the top. See [Streams](streams-vs-combine.md).

**`sync*` cannot `await`.** It is the `Iterable` version, for lazily computed
in-memory sequences — a tree walk, an infinite series, a paginated view over
something already loaded. Reach for it when the work is cheap and synchronous
but the sequence is large or unbounded.

## When to use which

The distinction that matters:

- **`async*` when *you* drive the sequence** — a loop, a recursive walk,
  sequential async work that reports as it goes. The generator's own control
  flow is the source of the values.
- **`StreamController` when something *else* drives it** — a callback, a
  socket, a platform event channel, a plugin. Values arrive when they arrive
  and you have no loop to write.
- **Neither, when you already have a stream.** Transform it: `map`, `where`,
  `asyncMap`, `distinct`. Wrapping an existing stream in an `async*` that just
  `yield*`s it adds a layer and buys nothing.

## Where it fits here

Nothing in Cuesheet uses `async*` yet — drift hands us query streams directly,
and the repositories transform them with `asyncMap`, which is the third case
above.

The obvious place it will appear is Phase 3's feed refresh, which is sequential
async work that should report progress as it goes rather than returning one
result at the end:

```dart
sealed class RefreshProgress {}
final class Fetching extends RefreshProgress { … }
final class Fetched  extends RefreshProgress { … }   // with a count
final class Failed   extends RefreshProgress { … }   // with the error

Stream<RefreshProgress> refreshAll(List<Podcast> podcasts) async* {
  for (final podcast in podcasts) {
    yield Fetching(podcast);
    try {
      yield Fetched(podcast, await _fetchAndStore(podcast));
    } catch (error) {
      yield Failed(podcast, error);   // one bad feed must not stop the rest
    }
  }
}
```

A UI can render that stream as a progress list, and the `try`/`catch` inside
the loop is what keeps a single malformed feed from aborting a refresh of
fifty. Written with a `StreamController` this needs a controller, a loop, a
`close()` in a `finally`, and care not to `add` after closing.

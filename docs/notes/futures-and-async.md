# Futures and `async`/`await`

## What it is

`Future<T>` is a value that will exist later. `async` marks a function that
returns one; `await` suspends until it completes. Everything runs on a single
thread driven by an event loop, with a microtask queue that drains completely
between each event.

Parallelism, when you need it, is an **isolate** — a separate thread with its
own heap that shares no memory and communicates by copying messages.

## Closest Swift/iOS analogue

Swift's `async`/`await` and `Task`. The syntax is close enough that most code
transliterates without thinking, which is the problem: four things underneath
it are different, and none of them produce a compile error.

## Where the analogy breaks down

**Calling an `async` function starts it.** In Dart, `final f = fetch();` runs
`fetch` synchronously up to its first `await`, then hands you a `Future`
that is already in flight. Swift has no equivalent — you cannot call an `async`
function without `await`, `async let`, or a `Task`. The Dart form is convenient
and is also how you accidentally start ten fetches you meant to run one at a
time.

**There is no cancellation. At all.** A `Future` cannot be cancelled once
started. There is no `Task.cancel()`, no `Task.isCancelled`, no cooperative
checking. If a feed refresh is in flight and the user navigates away, it
finishes. The only cancellable async primitive is `StreamSubscription`, which
is why anything genuinely abortable ends up modelled as a stream, and why a
"cancel" button usually means "ignore the result when it arrives".

**No structured concurrency.** No `TaskGroup`, no `async let`, no parent task
that cancels its children when it exits scope. `Future.wait` is the nearest
thing and it is not the same thing: it does not cancel siblings when one fails,
because it cannot. With `eagerError: true` it returns early on the first error
and the other futures keep running to completion, unobserved.

**One thread, so no actors and no `Sendable`.** There are no data races within
an isolate, so Dart needs none of the machinery Swift needs to prevent them —
no `@MainActor`, no `Sendable` conformance, no actor isolation. The cost is
that CPU-bound work blocks everything, and the fix is `Isolate.run`, which
copies its arguments and its result rather than sharing them.

**An unawaited `Future` that throws does not throw at you.** The error is
reported to the enclosing `Zone` as an unhandled async error — it does not
propagate to the caller and it does not stop anything. It usually surfaces as a
log line, at a stack depth that has nothing to do with where you forgot the
`await`. `unawaited(f)` from `dart:async` marks the omission as deliberate; the
`discarded_futures` and `unawaited_futures` lints catch the rest.

**The good news:** `try`/`catch`/`finally` work across `await` exactly as they
do in Swift, and `await` on a non-`Future` is legal and simply yields a
microtask.

## Minimal example

```dart
// Already running when this line finishes.
final pending = refresh(id);

// No way to stop it now, whatever happens next.
await Future<void>.delayed(const Duration(seconds: 1));
await pending;

// Concurrent, but not a task group: if the second throws, the first and third
// still run to completion.
final reports = await Future.wait([refresh(a), refresh(b), refresh(c)]);
```

## Where it's used here

- `packages/cuesheet_data/lib/src/feed/ingestion.dart` — the writes inside
  `db.transaction` are one `db.batch`, sequentially awaited, deliberately. Two
  reasons, and neither is obvious from Swift: drift propagates the enclosing
  transaction through a `Zone`, so work started concurrently inside one may not
  see it; and four hundred `await`ed inserts are four hundred round trips where
  a batch is one. The Swift instinct — a `TaskGroup` over the episodes — is the
  wrong shape twice over.
- `packages/cuesheet_data/lib/src/feed/feed_transport.dart` — the whole reason
  `FeedTransport` is an interface. There is no way to cancel an in-flight
  fetch, so the seam that makes tests instant is also the only seam where a
  fetch can be made not to happen at all.

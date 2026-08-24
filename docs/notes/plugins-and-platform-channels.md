# Plugins and platform channels

## What it is

A Flutter **plugin** is a Dart package that also ships native code — Swift or
Objective-C for iOS and macOS, Kotlin or Java for Android — plus the build-system
glue to get it linked. Dart and native do not share memory or call each other
directly. They exchange **messages** over a named `MethodChannel`, serialized by
a standard codec that understands a fixed set of types (numbers, strings, byte
buffers, lists, maps) and nothing else.

Every hop is asynchronous, even one that looks instantaneous.

## Closest Swift/iOS analogue

There isn't a close one, and that is the useful thing to know.

The nearest relatives are XPC to a helper process, or `NSDistributedNotification`
— message passing to something that is not in your address space. What it is
emphatically *not* is `import AVFoundation`. In an iOS app, `AVPlayer` is an
object you hold, configure, and observe with KVO, synchronously, right there.

## Where the analogy breaks down

**You cannot hold the object.** Dart never gets an `AVPlayer`. It gets an opaque
handle and sends it messages. There is no property access, no KVO, no delegate
you implement in Dart — the native side pushes updates back over an
`EventChannel`, which surfaces in Dart as a `Stream`.

**Everything is async, so state is always slightly stale.** `player.position` is
not a property read; it is the most recent value that arrived over a channel.
Two reads in the same frame can disagree with what the audio hardware is
actually doing. This is why `AudioEngine` reports a `Stream<PlaybackTick>`
rather than exposing getters — a getter would imply a precision the channel
cannot deliver.

**A plugin only exists on platforms that implement it.** `just_audio` declares
Android, iOS, macOS and web. `just_audio_background` declares Android and iOS.
A package with no implementation for the platform you are building simply is not
registered, and the failure arrives at runtime as a `MissingPluginException`
rather than at compile time. Swift has no equivalent: `#if os(iOS)` is checked
by the compiler.

**Federated plugins split one package into several.** An app-facing package, a
`platform_interface` package defining the contract, and one implementation
package per platform. When you read a stack trace through `just_audio` you are
walking three packages, and the one you `import` contains almost no logic.

**Plugins do not work under `flutter test`.** There is no engine, no platform
side, and no channel to answer. Any code path that reaches a plugin throws.
This is not a limitation to work around — it is the reason this project puts
`AudioEngine` behind an interface at all, and why `FakeAudioEngine` exists.

**Hot reload does not reload native code.** Dart changes appear instantly;
changing a line of Swift in a plugin needs a full restart, and often a clean
build. The reflex that "everything is instant now" has an exception exactly
here.

## Minimal example

```dart
// What a plugin call actually is, underneath.
const channel = MethodChannel('com.example/audio');

// Async, even though "set the volume" is instant in native terms.
await channel.invokeMethod<void>('setVolume', {'value': 0.5});

// Native pushes updates back; Dart sees a Stream.
const events = EventChannel('com.example/audio/position');
events.receiveBroadcastStream().listen((Object? position) { /* … */ });
```

## Where it's used here

- `packages/cuesheet_playback/` — the only package in the project that depends
  on a plugin, and therefore the only one that cannot be unit-tested. That is
  not a coincidence, and it is why §13's testing table has "real verification is
  manual, on device" in exactly one row.
- `packages/cuesheet_playback/lib/src/just_audio_engine.dart` — merges four
  plugin-backed streams into one `PlaybackTick`. Four streams rather than four
  properties is the channel boundary showing through.
- `packages/cuesheet_data/` — the counter-example worth noticing. It talks to
  SQLite, which sounds native, but drift on a Flutter host uses an FFI binding
  rather than a channel, so the package stays pure Dart and its tests stay fast.
  "Touches the OS" and "needs a plugin" are not the same question.

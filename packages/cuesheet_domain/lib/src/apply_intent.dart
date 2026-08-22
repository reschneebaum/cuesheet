import 'package:meta/meta.dart';

import 'cuesheet.dart';
import 'ids.dart';
import 'playback_intent.dart';
import 'queue_state.dart';

/// The outcome of applying one intent.
@immutable
final class IntentResult {
  const IntentResult({
    required this.state,
    required this.changed,
    this.displaced,
  });

  const IntentResult.unchanged(this.state)
      : changed = false,
        displaced = null;

  final QueueState state;

  /// False when the intent was a no-op. Callers must not push an undo
  /// snapshot for an unchanged result, or the undo stack fills with
  /// indistinguishable entries.
  final bool changed;

  /// An ephemeral cuesheet this intent threw away. Retained rather than
  /// deleted so an accidentally-clobbered queue can be recovered.
  final Cuesheet? displaced;
}

/// Apply [intent] to [current]. The only function permitted to produce a new
/// [QueueState].
///
/// [visibleList] is the on-screen order at the moment of the interaction, and
/// is required rather than optional: "from here, descending" is meaningless
/// without knowing which list "here" is in. The same episode tapped in a
/// podcast's episode list, in a filter result, and in a saved cuesheet must
/// produce three different queues, so the view supplies its own ordering and
/// the domain never guesses.
///
/// [newCuesheetId] is injected so this stays a pure function and tests get
/// deterministic identifiers.
IntentResult applyIntent(
  QueueState current,
  PlaybackIntent intent,
  List<EpisodeId> visibleList, {
  required CuesheetId Function() newCuesheetId,
}) {
  switch (intent) {
    case PlayJustThis(:final episode):
      if (current.source == Detached(episode)) {
        return IntentResult.unchanged(current);
      }
      // Note what is *not* touched here: active and position carry over
      // verbatim. That is the entire feature.
      return IntentResult(
        state: QueueState(
          active: current.active,
          position: current.position,
          source: Detached(episode),
        ),
        changed: true,
      );

    case PlayFromHere(:final episode, :final order):
      final start = visibleList.indexOf(episode);
      if (start < 0) {
        throw ArgumentError.value(
          episode.value,
          'intent',
          'PlayFromHere names an episode that is not in the visible list',
        );
      }
      final items = switch (order) {
        TraversalOrder.ascending => visibleList.sublist(start),
        TraversalOrder.descending =>
          visibleList.sublist(0, start + 1).reversed.toList(),
      };
      return _newEphemeral(current, items, 0,
          startPlaying: true, newId: newCuesheetId, origin: intent);

    case ReplaceQueue(:final episodes, :final startAt):
      return _newEphemeral(current, episodes, startAt,
          startPlaying: true, newId: newCuesheetId, origin: intent);

    case AppendToQueue(:final episode):
      final active = current.active;
      if (active == null) {
        return _newEphemeral(current, [episode], 0,
            startPlaying: false, newId: newCuesheetId, origin: intent);
      }
      // Appending something already queued is a no-op rather than a move:
      // "make sure this gets played" should not silently reorder the queue.
      if (active.items.contains(episode)) {
        return IntentResult.unchanged(current);
      }
      return _withItems(current, active, [...active.items, episode],
          current.position, current.source);

    case InsertNext(:final episode):
      final active = current.active;
      if (active == null) {
        return _newEphemeral(current, [episode], 0,
            startPlaying: false, newId: newCuesheetId, origin: intent);
      }
      final existing = active.items.indexOf(episode);
      if (existing == current.position) {
        return IntentResult.unchanged(current);
      }
      final items = [...active.items];
      var position = current.position;
      if (existing >= 0) {
        // Move, never duplicate. Removing ahead of the playhead drags the
        // playhead back one so it keeps pointing at the same episode.
        items.removeAt(existing);
        if (existing < position) position -= 1;
      }
      items.insert((position + 1).clamp(0, items.length), episode);
      return _withItems(current, active, items, position, current.source);

    case RemoveFromQueue(:final episode):
      final active = current.active;
      if (active == null) return IntentResult.unchanged(current);
      final index = active.items.indexOf(episode);
      if (index < 0) return IntentResult.unchanged(current);

      final items = [...active.items]..removeAt(index);
      var position = current.position;
      var source = current.source;
      if (items.isEmpty) {
        position = 0;
        // Only queue-sourced playback stops; detached playback is unaffected
        // by anything that happens to the queue.
        if (source is FromQueue) source = null;
      } else if (index < position) {
        position -= 1;
      } else {
        // Removing the playing episode slides the next one under the
        // playhead; removing the final episode falls back to the previous.
        position = position.clamp(0, items.length - 1);
      }
      return _withItems(current, active, items, position, source);

    case ReorderQueue(:final from, :final to):
      final active = current.active;
      if (active == null) return IntentResult.unchanged(current);
      if (from < 0 || from >= active.items.length) {
        throw RangeError.index(from, active.items, 'from');
      }
      // Resolve the playing episode *before* reordering, then find it again
      // afterwards. Position is an index, and indices do not survive a move.
      final playing = current.source is FromQueue ? current.nowPlaying : null;
      final items = [...active.items];
      final moved = items.removeAt(from);
      items.insert(to.clamp(0, items.length), moved);
      final position = playing != null
          ? items.indexOf(playing)
          : current.position.clamp(0, items.isEmpty ? 0 : items.length - 1);
      return _withItems(current, active, items, position, current.source);
  }
}

/// Replace the queue with a brand-new ephemeral cuesheet.
IntentResult _newEphemeral(
  QueueState current,
  List<EpisodeId> items,
  int position, {
  required bool startPlaying,
  required CuesheetId Function() newId,
  required PlaybackIntent origin,
}) {
  final deduped = _dedupe(items);
  final PlaybackSource? source;
  if (startPlaying) {
    source = deduped.isEmpty ? null : const FromQueue();
  } else {
    source = current.source;
  }
  final previous = current.active;
  return IntentResult(
    state: QueueState(
      active: Cuesheet(
        id: newId(),
        kind: CuesheetKind.ephemeral,
        items: deduped,
        origin: origin,
      ),
      position: deduped.isEmpty ? 0 : position.clamp(0, deduped.length - 1),
      source: source,
    ),
    changed: true,
    // A saved cuesheet is not "displaced" — it still exists in the library.
    displaced:
        previous != null && previous.kind == CuesheetKind.ephemeral ? previous : null,
  );
}

/// Rewrite the active cuesheet's items in place, collapsing to a no-op if the
/// result is indistinguishable from where we started.
IntentResult _withItems(
  QueueState current,
  Cuesheet active,
  List<EpisodeId> items,
  int position,
  PlaybackSource? source,
) {
  final next = QueueState(
    active: active.copyWith(items: items),
    position: position,
    source: source,
  );
  return next == current
      ? IntentResult.unchanged(current)
      : IntentResult(state: next, changed: true);
}

List<EpisodeId> _dedupe(List<EpisodeId> input) {
  final seen = <EpisodeId>{};
  return [
    for (final id in input)
      if (seen.add(id)) id,
  ];
}

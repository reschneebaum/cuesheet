import 'package:meta/meta.dart';

import 'apply_intent.dart';
import 'ids.dart';
import 'playback_intent.dart';
import 'queue_state.dart';

/// What a control should say, and whether it should offer to do anything.
@immutable
final class IntentPreview {
  const IntentPreview({
    required this.willChange,
    required this.verb,
    this.detail,
  });

  /// False means the intent is already satisfied or inapplicable. Render the
  /// control as already-done rather than hiding it — the user learns the
  /// episode's queue state from seeing it.
  final bool willChange;

  /// The label. "Add to queue", "Move to end", "Play from here down".
  final String verb;

  /// Why the control reads the way it does: "Already #3 in queue",
  /// "Not in this list", "Playing now".
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is IntentPreview &&
      other.willChange == willChange &&
      other.verb == verb &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(willChange, verb, detail);

  @override
  String toString() =>
      'IntentPreview($verb${detail == null ? '' : ' — $detail'}, '
      'willChange: $willChange)';
}

/// Describe what [intent] would do to [current], without doing it.
///
/// The UI is not permitted to invent its own labels or its own
/// enabled/disabled logic: a control that says "Move to end" and then does
/// nothing has lied, which is precisely the class of surprise this app exists
/// to eliminate.
///
/// [willChange] is answered by running [applyIntent] itself rather than by
/// reimplementing its rules. That is the entire anti-drift guarantee — there
/// is one set of rules, and the label reads from it.
IntentPreview previewIntent(
  QueueState current,
  PlaybackIntent intent,
  List<EpisodeId> visibleList,
) {
  final described = _describe(current, intent, visibleList);

  bool willChange;
  try {
    willChange = applyIntent(
      current,
      intent,
      visibleList,
      newCuesheetId: _previewId,
    ).changed;
  } on ArgumentError {
    // Covers RangeError too, which extends ArgumentError. Either way the
    // intent cannot be applied, so there is nothing to offer.
    willChange = false;
  }

  return IntentPreview(
    willChange: willChange,
    verb: described.verb,
    detail: described.detail,
  );
}

CuesheetId _previewId() => const CuesheetId('preview');

String _episodes(int n) => '$n ${n == 1 ? 'episode' : 'episodes'}';

/// The wording. Returns a record rather than a class — it is two strings that
/// exist for one statement, and naming a type for that would be ceremony.
({String verb, String? detail}) _describe(
  QueueState state,
  PlaybackIntent intent,
  List<EpisodeId> visibleList,
) {
  final items = state.active?.items ?? const <EpisodeId>[];

  switch (intent) {
    case PlayJustThis(:final episode):
      final alreadyDetached = state.isDetached && state.nowPlaying == episode;
      return (
        verb: 'Play just this',
        detail: alreadyDetached ? 'Playing now' : null,
      );

    case PlayFromHere(:final episode, :final order):
      final verb = switch (order) {
        TraversalOrder.ascending => 'Play from here down',
        TraversalOrder.descending => 'Play from here up',
      };
      final at = visibleList.indexOf(episode);
      if (at < 0) return (verb: verb, detail: 'Not in this list');
      final count = switch (order) {
        TraversalOrder.ascending => visibleList.length - at,
        TraversalOrder.descending => at + 1,
      };
      return (verb: verb, detail: _episodes(count));

    case InsertNext(:final episode):
      const verb = 'Play next';
      final at = items.indexOf(episode);
      if (at < 0) return (verb: verb, detail: null);
      if (at == state.position) return (verb: verb, detail: 'Playing now');
      if (at == state.position + 1) return (verb: verb, detail: 'Already next');
      return (verb: verb, detail: 'Move up from #${at + 1}');

    case AppendToQueue(:final episode):
      final at = items.indexOf(episode);
      return (
        verb: 'Add to queue',
        detail: at < 0 ? null : 'Already #${at + 1} in queue',
      );

    case MoveToEnd(:final episode):
      const verb = 'Move to end';
      final at = items.indexOf(episode);
      if (at < 0) return (verb: verb, detail: 'Not in queue');
      if (at == items.length - 1) return (verb: verb, detail: 'Already last');
      return (verb: verb, detail: null);

    case ReplaceQueue(:final episodes):
      return (verb: 'Replace queue', detail: _episodes(episodes.length));

    case RemoveFromQueue(:final episode):
      return (
        verb: 'Remove from queue',
        detail: items.contains(episode) ? null : 'Not in queue',
      );

    case ReorderQueue():
      return (verb: 'Reorder', detail: null);
  }
}

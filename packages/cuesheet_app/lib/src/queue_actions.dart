import 'package:cuesheet_domain/cuesheet_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The one path from a tap to a changed queue.
///
/// Nothing else in the app is allowed to call `saveQueue`. Every mutation goes
/// through [apply], which means every mutation is a named intent, and every
/// mutation pushes an undo snapshot — the invariant the whole app is built on,
/// enforced by there being exactly one function that can break it.
class QueueActions {
  QueueActions(this._ref);

  final Ref _ref;

  Future<void> apply(PlaybackIntent intent, List<EpisodeId> visible) async {
    final repository = _ref.read(cuesheetRepositoryProvider);
    final current = await repository.queue();

    final result = applyIntent(
      current,
      intent,
      visible,
      newCuesheetId: _newCuesheetId,
    );
    // A no-op must not push an undo snapshot, or the stack fills with entries
    // that undo nothing.
    if (!result.changed) return;

    _ref.read(undoStackProvider.notifier).push(current);
    await repository.saveQueue(result.state, displaced: result.displaced);
  }

  Future<void> undo() async {
    final previous = _ref.read(undoStackProvider.notifier).pop();
    if (previous == null) return;
    await _ref.read(cuesheetRepositoryProvider).saveQueue(previous);
  }

  /// Restoring a displaced queue is an ordinary save, not a special path —
  /// re-saving it as active clears its displaced stamp.
  Future<void> restore(Cuesheet cuesheet) async {
    final repository = _ref.read(cuesheetRepositoryProvider);
    _ref.read(undoStackProvider.notifier).push(await repository.queue());
    await repository.saveQueue(
        QueueState(active: cuesheet, source: const FromQueue()));
  }

  Future<void> promote(Cuesheet cuesheet, String title) =>
      _ref.read(cuesheetRepositoryProvider).save(
          cuesheet.copyWith(kind: CuesheetKind.saved, title: title));

  /// Stand-in for playback, which does not exist until Phase 4. Advances the
  /// playhead so the listening-state rules can be exercised by hand.
  /// Named to avoid shadowing the domain's `advance`, which it calls.
  Future<void> advancePlayhead(EpisodeView view, Duration by) async {
    final listening = _ref.read(listeningRepositoryProvider);
    final current = await listening.byEpisode(view.episode.id);
    await listening.save(advance(
      current,
      to: current.position + by,
      episodeDuration: view.episode.duration,
      now: _ref.read(clockProvider)(),
    ));
  }

  Future<void> resetListening(EpisodeView view) async {
    final listening = _ref.read(listeningRepositoryProvider);
    await listening.save(
        markUnplayed(await listening.byEpisode(view.episode.id)));
  }
}

CuesheetId _newCuesheetId() =>
    CuesheetId('cs-${DateTime.now().microsecondsSinceEpoch}');

final queueActionsProvider = Provider<QueueActions>(QueueActions.new);

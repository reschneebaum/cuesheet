import 'package:freezed_annotation/freezed_annotation.dart';

import 'episode.dart';
import 'ids.dart';
import 'listening_state.dart';

part 'episode_view.freezed.dart';

/// An episode with everything needed to filter and sort it.
///
/// The pieces live in separate tables (§6, §10) and are assembled for
/// presentation. Filters and sorts are defined against this rather than
/// against [Episode], because most of the interesting predicates are about
/// listening history, not feed metadata.
@freezed
abstract class EpisodeView with _$EpisodeView {
  const factory EpisodeView({
    required Episode episode,
    required ListeningState listening,
    required String podcastTitle,
    @Default(<CategoryId>{}) Set<CategoryId> categories,
  }) = _EpisodeView;
}

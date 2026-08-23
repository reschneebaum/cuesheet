import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';
import 'repositories.dart';

part 'saved_filter.freezed.dart';

/// A smart list: a name plus a query.
///
/// There is no stored membership and no manual order — the contents are
/// whatever the query selects, every time it is asked. Hand-arranging one
/// means materializing it into a saved cuesheet instead (§7, §8), which is a
/// different object with honestly different semantics.
@freezed
abstract class SavedFilter with _$SavedFilter {
  const factory SavedFilter({
    required SavedFilterId id,
    required String name,
    required EpisodeQuery query,
  }) = _SavedFilter;
}

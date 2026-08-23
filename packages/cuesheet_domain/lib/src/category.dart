import 'package:freezed_annotation/freezed_annotation.dart';

import 'ids.dart';

part 'category.freezed.dart';

/// A user-defined grouping, applied to podcasts and to individual episodes.
///
/// Nothing here is derived from a feed's own iTunes categories — those describe
/// how a show markets itself, which is not how anyone organises their own
/// listening.
@freezed
abstract class Category with _$Category {
  const factory Category({
    required CategoryId id,
    required String name,

    /// Opaque ARGB value, chosen by the user. The domain does not interpret it.
    int? color,
  }) = _Category;
}

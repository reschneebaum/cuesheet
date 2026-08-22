import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'ids.dart';
import 'playback_intent.dart';

enum CuesheetKind { ephemeral, saved }

/// An ordered list of episodes.
///
/// Ephemeral and saved playlists are the same entity with a different [kind];
/// "save this queue" flips the kind and requires a title. There is deliberately
/// no separate saved-playlist model to drift out of sync with the queue you
/// were actually listening to.
@immutable
final class Cuesheet {
  Cuesheet({
    required this.id,
    required this.kind,
    required List<EpisodeId> items,
    this.title,
    this.origin,
  })  : items = List.unmodifiable(items),
        assert(
          items.length == items.toSet().length,
          'a cuesheet may not contain the same episode twice',
        ),
        assert(
          kind == CuesheetKind.ephemeral || title != null,
          'a saved cuesheet must have a title',
        );

  final CuesheetId id;
  final CuesheetKind kind;
  final List<EpisodeId> items;
  final String? title;

  /// Which intent produced this cuesheet. Provenance only — deliberately not
  /// part of [operator ==], since two cuesheets with the same contents are the
  /// same cuesheet regardless of how the user got there.
  final PlaybackIntent? origin;

  bool get isEmpty => items.isEmpty;

  Cuesheet copyWith({List<EpisodeId>? items, CuesheetKind? kind, String? title}) =>
      Cuesheet(
        id: id,
        kind: kind ?? this.kind,
        items: items ?? this.items,
        title: title ?? this.title,
        origin: origin,
      );

  static const _itemsEq = ListEquality<EpisodeId>();

  @override
  bool operator ==(Object other) =>
      other is Cuesheet &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      _itemsEq.equals(other.items, items);

  @override
  int get hashCode => Object.hash(id, kind, title, _itemsEq.hash(items));

  @override
  String toString() =>
      'Cuesheet(${id.value}, ${kind.name}, ${items.length} items)';
}

import 'dart:convert';

import 'package:cuesheet_domain/cuesheet_domain.dart';

/// Serialization for the filter vocabulary.
///
/// Lives here rather than in the domain deliberately: JSON is a storage
/// concern, and `cuesheet_domain` is meant to be readable without knowing
/// anything about how its values get written down.
///
/// The encoding is a tagged object per variant. Adding a variant to
/// [EpisodeFilter] breaks [encodeFilter] at compile time, which is the point
/// of the union being sealed; [decodeFilter] can only fail at runtime, so it
/// fails loudly.
Map<String, Object?> encodeFilter(EpisodeFilter filter) => switch (filter) {
      ListenStateIs(:final states) => {
          'type': 'listenState',
          'states': [for (final s in states) s.name],
        },
      InPodcasts(:final ids) => {
          'type': 'inPodcasts',
          'ids': [for (final i in ids) i.value],
        },
      InCategories(:final ids) => {
          'type': 'inCategories',
          'ids': [for (final i in ids) i.value],
        },
      DurationBetween(:final min, :final max) => {
          'type': 'duration',
          'min': min?.inMilliseconds,
          'max': max?.inMilliseconds,
        },
      PublishedBetween(:final from, :final to) => {
          'type': 'published',
          'from': from?.toIso8601String(),
          'to': to?.toIso8601String(),
        },
      LastPlayedBetween(:final from, :final to) => {
          'type': 'lastPlayed',
          'from': from?.toIso8601String(),
          'to': to?.toIso8601String(),
        },
      PlayCountBetween(:final min, :final max) => {
          'type': 'playCount',
          'min': min,
          'max': max,
        },
      TitleContains(:final text) => {'type': 'title', 'text': text},
      AllOf(:final children) => {
          'type': 'allOf',
          'children': [for (final c in children) encodeFilter(c)],
        },
      AnyOf(:final children) => {
          'type': 'anyOf',
          'children': [for (final c in children) encodeFilter(c)],
        },
      Not(:final child) => {'type': 'not', 'child': encodeFilter(child)},
    };

EpisodeFilter decodeFilter(Map<String, Object?> json) {
  final type = json['type'];
  return switch (type) {
    'listenState' => ListenStateIs({
        for (final s in _list(json, 'states'))
          _enumByName(ListenState.values, s as String, 'listen state'),
      }),
    'inPodcasts' =>
      InPodcasts({for (final i in _list(json, 'ids')) PodcastId(i as String)}),
    'inCategories' =>
      InCategories({for (final i in _list(json, 'ids')) CategoryId(i as String)}),
    'duration' => DurationBetween(
        min: _millis(json['min']),
        max: _millis(json['max']),
      ),
    'published' => PublishedBetween(
        from: _date(json['from']),
        to: _date(json['to']),
      ),
    'lastPlayed' => LastPlayedBetween(
        from: _date(json['from']),
        to: _date(json['to']),
      ),
    'playCount' => PlayCountBetween(
        min: json['min'] as int?,
        max: json['max'] as int?,
      ),
    'title' => TitleContains(json['text']! as String),
    'allOf' => AllOf([
        for (final c in _list(json, 'children'))
          decodeFilter(c as Map<String, Object?>),
      ]),
    'anyOf' => AnyOf([
        for (final c in _list(json, 'children'))
          decodeFilter(c as Map<String, Object?>),
      ]),
    'not' => Not(decodeFilter(json['child']! as Map<String, Object?>)),
    _ => throw FormatException('unknown filter type: $type'),
  };
}

List<Object?> encodeSort(List<SortSpec> sort) => [
      for (final spec in sort)
        {'field': spec.field.name, 'descending': spec.descending},
    ];

List<SortSpec> decodeSort(List<Object?> json) => [
      for (final entry in json)
        SortSpec(
          _enumByName(SortField.values,
              (entry! as Map<String, Object?>)['field']! as String, 'sort field'),
          descending:
              (entry as Map<String, Object?>)['descending'] as bool? ?? false,
        ),
    ];

/// The pair of strings the `saved_filters` row holds.
({String filterJson, String sortJson}) encodeQuery(EpisodeQuery query) => (
      filterJson: jsonEncode(encodeFilter(query.filter)),
      sortJson: jsonEncode(encodeSort(query.sort)),
    );

EpisodeQuery decodeQuery({required String filterJson, required String sortJson}) =>
    EpisodeQuery(
      filter: decodeFilter(jsonDecode(filterJson) as Map<String, Object?>),
      sort: decodeSort(jsonDecode(sortJson) as List<Object?>),
    );

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('expected a list at "$key", got $value');
  }
  return value;
}

Duration? _millis(Object? value) =>
    value == null ? null : Duration(milliseconds: value as int);

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

T _enumByName<T extends Enum>(List<T> values, String name, String what) {
  final match = values.where((v) => v.name == name).firstOrNull;
  if (match == null) throw FormatException('unknown $what: $name');
  return match;
}

/// Parsing the date formats feeds actually emit, which is a different problem
/// from parsing dates.
///
/// RSS 2.0 specifies RFC 822 for `<pubDate>`. What arrives is RFC 822 with the
/// year widened to four digits, RFC 822 with two, ISO 8601, a bare date, a
/// timestamp with the seconds omitted, a named timezone that RFC 822 never
/// defined, a day-of-week that disagrees with the date, and — often enough to
/// design for — nothing usable at all.
///
/// Everything that parses comes back **UTC**. A timestamp with no zone is read
/// as UTC rather than as device-local, deliberately: the alternative makes one
/// feed produce different `publishedAt` values on two devices in two
/// timezones, and §6's third match rung compares publication dates to day
/// resolution. A date that shifts with the reader is a date that stops
/// matching.
library;

const _months = <String, int>{
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// The North American zone abbreviations feeds use in place of an offset.
///
/// RFC 822 defined only these plus the military single letters; everything
/// else ("CET", "IST", "BST") is a local invention, and an unrecognised zone
/// is read as UTC rather than rejected — a timestamp off by an hour is worth
/// far more than no timestamp.
const _namedZones = <String, int>{
  'ut': 0, 'utc': 0, 'gmt': 0, 'z': 0,
  'est': -5 * 60, 'edt': -4 * 60,
  'cst': -6 * 60, 'cdt': -5 * 60,
  'mst': -7 * 60, 'mdt': -6 * 60,
  'pst': -8 * 60, 'pdt': -7 * 60,
};

/// ISO 8601 with no zone designator, which we must not hand to
/// [DateTime.tryParse] unmodified: it would read it as device-local.
final _isoWithoutZone = RegExp(
  r'^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?))?$',
);

/// RFC 822 and its descendants, generously.
///
/// The day-of-week is matched and then thrown away. Feeds get it wrong, and a
/// parser that trusts it over the numeric date would reject a date it can read
/// perfectly well.
final _rfc822 = RegExp(
  r'^(?:[A-Za-z]{3,9}\.?,\s*)?'
  r'(\d{1,2})\s+'
  r'([A-Za-z]{3,9})\.?\s+'
  r'(\d{2,4})'
  r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?'
  r'\s*(?:\(([A-Za-z]+)\)|([+-]\d{4}|[+-]\d{2}:\d{2}|[A-Za-z]+))?\s*$',
);

/// Returns UTC, or null when nothing in [raw] is a date.
DateTime? parseFeedDate(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;

  final bare = _isoWithoutZone.firstMatch(text);
  if (bare != null) {
    final time = bare[2] ?? '00:00:00';
    return DateTime.tryParse('${bare[1]}T${time}Z');
  }

  // Anything else ISO-shaped carries its own zone, so this is safe.
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc();

  final m = _rfc822.firstMatch(text);
  if (m == null) return null;

  final day = int.parse(m[1]!);
  if (day < 1 || day > 31) return null;

  final month = _months[m[2]!.substring(0, 3).toLowerCase()];
  if (month == null) return null;

  final offset = _zoneOffsetMinutes(m[7] ?? m[8]);

  return DateTime.utc(
    _fourDigitYear(int.parse(m[3]!)),
    month,
    day,
    int.tryParse(m[4] ?? '') ?? 0,
    int.tryParse(m[5] ?? '') ?? 0,
    int.tryParse(m[6] ?? '') ?? 0,
  ).subtract(Duration(minutes: offset));
}

/// RFC 2822 §4.3: a two-digit year below 50 is this century, 50 and up is the
/// last one. Three digits is a Y2K bug in someone's feed generator, and 1900 +
/// the value is what they meant.
int _fourDigitYear(int year) {
  if (year >= 1000) return year;
  if (year >= 100) return 1900 + year;
  return year < 50 ? 2000 + year : 1900 + year;
}

int _zoneOffsetMinutes(String? zone) {
  final z = zone?.trim();
  if (z == null || z.isEmpty) return 0;

  final numeric = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(z);
  if (numeric != null) {
    final magnitude = int.parse(numeric[2]!) * 60 + int.parse(numeric[3]!);
    return numeric[1] == '-' ? -magnitude : magnitude;
  }

  // Unrecognised names — including the obsolete military single letters, which
  // RFC 2822 says to treat as "zone unknown" — fall through to UTC.
  return _namedZones[z.toLowerCase()] ?? 0;
}

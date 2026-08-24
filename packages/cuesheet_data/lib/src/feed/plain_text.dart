/// Feeds put markup in fields that are specified as plain text — a bolded
/// episode title, a link in `<itunes:author>`, a `&nbsp;` holding two words
/// apart. Anything the app renders as a label goes through here first.
///
/// Note what this is *not* used for: `<description>`. Show notes are
/// legitimately HTML, the column holds what the feed sent, and plain text can
/// always be derived later. The reverse is not true.
library;

/// The named entities that actually appear in podcast feeds.
///
/// This is deliberately not the full HTML5 set of two thousand. An entity we
/// do not know is left as written, which is a visible, reportable bug; a
/// thousand-entry table nobody has read is not obviously better.
const _namedEntities = <String, String>{
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'nbsp': '\u00a0', 'ensp': ' ', 'emsp': ' ', 'thinsp': ' ',
  'ndash': '–', 'mdash': '—', 'hellip': '…',
  'lsquo': '‘', 'rsquo': '’', 'sbquo': '‚',
  'ldquo': '“', 'rdquo': '”', 'bdquo': '„',
  'laquo': '«', 'raquo': '»', 'bull': '•',
  'middot': '·', 'dagger': '†', 'prime': '′',
  'trade': '™', 'copy': '©', 'reg': '®',
  'deg': '°', 'plusmn': '±', 'times': '×',
  'frac12': '½', 'frac14': '¼', 'euro': '€',
  'pound': '£', 'cent': '¢', 'yen': '¥',
  'aacute': 'á', 'eacute': 'é', 'iacute': 'í',
  'oacute': 'ó', 'uacute': 'ú', 'ntilde': 'ñ',
  'uuml': 'ü', 'ouml': 'ö', 'auml': 'ä',
  'agrave': 'à', 'egrave': 'è', 'ccedil': 'ç',
  'szlig': 'ß', 'aring': 'å', 'oslash': 'ø', 'ae': 'æ',
};

final _entityPattern =
    RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#\d{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});');

final _lineBreakTags = RegExp(r'<br\s*/?>', caseSensitive: false);
final _blockEndTags =
    RegExp(r'</\s*(p|div|li|ul|ol|h[1-6]|blockquote|tr)\s*>', caseSensitive: false);
final _anyTag = RegExp(r'<[^>]*>');
final _horizontalSpace = RegExp(r'[ \t\r\f\u00a0]+');
final _paddedNewline = RegExp(r' *\n *');
final _blankRun = RegExp(r'\n{3,}');

/// Markup out, entities in, whitespace collapsed. Null in, null out; a string
/// that reduces to nothing also comes back null, because an empty title and an
/// absent one are the same thing to every caller.
String? plainText(String? raw) {
  if (raw == null) return null;

  var text = raw
      .replaceAll(_lineBreakTags, '\n')
      .replaceAll(_blockEndTags, '\n')
      .replaceAll(_anyTag, '');

  // Entities are decoded *after* tags are stripped, not before. A feed that
  // writes `&lt;b&gt;` means the reader should see the characters `<b>` — it
  // is not asking for a bold tag, and decoding first would strip it as one.
  text = decodeHtmlEntities(text)
      .replaceAll(_horizontalSpace, ' ')
      .replaceAll(_paddedNewline, '\n')
      .replaceAll(_blankRun, '\n\n')
      .trim();

  return text.isEmpty ? null : text;
}

/// Numeric entities are already gone by the time a feed reaches us — the XML
/// parser handles those. Named HTML entities are not: they are undefined in
/// XML, and inside CDATA nothing is decoded at all. Both paths are handled
/// here so the caller does not have to know which one it is on.
String decodeHtmlEntities(String text) =>
    text.replaceAllMapped(_entityPattern, (match) {
      final body = match[1]!;
      if (!body.startsWith('#')) {
        return _namedEntities[body.toLowerCase()] ?? match[0]!;
      }
      final hex = body[1] == 'x' || body[1] == 'X';
      final code = int.tryParse(body.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      if (code == null || code < 0x20 || code > 0x10ffff) return match[0]!;
      return String.fromCharCode(code);
    });

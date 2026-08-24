import 'dart:convert';

/// The 32 characters Windows-1252 puts where ISO-8859-1 has control codes.
///
/// Worth carrying rather than falling back to Latin-1 for the whole range:
/// every one of these is a curly quote, a dash or an ellipsis, and they are
/// the single most common non-ASCII characters in English-language show notes.
/// Decoding them as Latin-1 controls turns every apostrophe in a feed into an
/// invisible character.
const _cp1252High = <int, int>{
  0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02c6, 0x89: 0x2030, 0x8a: 0x0160,
  0x8b: 0x2039, 0x8c: 0x0152, 0x8e: 0x017d, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201c, 0x94: 0x201d, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02dc, 0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a, 0x9c: 0x0153,
  0x9e: 0x017e, 0x9f: 0x0178,
};

final _declaredEncoding =
    RegExp(r'''encoding\s*=\s*["']([\w.:+-]+)["']''', caseSensitive: false);

/// Turns the bytes of a feed into a string, working out the encoding the way
/// XML says to rather than the way HTTP says to.
///
/// For most content types the `Content-Type` charset is authoritative. XML
/// inverts that: a byte-order mark, and then the `encoding` pseudo-attribute
/// of the XML declaration, both outrank the transport, because an XML document
/// is supposed to be self-describing after it has been saved to disk and the
/// headers are long gone. Feeds served as `text/xml` with no charset are
/// common, and `package:http` would decode those as Latin-1 — which is why
/// this function exists rather than a call to `response.body`.
String decodeFeedBody(List<int> bytes, {String? contentType}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }

  final name = _declaredCharset(bytes) ?? _charsetParameter(contentType);
  return switch (name?.toLowerCase()) {
    'iso-8859-1' || 'latin1' || 'latin-1' || 'iso8859-1' =>
      String.fromCharCodes(bytes),
    'windows-1252' || 'cp1252' || 'win-1252' => _decodeCp1252(bytes),
    // Everything else, named or not, is read as UTF-8. `allowMalformed`
    // substitutes U+FFFD for bad sequences rather than throwing: one mangled
    // character must not cost the user a whole subscription.
    _ => utf8.decode(bytes, allowMalformed: true),
  };
}

/// The XML declaration is ASCII by construction, so reading the head of the
/// document as Latin-1 to find it is safe under every encoding this handles.
String? _declaredCharset(List<int> bytes) {
  final head =
      String.fromCharCodes(bytes.take(200).where((b) => b > 0 && b < 128));
  if (!head.trimLeft().startsWith('<?xml')) return null;
  final end = head.indexOf('?>');
  final declaration = end < 0 ? head : head.substring(0, end);
  return _declaredEncoding.firstMatch(declaration)?[1];
}

String? _charsetParameter(String? contentType) {
  if (contentType == null) return null;
  for (final part in contentType.split(';').skip(1)) {
    final pair = part.split('=');
    if (pair.length == 2 && pair.first.trim().toLowerCase() == 'charset') {
      return pair.last.trim().replaceAll('"', '');
    }
  }
  return null;
}

String _decodeCp1252(List<int> bytes) => String.fromCharCodes(
    [for (final b in bytes) _cp1252High[b] ?? b]);

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

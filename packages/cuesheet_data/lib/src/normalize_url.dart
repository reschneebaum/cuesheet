/// Query parameters that identify a listener or a campaign rather than a file.
const _trackingParams = {
  'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
  'ref', 'source', '_from', 'awCollectionId', 'awEpisodeId',
};

/// Redirect wrappers that podcast hosts prepend to the real enclosure URL.
/// The tail after the marker is the URL that actually matters.
const _redirectMarkers = [
  'dts.podtrac.com/redirect.mp3/',
  'chtbl.com/track/',
  'pdst.fm/e/',
  'traffic.megaphone.fm/',
  'verifi.podscribe.com/rss/p/',
  'pfx.vpixl.com/',
];

/// A stable key for an enclosure URL, for the second rung of the identity
/// ladder (§6).
///
/// Enclosure URLs move: hosts change CDN, add and remove analytics wrappers,
/// and append campaign parameters. Two URLs that fetch the same audio must
/// normalize to the same string, or a feed's routine reshuffle looks like a
/// batch of brand-new episodes.
///
/// Deliberately conservative for now — it unwraps the redirect prefixes we
/// know about and drops tracking parameters. Phase 3 extends it against the
/// real feed corpus, where the interesting cases live.
String normalizeEnclosureUrl(Uri url) {
  var text = url.toString();

  // Unwrap nested wrappers, innermost wins: some feeds stack two or three.
  var unwrapped = true;
  while (unwrapped) {
    unwrapped = false;
    for (final marker in _redirectMarkers) {
      final at = text.indexOf(marker);
      if (at >= 0) {
        final tail = text.substring(at + marker.length);
        // The tail may have lost its scheme in the wrapping.
        text = tail.startsWith('http') ? tail : 'https://$tail';
        unwrapped = true;
        break;
      }
    }
  }

  final parsed = Uri.tryParse(text);
  if (parsed == null) return text.toLowerCase();

  final kept = Map<String, String>.fromEntries(
    parsed.queryParameters.entries
        .where((e) => !_trackingParams.contains(e.key.toLowerCase())),
  );

  return Uri(
    scheme: parsed.scheme.toLowerCase(),
    host: parsed.host.toLowerCase(),
    port: parsed.hasPort ? parsed.port : null,
    path: parsed.path,
    queryParameters: kept.isEmpty ? null : kept,
  ).toString();
}

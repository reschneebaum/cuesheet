/// Typed identifiers.
///
/// These are extension types: a compile-time-only wrapper with no runtime
/// object of its own, so a `List<EpisodeId>` costs exactly what a
/// `List<String>` costs. The point is that `EpisodeId` and `CuesheetId` are
/// not interchangeable, which plain `String` aliases would not give us.
extension type const EpisodeId(String value) {}

extension type const CuesheetId(String value) {}

extension type const PodcastId(String value) {}

extension type const CategoryId(String value) {}

extension type const SavedFilterId(String value) {}

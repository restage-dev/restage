/// Server-side revenue-meter primitives — FX fold of a signed money movement
/// to USD micros.
///
/// Kept out of the general `restage_shared.dart` barrel on purpose. The fold
/// uses a signed-64-bit boundary constant (`2^63 − 1`) that the dart2js web
/// compiler cannot represent exactly, so any library that transitively pulls
/// it into a web compilation unit fails to build. The general barrel is
/// re-exported by the Flutter SDK, whose consumers may compile to dart2js
/// web; this meter is server-only (Dart VM) code and is imported directly by
/// the backend through this dedicated entrypoint.
library;

export 'src/meter/fold_entry_usd.dart';

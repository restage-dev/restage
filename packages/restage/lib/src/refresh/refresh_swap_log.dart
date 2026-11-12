import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:meta/meta.dart' show internal;

/// Logs in debug builds that a refresh replaced what a mounted surface shows.
@internal
void debugLogRefreshSwap(String surfaceType, String slug, Object? version) {
  if (!kDebugMode) return;
  debugPrint('[restage] live refresh: $surfaceType "$slug" now shows '
      '${version == null ? 'new content' : 'r$version'}.');
}

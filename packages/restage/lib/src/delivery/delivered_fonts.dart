import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart' show Widget;
import 'package:meta/meta.dart';
import 'package:restage_core/restage_core.dart'
    show DeliveredIconFonts, LoadedIconFont;
import 'package:restage_shared/restage_shared.dart';

/// Loads the icon fonts delivered with surfaces, once per font per process.
@internal
abstract final class DeliveredIconFontLoader {
  DeliveredIconFontLoader._();

  static final Map<String, Future<LoadedIconFont?>> _loading =
      <String, Future<LoadedIconFont?>>{};
  static final Map<String, LoadedIconFont> _loaded = <String, LoadedIconFont>{};

  /// Registers [bytes] with the engine under [family].
  @visibleForTesting
  static Future<void> Function(String family, Uint8List bytes) loadFont =
      _engineLoad;

  /// The family a delivered font with [bytes] is loaded under.
  static String familyFor(Uint8List bytes) =>
      'restage-icons-${crypto.sha256.convert(bytes).toString().substring(0, 12)}';

  /// Loads every font in [fonts]; true when all of them are usable.
  static Future<bool> loadAll(List<DeliveredIconFont> fonts) async {
    final results = await Future.wait(fonts.map((font) => _load(font.bytes)));
    return results.every((loaded) => loaded != null);
  }

  /// The loaded fonts for [fonts], keyed by source family. A font that has not
  /// finished loading is left out.
  static Map<String, LoadedIconFont> scopeFor(List<DeliveredIconFont> fonts) {
    final scope = <String, LoadedIconFont>{};
    for (final font in fonts) {
      final loaded = _loaded[familyFor(font.bytes)];
      if (loaded != null) scope[font.family] = loaded;
    }
    return scope;
  }

  /// Puts the loaded [fonts] in scope above [child]; [child] alone when the
  /// surface carries none.
  static Widget scope(List<DeliveredIconFont> fonts, {required Widget child}) =>
      fonts.isEmpty
          ? child
          : DeliveredIconFonts(fonts: scopeFor(fonts), child: child);

  /// Forgets every load so one test cannot leak into the next.
  @visibleForTesting
  static void reset() {
    _loading.clear();
    _loaded.clear();
    loadFont = _engineLoad;
  }

  static Future<LoadedIconFont?> _load(Uint8List bytes) {
    final family = familyFor(bytes);
    final pending = _loading[family];
    if (pending != null) return pending;
    final loading = _loadOnce(family, bytes);
    _loading[family] = loading;
    // A failed load is retried by the next delivery that carries it.
    unawaited(loading.then((loaded) {
      if (loaded == null) _loading.remove(family);
    }));
    return loading;
  }

  static Future<LoadedIconFont?> _loadOnce(
      String family, Uint8List bytes) async {
    try {
      final codePoints = readSfntCoveredCodePoints(bytes);
      await loadFont(family, bytes);
      return _loaded[family] = LoadedIconFont(
        loadedFamily: family,
        codePoints: Set<int>.unmodifiable(codePoints),
      );
    } on Object {
      return null;
    }
  }

  static Future<void> _engineLoad(String family, Uint8List bytes) =>
      (FontLoader(family)
            ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
          .load();
}

import 'dart:typed_data';

import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, ByteData, rootBundle;
import 'package:restage_shared/restage_shared.dart';

/// The directory generated `.rsbundle` containers are packaged into.
const String kRestageBundleAssetDirectory = 'assets/restage/bundles/';

/// Serves generated delivery artifacts out of packaged `.rsbundle` containers.
///
/// Generated artifacts used to be packaged twice: once loose at their logical
/// path and once inside a bundle. Only the bundles are packaged now, so a
/// reader asking for a logical path has to be answered from inside one.
///
/// This wraps an asset bundle and answers such a read by consulting the
/// containers, which means every existing logical-path reader keeps working
/// unchanged. Loose assets still win when present, so an application may
/// package a hand-authored artifact at a logical path and have it served.
///
/// Containers are located from the asset manifest rather than from any
/// per-artifact declaration, so artifacts whose references carry no locator —
/// every flow and paywall — resolve without one.
final class BundledAssetSource extends AssetBundle {
  /// Wraps [delegate], serving its assets first and packaged bundles second.
  BundledAssetSource(this.delegate);

  /// The underlying bundle. Loose assets are served from here unchanged.
  final AssetBundle delegate;

  final Map<String, Uint8List> _entries = <String, Uint8List>{};
  final Map<String, Object> _undecodable = <String, Object>{};
  // The RESOLVED key list, never the future that produces it. Memoizing the
  // future would hand a later caller a future created under an earlier
  // caller's async scheduling; when that scheduling is gone — as it is between
  // widget tests, each of which runs in its own fake-async zone — the await
  // never completes and the surface silently never renders.
  List<String>? _bundleKeys;
  int _indexed = 0;

  @override
  Future<ByteData> load(String key) async {
    try {
      return await delegate.load(key);
    } on Object catch (error, stackTrace) {
      final Uint8List? bytes;
      try {
        bytes = await _findEntry(key);
      } on Object catch (bundleError, bundleStack) {
        // A container that cannot be read is a packaging fault worth naming;
        // reporting the delegate's "asset missing" instead would send a
        // reader looking for a file that was never supposed to be there.
        Error.throwWithStackTrace(bundleError, bundleStack);
      }
      if (bytes == null) Error.throwWithStackTrace(error, stackTrace);
      return ByteData.sublistView(bytes);
    }
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async =>
      parser(await loadString(key));

  @override
  void evict(String key) {
    _entries.remove(key);
    delegate.evict(key);
  }

  @override
  void clear() {
    _entries.clear();
    _undecodable.clear();
    _bundleKeys = null;
    _indexed = 0;
    delegate.clear();
  }

  /// Finds [logicalPath] in the packaged containers, indexing only as many as
  /// it takes to find it.
  ///
  /// An application packaging many containers should not pay to read all of
  /// them to serve one artifact, so containers are indexed one at a time and
  /// the search stops at the first hit.
  Future<Uint8List?> _findEntry(String logicalPath) async {
    final known = _entries[logicalPath];
    if (known != null) return known;

    final keys = await _bundleAssetKeys();
    while (_indexed < keys.length) {
      await _indexBundle(keys[_indexed++]);
      final found = _entries[logicalPath];
      if (found != null) return found;
    }

    if (_undecodable.isNotEmpty) {
      // Every container was read and the artifact is in none of them, but some
      // could not be read at all — so "not packaged" is not a conclusion this
      // can honestly reach.
      throw StateError(
        'Could not serve "$logicalPath": '
        '${_undecodable.length} packaged bundle(s) could not be read '
        '(${_undecodable.keys.join(', ')}). '
        'First failure: ${_undecodable.values.first}',
      );
    }
    return null;
  }

  Future<List<String>> _bundleAssetKeys() async =>
      _bundleKeys ??= await _listBundleAssets();

  Future<List<String>> _listBundleAssets() async {
    final List<String> assets;
    try {
      assets = (await AssetManifest.loadFromAssetBundle(delegate)).listAssets();
    } on Object {
      // No manifest at all: an application that packages no bundles, or a
      // narrow test bundle. Either way there is nothing to serve, and the
      // delegate's own error is the right one to surface.
      return const <String>[];
    }
    return assets
        .where(
          (asset) =>
              asset.startsWith(kRestageBundleAssetDirectory) &&
              asset.endsWith('.rsbundle'),
        )
        .toList()
      // Indexing order decides which container answers first, so it is fixed
      // rather than left to the manifest's ordering.
      ..sort();
  }

  Future<void> _indexBundle(String assetKey) async {
    final RestageBundle bundle;
    try {
      final data = await delegate.load(assetKey);
      bundle = RestageBundleCodec.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } on Object catch (error) {
      _undecodable[assetKey] = error;
      return;
    }

    for (final entry in bundle.entries) {
      final existing = _entries[entry.logicalPath];
      final bytes = entry.bytes;
      if (existing == null) {
        _entries[entry.logicalPath] = bytes;
        continue;
      }
      if (!_sameBytes(existing, bytes)) {
        throw StateError(
          'Two packaged bundles disagree about "${entry.logicalPath}"; '
          '"$assetKey" carries different bytes than an earlier bundle.',
        );
      }
    }
  }

  static bool _sameBytes(Uint8List left, Uint8List right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

final Expando<BundledAssetSource> _sources = Expando<BundledAssetSource>();

/// Returns the bundle-aware view of [bundle], or of Flutter's root bundle.
///
/// One view is kept per underlying bundle so the container index built to
/// serve the first artifact is reused by every later read.
AssetBundle restageAssetSource(AssetBundle? bundle) {
  final delegate = bundle ?? rootBundle;
  if (delegate is BundledAssetSource) return delegate;
  return _sources[delegate] ??= BundledAssetSource(delegate);
}

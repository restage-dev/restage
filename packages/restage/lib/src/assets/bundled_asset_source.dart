import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        DiagnosticsNode,
        ErrorDescription,
        ErrorSummary,
        FlutterError,
        debugPrint;
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
///
/// The same manifest also decides whether the delegate is consulted at all. A
/// surface probes for optional artifacts by logical path — a flow document
/// that only a multi-screen surface has, a screen a single-screen one never
/// emits — and on a platform that fetches assets over the network, asking for
/// one that was never packaged costs a request whose failure the browser
/// logs. The manifest lists every packaged loose asset, so a key it does not
/// list is answered from the containers directly.
///
/// That rests on one requirement of the wrapped bundle: **its asset manifest
/// must describe it.** A bundle that serves assets its own manifest does not
/// list — one that answers `AssetManifest.bin` from the root bundle while
/// serving keys of its own — would have those keys reported as never
/// packaged. A bundle with no manifest at all is fine and unaffected: nothing
/// can be proven absent without one, so every read goes to the delegate.
final class BundledAssetSource extends AssetBundle {
  /// Wraps [delegate], serving its assets first and packaged bundles second.
  BundledAssetSource(this.delegate);

  /// The underlying bundle. Loose assets are served from here unchanged.
  final AssetBundle delegate;

  final Map<String, Uint8List> _entries = <String, Uint8List>{};
  final Map<String, Object> _undecodable = <String, Object>{};
  // The RESOLVED index, never the future that produces it. Memoizing the
  // future would hand a later caller a future created under an earlier
  // caller's async scheduling; when that scheduling is gone — as it is between
  // widget tests, each of which runs in its own fake-async zone — the await
  // never completes and the surface silently never renders.
  _AssetIndex? _index;
  int _indexed = 0;

  @override
  Future<ByteData> load(String key) async {
    final index = await _assetIndex();
    if (index.provesAbsent(key)) {
      final bytes = await _findEntry(key);
      if (bytes == null) throw _unableToLoad(key);
      return ByteData.sublistView(bytes);
    }
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
    _index = null;
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

    final keys = (await _assetIndex()).bundleKeys;
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

  Future<_AssetIndex> _assetIndex() async => _index ??= await _readAssetIndex();

  Future<_AssetIndex> _readAssetIndex() async {
    final List<String> assets;
    try {
      assets = (await AssetManifest.loadFromAssetBundle(delegate)).listAssets();
    } on FlutterError {
      // There is no manifest: an application that declares no assets, or a
      // narrow test bundle. Nothing can be proven absent without one, so every
      // read goes to the delegate exactly as it did before, and that is not
      // worth saying out loud.
      return const _AssetIndex.unavailable();
    } on Object catch (error) {
      // A manifest that exists and cannot be read is a different thing, and a
      // silent one is expensive: no container can be located, so every
      // packaged artifact fails as "not packaged" and points the reader at a
      // file they must not add. Fail open the same way — that is the safe
      // direction — but say why once.
      assert(() {
        debugPrint(
          '[restage] the asset manifest could not be read, so no packaged '
          'bundle can be located and every artifact inside one will report '
          'as missing: $error',
        );
        return true;
      }());
      return const _AssetIndex.unavailable();
    }
    return _AssetIndex(assets);
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

  /// Reports a key no loose asset and no container carries.
  ///
  /// Shaped like Flutter's own missing-asset failure, because every reader of
  /// this source distinguishes "not packaged" from every other failure by
  /// catching [FlutterError], and skipping the delegate must not change which
  /// branch a reader takes.
  static FlutterError _unableToLoad(String key) =>
      FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('Unable to load asset: "$key".'),
        ErrorDescription(
          'The asset manifest does not list it and no packaged bundle '
          'carries it.',
        ),
      ]);

  static bool _sameBytes(Uint8List left, Uint8List right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

/// What the asset manifest says an application packaged.
final class _AssetIndex {
  /// Indexes a manifest's asset list.
  ///
  /// A manifest lists every asset an application declares, not only Restage's,
  /// so it is walked once rather than once per thing read off it.
  factory _AssetIndex(List<String> assets) {
    final loose = <String>{};
    final bundleKeys = <String>[];
    for (final asset in assets) {
      loose.add(asset);
      if (asset.startsWith(kRestageBundleAssetDirectory) &&
          asset.endsWith('.rsbundle')) {
        bundleKeys.add(asset);
      }
    }
    return _AssetIndex._(
      available: true,
      loose: loose,
      // Indexing order decides which container answers first, so it is fixed
      // rather than left to the manifest's ordering.
      bundleKeys: bundleKeys..sort(),
    );
  }

  const _AssetIndex._({
    required this.available,
    required Set<String> loose,
    required this.bundleKeys,
  }) : _loose = loose;

  /// The index of an application whose manifest could not be read.
  const _AssetIndex.unavailable()
      : available = false,
        _loose = const <String>{},
        bundleKeys = const <String>[];

  /// Whether a manifest was read at all. Without one nothing is provable.
  final bool available;

  /// Packaged containers, in the order they are indexed.
  final List<String> bundleKeys;

  final Set<String> _loose;

  /// Whether the manifest proves [key] is not a loose asset.
  bool provesAbsent(String key) => available && !_loose.contains(key);
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

// A `Resolvers` that records every analyzer entry point a build step uses.
//
// The package-wide walks are supposed to resolve only the assets that can
// carry a Restage declaration. "Supposed to" is not measurable from an
// artifact — a walk that resolved every file would emit exactly the same
// output — so the proof has to observe the resolver itself.
//
// Every API that can pull analysis is counted, not just `libraryFor`: a
// regression that reached for `compilationUnitFor`, `astNodeFor` or `libraries`
// instead would otherwise read as zero. `isLibrary` is deliberately NOT
// counted — in the pinned build_runner it is a file-state query
// (`build_resolver.dart` asks the driver `getFile(...).isPart`), not an
// element resolution.
//
// This reaches into `build_runner`'s `src/` for `ResolversImpl` and
// `AnalysisDriverModel`. The pubspec pins `build_runner` exactly and explains
// why (a patch release once refactored `src/` out from under a proof in this
// package); raising that pin means re-verifying this file.

import 'dart:collection';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_runner/src/internal.dart' as build_runner_internal;

/// One analyzer entry point a build step reached for.
///
/// `asset` is `null` for the APIs that do not name one — those are counted
/// against every package, because nothing rules out what they reached.
typedef ResolverUse = ({String api, AssetId? asset});

/// Wraps a real build resolver and records every analysis it is asked for.
///
/// Pass one to `testBuilder(..., resolvers: ...)`, then read [uses] or
/// [usesIn].
final class CountingResolvers implements Resolvers {
  /// Creates a counting wrapper around a fresh analysis driver.
  CountingResolvers()
      : _delegate = build_runner_internal.ResolversImpl.custom(
          analysisDriverModel: build_runner_internal.AnalysisDriverModel(),
        );

  final Resolvers _delegate;

  final List<ResolverUse> _uses = <ResolverUse>[];

  /// Every analyzer entry point reached for, in call order, across build steps.
  List<ResolverUse> get uses => UnmodifiableListView(_uses);

  /// How many times each API was reached for.
  Map<String, int> get callsByApi {
    final counts = <String, int>{};
    for (final use in _uses) {
      counts[use.api] = (counts[use.api] ?? 0) + 1;
    }
    return counts;
  }

  /// [uses] restricted to [package], plus every use that names no asset.
  ///
  /// A build resolves libraries outside the package under test for reasons
  /// that have nothing to do with walk scoping — the SDK, Flutter, the Restage
  /// packages a fixture imports — so a claim about a walk is a claim about the
  /// package's own assets. A use that names no asset cannot be excluded that
  /// way and is therefore always reported.
  List<ResolverUse> usesIn(String package) => [
        for (final use in _uses)
          if (use.asset == null || use.asset!.package == package) use,
      ];

  /// A short, readable description of [usesIn], for a failure message.
  String describe(String package) => usesIn(package)
      .map((use) => '${use.api}(${use.asset?.path ?? '-'})')
      .join(', ');

  @override
  Future<ReleasableResolver> get(BuildStep buildStep) async =>
      _CountingResolver(await _delegate.get(buildStep), _uses);

  @override
  void reset() => _delegate.reset();
}

final class _CountingResolver implements ReleasableResolver {
  _CountingResolver(this._delegate, this._uses);

  final ReleasableResolver _delegate;
  final List<ResolverUse> _uses;

  @override
  Future<LibraryElement> libraryFor(
    AssetId assetId, {
    bool allowSyntaxErrors = false,
  }) {
    _uses.add((api: 'libraryFor', asset: assetId));
    return _delegate.libraryFor(
      assetId,
      allowSyntaxErrors: allowSyntaxErrors,
    );
  }

  @override
  Future<CompilationUnit> compilationUnitFor(
    AssetId assetId, {
    bool allowSyntaxErrors = false,
  }) {
    _uses.add((api: 'compilationUnitFor', asset: assetId));
    return _delegate.compilationUnitFor(
      assetId,
      allowSyntaxErrors: allowSyntaxErrors,
    );
  }

  @override
  Future<AstNode?> astNodeFor(Fragment fragment, {bool resolve = false}) {
    _uses.add((api: 'astNodeFor', asset: null));
    return _delegate.astNodeFor(fragment, resolve: resolve);
  }

  @override
  Stream<LibraryElement> get libraries {
    _uses.add((api: 'libraries', asset: null));
    return _delegate.libraries;
  }

  /// Not counted: a file-state query in the pinned build_runner, not a resolve.
  @override
  Future<bool> isLibrary(AssetId assetId) => _delegate.isLibrary(assetId);

  @override
  Future<LibraryElement?> findLibraryByName(String libraryName) =>
      _delegate.findLibraryByName(libraryName);

  @override
  Future<AssetId> assetIdForElement(Element element) =>
      _delegate.assetIdForElement(element);

  @override
  void release() => _delegate.release();
}

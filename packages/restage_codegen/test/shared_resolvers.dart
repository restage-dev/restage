import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/src/clients/build_resolvers/build_resolvers.dart'
    show AnalysisDriverForPackageBuild;
import 'package:build/build.dart';
import 'package:build_runner/src/build/asset_graph/graph.dart';
import 'package:build_runner/src/build/asset_graph/node.dart';
import 'package:build_runner/src/build/input_tracker.dart';
import 'package:build_runner/src/build/library_cycle_graph/asset_deps.dart';
import 'package:build_runner/src/build/library_cycle_graph/asset_deps_loader.dart';
import 'package:build_runner/src/build/library_cycle_graph/library_cycle_graph.dart';
import 'package:build_runner/src/build/library_cycle_graph/library_cycle_graph_loader.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_asset_deps.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_reader.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_value.dart';
import 'package:build_runner/src/build/resolver/analysis_driver_model.dart';
import 'package:build_runner/src/build/resolver/resolvers_impl.dart';
import 'package:build_runner/src/logging/timed_activities.dart';

/// Resolvers whose analysis driver stays warm across test builds.
///
/// `testBuilder` starts every build clean, so the stock driver model drops
/// its in-memory filesystem and re-parses and re-analyzes the whole
/// dependency closure per build. This model keeps unchanged sources and their
/// parsed directives, and invalidates only sources whose content changed or
/// that the next build no longer contains, so the analyzer re-analyzes only
/// the synthetic files a test actually varies.
///
/// Pass as `resolvers:` to `testBuilder` / `resolveSources`. Builds in one
/// isolate run sequentially, which is the only sharing this relies on.
final Resolvers sharedResolvers = ResolversImpl.custom(
  analysisDriverModel: _RetainingAnalysisDriverModel(),
);

final class _RetainingAnalysisDriverModel extends AnalysisDriverModel {
  final _graphLoader = LibraryCycleGraphLoader();
  final _syncedGraphs = Set<LibraryCycleGraph>.identity();
  final _depsCache = <AssetId, _ParsedDeps>{};
  final _synced = <AssetId>{};

  @override
  Future<void> takeLockAndStartBuild(
    AssetGraph assetGraph, {
    required Set<AssetId>? invalidatedSources,
  }) {
    // A clean build passes null, which would wipe the filesystem. Keep only
    // what this build still has as a source; content changes are caught by
    // hash when the file is synced again, and generated outputs are re-synced
    // once the build produces them.
    final gone = {
      for (final id in _synced)
        if (assetGraph.get(id)?.type != NodeType.source) id,
    };
    _synced.removeAll(gone);
    _depsCache.removeWhere((id, _) => gone.contains(id));
    return super.takeLockAndStartBuild(
      assetGraph,
      invalidatedSources: invalidatedSources ?? gone,
    );
  }

  @override
  void endBuildAndUnlock() {
    _graphLoader.clear();
    _syncedGraphs.clear();
    super.endBuildAndUnlock();
  }

  @override
  PhasedAssetDeps phasedAssetDeps() => _graphLoader.phasedAssetDeps();

  @override
  Future<void> updateDriver({
    required Future<void> Function(
      Future<void> Function(AnalysisDriverForPackageBuild),
    ) withDriver,
    required AssetId entrypoint,
    required PhasedReader phasedReader,
    required InputTracker inputTracker,
    required bool transitive,
  }) async {
    AssetId? idToSync;
    LibraryCycleGraph? graphToSync;

    if (transitive) {
      graphToSync = await TimedActivity.resolve.runAsync(() async {
        final nodeLoader = _CachingAssetDepsLoader(phasedReader, _depsCache);
        inputTracker.addResolverEntrypoint(entrypoint);
        return (await _graphLoader.libraryCycleGraphOf(
          nodeLoader,
          entrypoint,
        ))
            .valueAt(phase: phasedReader.phase);
      });
    } else {
      inputTracker.add(entrypoint);
      idToSync = entrypoint;
      await phasedReader.readAtPhase(entrypoint);
    }

    await withDriver((driver) async {
      await TimedActivity.resolve.runAsync(() async {
        filesystem.phase = phasedReader.phase;

        Future<void> sync(AssetId id) async {
          final content = await phasedReader.readAtPhase(id);
          if (content.exists) {
            filesystem.writeContent(content);
            _synced.add(id);
          }
        }

        if (idToSync != null) await sync(idToSync);

        if (graphToSync != null) {
          final next = [graphToSync];
          while (next.isNotEmpty) {
            final graph = next.removeLast();
            if (_syncedGraphs.add(graph)) {
              for (final id in graph.root.ids) {
                await sync(id);
              }
              next.addAll(graph.children);
            }
          }
        }
      });

      if (filesystem.changedPaths.isNotEmpty) {
        filesystem.changedPaths.forEach(driver.changeFile);
        filesystem.clearChangedPaths();
        await TimedActivity.analyze.runAsync(driver.applyPendingFileChanges);
      }
    });
  }
}

typedef _ParsedDeps = ({String content, PhasedValue<AssetDeps> deps});

/// Parses import directives once per distinct file content.
final class _CachingAssetDepsLoader extends AssetDepsLoader {
  _CachingAssetDepsLoader(this._reader, this._cache) : super(_reader);

  final PhasedReader _reader;
  final Map<AssetId, _ParsedDeps> _cache;

  @override
  Future<PhasedValue<AssetDeps>> load(AssetId id) async {
    final phased = await _reader.readPhased(id);
    final values = phased.values;
    if (values.length != 1 || values.single.expiresAfter != null) {
      return super.load(id);
    }
    final content = values.single.value;
    final cached = _cache[id];
    if (cached != null && cached.content == content) return cached.deps;
    final deps = PhasedValue.fixed(_parseDeps(id, content));
    _cache[id] = (content: content, deps: deps);
    return deps;
  }

  static AssetDeps _parseDeps(AssetId id, String content) {
    if (content.isEmpty) return AssetDeps.empty;
    final unit = parseString(content: content, throwIfDiagnostics: false).unit;
    return AssetDeps([
      for (final directive in unit.directives)
        if (directive is UriBasedDirective)
          if (directive.uri.stringValue case final uri?)
            if (Uri.parse(uri) case final parsed
                when !parsed.isScheme('dart') && !parsed.isScheme('dart-ext'))
              AssetId.resolve(parsed, from: id),
    ]);
  }
}

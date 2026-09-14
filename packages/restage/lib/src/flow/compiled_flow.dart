import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart';

import 'flow_resolver.dart';

/// Constructs an authored flow screen, including any app-owned arguments.
typedef CompiledFlowScreenBuilder = Widget Function();

/// The compiler's original graph and Flutter constructors, retained in Dart.
/// Uses the same document codec and graph as delivered flows; no assets are
/// needed to run a complete compiled closure.
final class CompiledFlow {
  /// Creates a compiler-emitted flow fallback.
  const CompiledFlow({
    required this.documentJson,
    required this.screens,
    this.children = const {},
  });

  /// Canonical JSON emitted by the existing flow compiler.
  final String documentJson;

  /// Original screen constructors keyed by artifact ID.
  final Map<String, CompiledFlowScreenBuilder> screens;

  /// Exact child graphs keyed by flow ID.
  final Map<String, CompiledFlow> children;

  /// Decodes the original contract through the delivery document codec.
  FlowDocument get document => FlowDocumentCodec.decodeJson(documentJson);

  /// Freezes the original constructors and child closure for one resolution.
  CompiledFlow freeze() => CompiledFlow(
        documentJson: documentJson,
        screens: Map.unmodifiable(screens),
        children: Map.unmodifiable({
          for (final entry in children.entries) entry.key: entry.value.freeze()
        }),
      );

  /// Supplies app-owned constructors throughout the compiled closure.
  CompiledFlow withScreenBuilders(
          Map<String, CompiledFlowScreenBuilder> builders) =>
      CompiledFlow(documentJson: documentJson, screens: {
        ...screens,
        for (final id in document.screenArtifacts.keys)
          if (builders.containsKey(id)) id: builders[id]!
      }, children: {
        for (final entry in children.entries)
          entry.key: entry.value.withScreenBuilders(builders)
      });

  /// Finds a graph in this already compiled closure.
  CompiledFlow? find(String id, int version) {
    final own = document;
    if (own.flow == id && own.version == version) return this;
    for (final child in children.values) {
      final found = child.find(id, version);
      if (found != null) return found;
    }
    return null;
  }

  /// Checks the complete native closure before a flow can start.
  void validateNativeClosure() => _validateNativeClosure(document);

  /// Whether every retained screen has an app-owned constructor available.
  bool get hasCompleteScreenBuilders =>
      document.screenArtifacts.keys.every(screens.containsKey) &&
      children.values.every((child) => child.hasCompleteScreenBuilders);

  void _validateNativeClosure(FlowDocument doc) {
    FlowDocumentValidation.checkValid(doc);
    for (final id in doc.screenArtifacts.keys) {
      if (!screens.containsKey(id)) {
        throw StateError(
            'Compiled flow "${doc.flow}" needs a builder for "$id".');
      }
    }
    for (final state in doc.states.values.whereType<SubFlowState>()) {
      final child = children[state.flow];
      final childDocument = child?.document;
      if (child == null ||
          childDocument!.version != state.version ||
          FlowContentHash.compute(
                  FlowDocumentCodec.encodeCanonicalJson(childDocument)) !=
              state.contentHash) {
        throw StateError(
            'Compiled flow "${doc.flow}" has no exact child "${state.flow}".');
      }
      child._validateNativeClosure(childDocument);
    }
  }

  /// Selects the original graph and native screens as one immutable resolution.
  ResolvedFlow resolve() {
    final doc = document;
    _validateNativeClosure(doc);
    return ResolvedFlow(
        document: doc,
        screenBlobs: const {},
        compiled: this,
        contentHash:
            FlowContentHash.compute(FlowDocumentCodec.encodeCanonicalJson(doc)),
        cacheHit: false);
  }
}

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Mutable state accumulated during one build pass over one input library.
///
/// The builder constructs a fresh instance per [BuildStep], passes it
/// through every registered [LibraryVisitor] in order, then makes write
/// decisions from the post-pass state.
///
/// Visitors share this object so a later visitor can read findings
/// contributed by earlier visitors (e.g. paywall translation reading
/// customer-registered widget entries). Visitors must not mutate the
/// `library` reference; only the accumulator fields are write-targets.
@internal
final class CodegenBuildState {
  /// Creates the per-build-pass accumulator over [library]/[assetId] with the
  /// shared merged [catalog].
  CodegenBuildState({
    required this.library,
    required this.assetId,
    required this.catalog,
  });

  /// The resolved library being walked.
  final LibraryElement library;

  /// The input asset whose library is being walked. Visitors use this
  /// when constructing the `location` field on [Issue]s they emit.
  final AssetId assetId;

  /// Merged widget catalog spanning all built-in libraries. Loaded
  /// once per build pass by the builder and shared across every
  /// visitor.
  final Catalog catalog;

  /// Diagnostics accumulated by all visitors during this build pass.
  final List<Issue> issues = [];

  /// `@PaywallSource`-annotated classes discovered during the visitor pass.
  final List<PaywallSourceFound> paywallSources = [];

  /// `@RestageWidget`-annotated classes discovered during the visitor pass.
  /// Empty until the customer-widget visitor runs.
  final List<WidgetEntry> widgetEntries = [];
}

/// Pluggable visitor step that walks a resolved [LibraryElement] during one
/// codegen build pass.
///
/// Each visitor sees the same [CodegenBuildState] and contributes either
/// diagnostics ([CodegenBuildState.issues]) or visitor-specific findings
/// to the typed accumulator fields on [CodegenBuildState].
///
/// Visitors run in registration order. A visitor that depends on another
/// visitor's findings must be registered after it.
///
// Intentionally a one-method interface (vs. a top-level function): visitors
// hold per-implementation configuration (analyzer helpers, registries) as
// fields, and each implementation contributes its own walker — the
// `@PaywallSource` walker and the `@RestageWidget` walker for
// customer-registered widgets. The interface shape is the shared contract.
// ignore: one_member_abstracts
@internal
abstract interface class LibraryVisitor {
  /// Walk the library on `state`, appending diagnostics and findings to it.
  Future<void> visit(CodegenBuildState state);
}

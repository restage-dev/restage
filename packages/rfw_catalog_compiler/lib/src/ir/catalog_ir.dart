import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/design_token_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/union_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/widget_ir.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Root compiler IR for one catalog emission.
@immutable
final class CatalogIR {
  /// Creates a catalog IR root.
  const CatalogIR({
    required this.generatedAt,
    required this.libraryVersions,
    required this.widgets,
    this.libraryCapabilityVersions = const {},
    this.structuredTypes = const [],
    this.unions = const [],
    this.designTokens = const [],
    this.flutterVersion,
  });

  /// ISO-8601 UTC timestamp for this compiler run.
  final String generatedAt;

  /// Package version by catalog library.
  final Map<WidgetLibrary, String> libraryVersions;

  /// Declared monotonic capability version by catalog library. A library absent
  /// from this map (the default for built-ins) declared none — recorded as a
  /// `null` `LibraryInfo.capabilityVersion`. Distinct from [libraryVersions]
  /// (the pub semver).
  final Map<WidgetLibrary, int> libraryCapabilityVersions;

  /// Widget IR entries.
  final List<WidgetIR> widgets;

  /// Structured type IR entries.
  final List<StructuredIR> structuredTypes;

  /// Union IR entries.
  final List<UnionIR> unions;

  /// Design token IR entries.
  final List<DesignTokenIR> designTokens;

  /// Flutter SDK version observed by the compiler, if available.
  final String? flutterVersion;
}

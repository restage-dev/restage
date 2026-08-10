import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One resolved authored Dart library in the current package build.
typedef ResolvedPackageLibrary = ({AssetId assetId, LibraryElement library});

/// Target-neutral `@RestageLibrary` facts for one complete package scan.
///
/// Ownership keys use the resolved declaration's fully-qualified identity,
/// not its bare class name. Values are distinct library namespaces sorted for
/// deterministic diagnostics and output.
@immutable
final class RestageWidgetPackageFacts {
  /// Creates immutable package facts.
  RestageWidgetPackageFacts({
    required Map<AssetId, LibraryWalkResult> walksByAsset,
    required Map<String, List<WidgetLibrary>> ownershipByWidget,
    required Set<String> widgetDeclarations,
  })  : walksByAsset = Map.unmodifiable(walksByAsset),
        widgetDeclarations = Set.unmodifiable(widgetDeclarations),
        ownershipByWidget = Map.unmodifiable({
          for (final entry in ownershipByWidget.entries)
            entry.key: List<WidgetLibrary>.unmodifiable(entry.value),
        });

  /// Each authored library's existing `@RestageLibrary` walk result.
  final Map<AssetId, LibraryWalkResult> walksByAsset;

  /// Exact widget declaration FQN to sorted, distinct owning libraries.
  final Map<String, List<WidgetLibrary>> ownershipByWidget;

  /// Exact declarations carrying the genuine customer-widget annotation.
  final Set<String> widgetDeclarations;

  /// Whether this package contains any customer-widget declarations.
  bool get hasWidgetDeclarations => widgetDeclarations.isNotEmpty;
}

/// Builds the one shared ownership index consumed by RFW, A2UI, and
/// Widgetbook before any target applies its own accepted-set rules.
RestageWidgetPackageFacts indexRestageWidgetPackage(
  Iterable<ResolvedPackageLibrary> sources,
) {
  final ordered = sources.toList()
    ..sort((left, right) => left.assetId.path.compareTo(right.assetId.path));
  final walksByAsset = <AssetId, LibraryWalkResult>{};
  final librariesByWidget = <String, Map<String, WidgetLibrary>>{};
  final widgetDeclarations = <String>{};

  for (final source in ordered) {
    final walk = walkRestageLibrary(
      barrel: source.library,
      barrelAssetId: source.assetId,
    );
    walksByAsset[source.assetId] = walk;
    for (final cls in source.library.classes) {
      if (firstAnnotationFromOriginAny(
            cls,
            const {'RestageWidget'},
            'package:rfw_catalog_schema',
          ) !=
          null) {
        widgetDeclarations.add(restageWidgetElementIdentity(cls));
      }
    }
    final declaration = walk.declaration;
    if (declaration == null) continue;
    for (final widgetClass in walk.widgetClasses) {
      final identity = restageWidgetElementIdentity(widgetClass);
      librariesByWidget
          .putIfAbsent(identity, () => <String, WidgetLibrary>{})
          .putIfAbsent(
            declaration.library.namespace,
            () => declaration.library,
          );
    }
  }

  return RestageWidgetPackageFacts(
    walksByAsset: walksByAsset,
    widgetDeclarations: widgetDeclarations,
    ownershipByWidget: {
      for (final entry in librariesByWidget.entries)
        entry.key: (entry.value.values.toList()
          ..sort(
            (left, right) => left.namespace.compareTo(right.namespace),
          )),
    },
  );
}

/// Exact analyzer declaration identity used at the ownership join seam.
String restageWidgetElementIdentity(ClassElement element) =>
    '${element.library.identifier}#${element.name ?? ''}';

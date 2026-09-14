import 'package:meta/meta.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Where a developer reads the catalog positions and how to measure app size.
const String kAppSizeDocsUrl =
    'https://docs.page/restage-dev/restage/delivery/app-size';

/// A widget group measured together in a historical reference build.
///
/// The groups share framework machinery. These whole-group figures are
/// reference estimates, not guaranteed marginal additions to another app's
/// release build.
@immutable
final class WidgetSizeGroup {
  /// Creates a group named [label], holding [entries] and measured at [bytes].
  const WidgetSizeGroup({
    required this.label,
    required this.entries,
    required this.bytes,
  });

  /// Plain-words name of the group.
  final String label;

  /// The namespaced catalog names the group covers.
  final List<String> entries;

  /// Compiled bytes attributed to the group in the historical reference build.
  final int bytes;
}

/// The measured widget groups, largest first.
///
/// Figures are compiled-code bytes from the app-size census of 2026-09-09,
/// taken from Android arm64 release builds with icon tree-shaking off. They
/// are approximate and move with the Flutter version.
const List<WidgetSizeGroup> kMeasuredWidgetGroups = [
  WidgetSizeGroup(
    label: 'text entry',
    entries: [
      'restage.material:TextField',
      'restage.cupertino:CupertinoTextField',
      'restage.cupertino:CupertinoSearchTextField',
    ],
    bytes: 781280,
  ),
  WidgetSizeGroup(
    label: 'Cupertino pickers',
    entries: [
      'restage.cupertino:CupertinoDatePicker',
      'restage.cupertino:CupertinoTimerPicker',
      'restage.cupertino:CupertinoPicker',
    ],
    bytes: 171776,
  ),
  WidgetSizeGroup(
    label: 'sheets and pager',
    entries: [
      'restage.material:RestageModalSheet',
      'restage.material:RestageDraggableSheet',
      'restage.material:RestagePager',
    ],
    bytes: 119392,
  ),
  WidgetSizeGroup(
    label: 'sliders',
    entries: [
      'restage.material:Slider',
      'restage.cupertino:CupertinoSlider',
    ],
    bytes: 107888,
  ),
  WidgetSizeGroup(
    label: 'switches',
    entries: [
      'restage.material:Switch',
      'restage.material:SwitchListTile',
      'restage.cupertino:CupertinoSwitch',
    ],
    bytes: 95504,
  ),
  WidgetSizeGroup(
    label: 'chips',
    entries: [
      'restage.material:Chip',
      'restage.material:ActionChip',
      'restage.material:ChoiceChip',
      'restage.material:FilterChip',
    ],
    bytes: 80496,
  ),
  WidgetSizeGroup(
    label: 'toggle and segmented buttons',
    entries: [
      'restage.material:RestageToggleButtons',
      'restage.material:RestageSegmentedButtonString',
    ],
    bytes: 74240,
  ),
  WidgetSizeGroup(
    label: 'tabs',
    entries: [
      'restage.material:DefaultTabController',
      'restage.material:TabBar',
      'restage.material:Tab',
    ],
    bytes: 72992,
  ),
  WidgetSizeGroup(
    label: 'Cupertino navigation',
    entries: [
      'restage.cupertino:CupertinoNavigationBar',
      'restage.cupertino:CupertinoPageScaffold',
    ],
    bytes: 52016,
  ),
  WidgetSizeGroup(
    label: 'dropdown',
    entries: ['restage.material:RestageDropdownString'],
    bytes: 45216,
  ),
  WidgetSizeGroup(
    label: 'images',
    entries: [
      'restage.core:Image',
      'restage.core:ImageAsset',
      'restage.core:FadeInImageAssetNetwork',
    ],
    bytes: 35760,
  ),
  WidgetSizeGroup(
    label: 'expansion tile',
    entries: ['restage.material:ExpansionTile'],
    bytes: 30928,
  ),
  WidgetSizeGroup(
    label: 'list rows',
    entries: [
      'restage.cupertino:CupertinoListSection',
      'restage.cupertino:CupertinoListSectionInsetGrouped',
      'restage.material:ListTile',
    ],
    bytes: 14496,
  ),
  WidgetSizeGroup(
    label: 'scrolling',
    entries: [
      'restage.material:Scrollbar',
      'restage.core:ListView',
      'restage.core:SingleChildScrollView',
    ],
    bytes: 7728,
  ),
  WidgetSizeGroup(
    label: 'backdrop filter',
    entries: ['restage.core:BackdropFilter'],
    bytes: 1392,
  ),
];

/// Where a build stands between the whole built-in catalog and the set this
/// package's own source draws on.
enum CatalogPosition {
  /// Generated registration includes complete built-in families by default.
  wholeCatalog,

  /// The generated registration installs the derived set, and the app's own
  /// source calls the built-in helper with its own family options.
  appInstalled,

  /// The generated registration installs the derived set, and nothing else
  /// hand-installs the built-in catalog.
  derived,
}

/// What this build derived and how to change it, in the two sentences every
/// build shows: what a surface delivered later can render, and what to do to
/// change it.
///
/// [builtInWidgetCount] is how many widgets the whole built-in catalog holds,
/// which is what [CatalogPosition.wholeCatalog] reports. The other two
/// positions report the derived count instead, because that is what the build
/// installs.
String summariseAppVocabulary(
  SurfaceVocabularyReferences vocabulary, {
  required CatalogPosition position,
  required int builtInWidgetCount,
}) {
  if (position == CatalogPosition.wholeCatalog) {
    return [
      'Restage: generated registration includes the whole built-in catalog '
          'by default: all $builtInWidgetCount built-in widgets and every '
          'built-in icon of both families. includeMaterial/includeCupertino '
          'can omit full family contributions while keeping app requirements.',
      'To install only what this build draws on, set catalog: derived under '
          'the restage_codegen:user_factories builder in build.yaml and call '
          'Restage.configureWithInstalledCatalog() after registration. The '
          'build then installs what this package draws in its own Dart plus '
          "what its compiled surfaces render. Measure this app's release "
          'builds to compare sizes. $kAppSizeDocsUrl',
    ].join('\n');
  }
  final widgets = vocabulary.widgetNames.where(_isBuiltIn).length;
  final icons = vocabulary.orderedIcons.length;
  final lines = <String>[
    'Restage: a surface delivered to this app can render $widgets built-in '
        '${_noun(widgets, 'widget')} and $icons ${_noun(icons, 'icon')}: '
        'the ones this package draws in its own Dart, plus the ones its '
        'compiled surfaces render.',
  ];
  if (position == CatalogPosition.appInstalled) {
    lines.add(
      'This app also calls RestageWidgetLibraries.builtIn(); the families '
      'included depend on its includeMaterial/includeCupertino arguments. '
      '$kAppSizeDocsUrl',
    );
  } else {
    lines.add(
      'This build opted down with catalog: derived. Call '
      'Restage.configureWithInstalledCatalog() after registration so unused '
      'catalog entries can be removed. To render more, draw '
      'the widget once in a @Screen the app never mounts, or drop the '
      "option and go back to the whole catalog. Measure this app's release "
      'builds to compare sizes. Run the build with --verbose for historical '
      'widget-group reference estimates. $kAppSizeDocsUrl',
    );
  }
  return lines.join('\n');
}

/// The omitted widget groups, with historical reference size estimates.
///
/// Empty whenever the whole catalog is in the build, and when every measured
/// group is already in [vocabulary].
List<String> describeMissingWidgetGroups(
  SurfaceVocabularyReferences vocabulary, {
  required CatalogPosition position,
}) {
  if (position != CatalogPosition.derived) return const [];
  final lines = _missingGroupLines(vocabulary);
  if (lines.length == 1) return const [];
  return lines;
}

/// Historical reference estimates for groups absent from [vocabulary].
/// Partly present groups are omitted: each figure covers the whole group.
List<String> _missingGroupLines(SurfaceVocabularyReferences vocabulary) {
  bool absent(WidgetSizeGroup group) =>
      group.entries.every((entry) => !vocabulary.widgetNames.contains(entry));
  final missing = kMeasuredWidgetGroups.where(absent).toList();
  if (missing.isEmpty) return const ['Every measured widget group is in it.'];
  return [
    'Historical reference estimates; actual additions depend on this app:',
    for (final group in missing)
      '  ${_kilobytes(group.bytes)}  ${group.label} '
          '(${group.entries.map(_plainName).join(', ')})',
  ];
}

/// Whether [qualifiedName] names a widget of a built-in library. A custom
/// widget reaches the runtime through the generated factories instead.
bool _isBuiltIn(String qualifiedName) {
  final separator = qualifiedName.indexOf(':');
  if (separator <= 0) return false;
  final namespace = qualifiedName.substring(0, separator);
  return WidgetLibrary.builtInByNamespace(namespace) != null;
}

/// The widget name without its namespace.
String _plainName(String qualifiedName) =>
    qualifiedName.substring(qualifiedName.indexOf(':') + 1);

String _kilobytes(int bytes) => '${(bytes / 1024).round()} KB'.padLeft(6);

String _noun(int amount, String singular) =>
    amount == 1 ? singular : '${singular}s';

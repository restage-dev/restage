import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';

/// The app-wide registration of [package]'s islands from its compiler
/// [sites]: one library holding every mount's own island registration, plus
/// `restageIslandPreviews`, the mount-free builders a render bundle supplies
/// the island scope with. Null when there are no islands.
AppWidgetRegistrationSource? islandRegistration(
  String package,
  List<SplitSite> sites, {
  Map<String, List<String>> surfaceIslands = const {},
}) {
  final islands = {
    for (final site in sites)
      if (site.kind == SplitSiteKind.island) site.name: site,
  };
  if (islands.isEmpty) return null;
  final names = islands.keys.toList()..sort();
  final libraries = {
    for (final name in names) _libraryOf(islands[name]!),
  }.toList()..sort();
  final prefixes = {
    for (final (index, library) in libraries.indexed) library: 'island$index',
  };
  final byMount = <String, List<SplitSite>>{};
  for (final site in islands.values) {
    (byMount[site.mount] ??= []).add(site);
  }
  final declarations = StringBuffer()
    ..writeln()
    ..writeln("/// Every island's builder outside its screen, for previews.")
    ..writeln('const Map<String, LocalWidgetBuilder> restageIslandPreviews = {')
    ..writeAll([
      for (final qualified in names)
        '  ${dartStringLiteral(_nameOf(qualified))}: '
            '${prefixes[_libraryOf(islands[qualified]!)]}.'
            'restagePreview\$${_nameOf(qualified)},\n',
    ])
    ..writeln('};')
    ..writeln()
    ..writeln()
    ..writeln(
      "/// Each surface's own island builders, by `<surfaceType>/<slug>`.",
    )
    ..writeln(
      'const Map<String, Map<String, LocalWidgetBuilder>> '
      'restageSurfaceIslandPreviews = {',
    )
    ..writeAll([
      for (final surface in surfaceIslands.keys.toList()..sort())
        '  ${dartStringLiteral(surface)}: {${[
          for (final qualified in names)
            if (surfaceIslands[surface]!.contains(qualified)) '${dartStringLiteral(_nameOf(qualified))}: '
                  '${prefixes[_libraryOf(islands[qualified]!)]}.'
                  'restagePreview\$${_nameOf(qualified)}',
        ].join(', ')}},\n',
    ])
    ..writeln('};')
    ..writeln()
    ..writeln(
      "/// [child] with [surface]'s own islands built outside its screen,",
    )
    ..writeln("/// or every island when the surface isn't known.")
    ..writeln(
      'Widget restageIslandPreviewScope(String? surface, Widget child) =>',
    )
    ..writeln('    RestageIslandScope(')
    ..writeln(
      '      builders: restageSurfaceIslandPreviews[surface] ?? '
      'restageIslandPreviews,',
    )
    ..writeln('      child: child,')
    ..writeln('    );');
  // Each island registers in its own library: another package's split
  // widget brings that package's islands.
  final byNamespace = <String, List<String>>{};
  for (final sites in byMount.values) {
    final namespace = _namespaceOf(sites.first.name);
    (byNamespace[namespace] ??= []).add(
      '${prefixes[_libraryOf(sites.first)]}.${islandRegistrationName([for (final site in sites) _nameOf(site.name)])}',
    );
  }
  final registrations = StringBuffer();
  for (final namespace in byNamespace.keys.toList()..sort()) {
    registrations
      ..writeln('Restage.registerWidgetLibrary(')
      ..writeln('  WidgetLibrary.custom(${dartStringLiteral(namespace)}),')
      ..writeln('  widgets: [')
      ..writeAll([
        for (final mount in byNamespace[namespace]!..sort())
          '    ...$mount.widgets,\n',
      ])
      ..writeln('  ],')
      ..writeln(');');
  }
  return (
    imports: [
      "import 'package:flutter/widgets.dart';",
      for (final library in libraries)
        'import ${dartStringLiteral(library)} as ${prefixes[library]};',
    ],
    declarations: declarations.toString(),
    registrations: registrations.toString(),
  );
}

/// The public constant registering the islands of the mount [mountName].
/// The public constant registering one mount's [islands], named after the
/// first, since island names are unique in the package.
String islandRegistrationName(Iterable<String> islands) =>
    'restageIslands\$${(islands.toList()..sort()).first}';

/// The registered factory of island [name], in the library declaring it.
String islandFactoryName(String name) => '_restageIsland\$$name';

/// The factory of island [name]: it builds the island from the nearest
/// island scope and, outside [mount], names the [widget] at [location] that
/// only [mount] provides; [step] when [mount] is a flow's widget. [sdk] and
/// [flutter] prefix the symbols it uses.
String islandFactorySource(
  String name, {
  required String widget,
  required String location,
  required String mount,
  bool step = false,
  String sdk = '',
  String flutter = '',
}) {
  final missing =
      '`$widget` ($location) needs app code that only `$mount` '
      'provides. Try using `$mount` to build this ${step ? 'flow' : 'screen'}.';
  return '${flutter}Widget ${islandFactoryName(name)}('
      '${flutter}BuildContext context, ${sdk}DataSource source) =>\n'
      '    ${sdk}RestageIslandScope.build(${dartStringLiteral(name)}, '
      '${dartStringLiteral(missing)}, context, source);';
}

/// A constant registration of a surface's own [islands] in [library], whose
/// factories [islandFactorySource] declares; [sdk] prefixes its symbols.
String islandLibraryRegistrationSource(
  String library,
  Iterable<String> islands,
  String sdk,
) =>
    '${sdk}RestageWidgetLibraryRegistration.constant('
    'library: ${sdk}WidgetLibrary.custom(${dartStringLiteral(library)}), '
    'widgets: [${[
      for (final name in islands) '${sdk}RestageWidgetFactory(name: ${dartStringLiteral(name)}, '
            'builder: ${islandFactoryName(name)})',
    ].join(', ')}], islands: true)';

String _libraryOf(SplitSite site) =>
    site.surface.substring(0, site.surface.lastIndexOf('#'));

String _namespaceOf(String qualified) =>
    qualified.substring(0, qualified.indexOf(':'));

String _nameOf(String qualified) =>
    qualified.substring(qualified.indexOf(':') + 1);

// What a compiled publication asks of its host app, and the build error when
// that cannot be worked out.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _package = 'apps_examples';
const _catalogAsset = '$_package|lib/src/widget_catalog/catalog.json';

const _widgets = '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ds'),
  capabilityVersion: 1,
)
const acmeLibrary = 0;

@RestageWidget(name: 'StreakBadge',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'A streak badge.')
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, this.count});
  @RestageProperty(description: 'The streak length.')
  final int? count;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _Painter());
}

class _Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_Painter oldDelegate) => false;
}
''';

const _surfaces = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'widgets.dart';

part 'restage.generated/surfaces.restage.g.dart';

@Paywall(id: 'offer')
final class Offer extends StatelessWidget {
  const Offer({super.key});

  static const start = SurfaceEvent<void>('start');

  @override
  Widget build(BuildContext context) => Column(children: [
        const StreakBadge(count: 3),
        TextButton(onPressed: paywallEvent('close'), child: const Text('x')),
        FilledButton(
          onPressed: paywallEvent('start', args: {'plan': 'yearly'}),
          child: const Text('Start'),
        ),
      ]);
}

final class Row0 {
  const Row0({required this.id, required this.title});
  final String id;
  final String title;
}

@Screen(id: 'rows', surface: Surface.general)
final class Rows extends StatelessWidget {
  const Rows({required this.rows, super.key});
  final List<Row0> rows;

  static const pick = SurfaceEvent<String>('pick');
  static const typed = SurfaceEvent<String>('typed');

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(onChanged: surfaceEvent(typed)),
        for (final row in rows)
          InkWell(onTap: surfaceEvent(pick, row.id), child: Text(row.title)),
      ]);
}
''';

const _unprojectable = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/goal.restage.g.dart';

@Screen(id: 'goal', surface: Surface.general)
final class Goal extends StatelessWidget {
  const Goal({super.key});

  static const chosen = SurfaceEvent<String>('chosen');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: surfaceEvent(chosen),
        child: const Text('Go'),
      );
}
''';

Future<String> _catalog() async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  final result = await testBuilder(
    const UserCatalogJsonBuilder(BuilderOptions.empty),
    {'$_package|lib/features/widgets.dart': _widgets},
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return readerWriter.testing.readString(AssetId.parse(_catalogAsset));
}

Future<({TestBuilderResult result, TestReaderWriter readerWriter})> _compile(
  Map<String, String> sources,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
    sources,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  return (result: result, readerWriter: readerWriter);
}

Map<String, Object?> _fit(TestReaderWriter readerWriter, String slug) {
  final bundle = jsonDecode(
    readerWriter.testing.readString(
      AssetId(_package, kRestageSurfacePublicationCompilerBundlePath),
    ),
  );
  Map<String, Object?>? found;
  void visit(Object? value) {
    if (value is Map<String, Object?>) {
      if (value['slug'] == slug && value['fitRequirement'] is Map) {
        found ??= value['fitRequirement']! as Map<String, Object?>;
      }
      value.values.forEach(visit);
    } else if (value is List) {
      value.forEach(visit);
    }
  }

  visit(bundle);
  return found ?? fail('no fit requirement for $slug');
}

const _acmeBadge = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A badge from the app's own widget library, rendered by the app.
@RestageWidget()
class AcmeBadge extends StatefulWidget {
  const AcmeBadge({super.key, required this.label});
  @RestageProperty(description: 'The badge text.')
  final String label;
  @override
  State<AcmeBadge> createState() => _AcmeBadgeState();
}

class _AcmeBadgeState extends State<AcmeBadge> {
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _AcmeBadgePainter(), child: Text(widget.label));
}

class _AcmeBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawCircle(Offset.zero, size.shortestSide, Paint());
  @override
  bool shouldRepaint(_AcmeBadgePainter oldDelegate) => false;
}
''';

const _acmeLibrary = '''
import 'package:restage/restage.dart';
export 'widgets/acme_badge.dart';
final class AcmeWidgets extends WidgetLibrary {
  const AcmeWidgets();
  @override
  final String namespace = 'acme.widgets';
}
const WidgetLibrary acmeWidgets = AcmeWidgets();
@RestageLibrary(library: acmeWidgets, capabilityVersion: 2)
const acmeWidgetCatalog = 0;
''';

const _acmeSurfaces = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import '../acme_widgets.dart';
part 'restage.generated/acme_surfaces.restage.g.dart';

@Screen(id: 'acme_screen', surface: Surface.general, version: 1, minClient: 3)
final class AcmeScreen extends StatelessWidget {
  const AcmeScreen({super.key});
  @override
  Widget build(BuildContext context) => const AcmeBadge(label: 'Hello');
}

@Paywall(id: 'acme_paywall')
final class AcmePaywall extends StatelessWidget {
  const AcmePaywall({super.key});
  @override
  Widget build(BuildContext context) => const AcmeBadge(label: 'Hello');
}
''';

void main() {
  test('an app library widget behind a barrel asks for its library', () async {
    final sources = {
      '$_package|lib/widgets/acme_badge.dart': _acmeBadge,
      '$_package|lib/acme_widgets.dart': _acmeLibrary,
    };
    final catalogReader = await readerWriterWithFilesystemSources(
      rootPackage: _package,
      includeFlutter: true,
    );
    final catalogResult = await testBuilder(
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      sources,
      rootPackage: _package,
      readerWriter: catalogReader,
      flattenOutput: true,
    );
    expect(catalogResult.succeeded, isTrue);
    final compiled = await _compile({
      ...sources,
      '$_package|lib/surfaces/acme_surfaces.dart': _acmeSurfaces,
      _catalogAsset:
          catalogReader.testing.readString(AssetId.parse(_catalogAsset)),
    });
    expect(
      compiled.result.succeeded,
      isTrue,
      reason: compiled.result.errors.join('\n'),
    );
    for (final slug in ['acme_screen', 'acme_paywall']) {
      final capabilities = _fit(compiled.readerWriter, slug)['capabilities']!
          as Map<String, Object?>;
      expect(
        capabilities['requiredLibraries'],
        contains(
          allOf(
            containsPair('namespace', 'acme.widgets'),
            containsPair('minVersion', 2),
          ),
        ),
        reason: slug,
      );
    }
  });

  late TestBuilderResult result;
  late TestReaderWriter readerWriter;

  setUpAll(() async {
    final catalog = await _catalog();
    final compiled = await _compile({
      '$_package|lib/features/widgets.dart': _widgets,
      '$_package|lib/features/surfaces.dart': _surfaces,
      _catalogAsset: catalog,
    });
    result = compiled.result;
    readerWriter = compiled.readerWriter;
  });

  test('every surface projects a fit', () {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });

  test('a custom widget asks for its library, not a vocabulary name', () {
    final fit = _fit(readerWriter, 'offer');
    final capabilities = fit['capabilities']! as Map<String, Object?>;
    expect(
      capabilities['requiredLibraries'],
      contains(containsPair('namespace', 'acme.ds')),
    );
    expect(jsonEncode(fit['requiredVocabulary']), isNot(contains('acme.ds')));
  });

  test('a paywall asks for no typed events', () {
    final fit = _fit(readerWriter, 'offer');
    expect((fit['emittedEvents']! as Map)['events'], isEmpty);
  });

  test('loop data and a value callback satisfy typed events', () {
    final fit = _fit(readerWriter, 'rows');
    final ids = [
      for (final event in (fit['emittedEvents']! as Map)['events'] as List)
        (event as Map)['id'],
    ];
    expect(ids, containsAll(<String>['pick', 'typed']));
  });

  test('a surface whose fit does not project fails the build', () async {
    final compiled = await _compile({
      '$_package|lib/features/goal.dart': _unprojectable,
    });
    expect(compiled.result.succeeded, isFalse);
    expect(
      compiled.result.errors.join('\n'),
      allOf(
        contains('[${IssueCode.surfaceFitUnavailable.name}] '
            'lib/features/goal.dart:'),
        contains('chosen'),
      ),
    );
  });
}

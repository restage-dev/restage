// What the two opt-in catalog indexes must keep resolving once they stop
// resolving everything.
//
// The native screen index admits a source on three different grounds, and only
// two of them are annotations. The third is a location: a library at a
// deprecated screen path goes through screen admission whether or not it is
// annotated, and that is where its syntax errors are reported. A filter keyed
// on annotations alone deletes that diagnostic — the build stops failing,
// which reads as an improvement and is not one.
//
// The Widgetbook catalog index has the ordinary shape and is here for the one
// case scoping is most likely to lose: a declaration written in a `part`.
//
// The expectations below were captured from the indexes BEFORE they were
// scoped, not written from the design.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'index_probe_helpers.dart';

/// Syntactically invalid, and spells no Restage identifier anywhere.
const String _broken = '''
class Broken {
  const Broken(
}
''';

/// A canonical screen declared in a part of a library that spells nothing
/// itself, at a path the deprecated location rule does not cover.
const String _canonicalPartHost = '''
library acme_host;

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as rs;

part 'restage.generated/host.restage.g.dart';
part 'greeting_part.dart';
''';

const String _canonicalPart = '''
part of 'host.dart';

@rs.Screen(id: 'greeting')
class GreetingScreen extends StatelessWidget {
  const GreetingScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const String _widgetPartHost = '''
library acme_widgets;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'card_part.dart';
''';

const String _widgetPart = '''
part of 'host.dart';

/// A customer card declared in a part.
@RestageWidget(
  library: WidgetLibrary.custom('acme.product'),
  description: 'A customer card declared in a part.',
)
class PartCard {
  const PartCard();
}
''';

void main() {
  group('native screen index', () {
    for (final consumer in NativeScreenSourceConsumer.values) {
      test(
        '${consumer.name}: an unannotated library at a deprecated screen path '
        'is still put through screen admission',
        () async {
          final probe = await _nativeIndex(
            {'lib/onboarding/screens/plain.dart': _broken},
            consumer,
          );

          // Captured from the unscoped index: the build fails, and every issue
          // is the syntax error in a file that names no annotation at all.
          expect(probe.succeeded, isFalse);
          expect(
            probe.errors,
            allOf(
              contains('[malformedSourceInput]'),
              contains('lib/onboarding/screens/plain.dart'),
              contains('native screen source issue'),
            ),
          );
        },
      );

      test(
        '${consumer.name}: the same file outside that path is not admitted',
        () async {
          final probe = await _nativeIndex(
            {'lib/widgets/plain.dart': _broken},
            consumer,
          );

          // Also captured: identical content, different location, no
          // diagnostic. This is the pair that makes the test above mean
          // something — drop the location rule and the two become the same.
          expect(probe.succeeded, isTrue, reason: probe.errors);
        },
      );

      test(
        '${consumer.name}: a canonical screen declared in a part is found',
        () async {
          final probe = await _nativeIndex(
            {
              'lib/screens/host.dart': _canonicalPartHost,
              'lib/screens/greeting_part.dart': _canonicalPart,
            },
            consumer,
          );

          expect(probe.succeeded, isTrue, reason: probe.errors);
          expect(probe.screens, contains('greeting'));
        },
      );
    }
  });

  group('widgetbook catalog index', () {
    test('a syntax error in a token-free file is no longer reported', () async {
      // A deliberate, documented behaviour change, pinned so it is a decision
      // rather than a fact about whatever the code currently does. Captured
      // before the scoping landed, this exact fixture failed the build with
      // three `[malformedSourceInput]` issues; the Dart toolchain reports the
      // error either way, and the index no longer analyses a file that names
      // no annotation. The native index has the location rule above for the
      // one path where the diagnostic still matters; this lane has none.
      final widgets = await _widgetbookIndex({
        'lib/widgets/plain.dart': _broken,
      });

      expect(widgets, isEmpty);
    });

    test('a customer widget declared in a part is found', () async {
      final widgets = await _widgetbookIndex({
        'lib/widgets/host.dart': _widgetPartHost,
        'lib/widgets/card_part.dart': _widgetPart,
        'lib/models/order.dart': 'class Order {}',
      });

      expect(widgets, contains('PartCard'));
    });
  });
}

Future<({bool succeeded, String errors, List<String> screens})> _nativeIndex(
  Map<String, String> dartSources,
  NativeScreenSourceConsumer consumer,
) async {
  final sources = _packageSources(dartSources);
  final readerWriter = await _writer(sources);
  var screens = <String>[];
  final result = await runWithNativeScreenPackageGraphForTesting(
    packageGraphSource: _dependencyGraph,
    body: () => testBuilder(
      _NativeIndexProbe(consumer: consumer, onScreens: (ids) => screens = ids),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
    ),
  );
  return (
    succeeded: result.succeeded,
    errors: result.errors.join('\n'),
    screens: screens,
  );
}

Future<List<String>> _widgetbookIndex(Map<String, String> dartSources) async {
  final sources = _packageSources(dartSources);
  final readerWriter = await _writer(sources);
  var widgets = <String>[];
  final result = await testBuilder(
    _WidgetbookIndexProbe((names) => widgets = names),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return widgets;
}

/// The direct-dependency metadata the index reads after identity is settled.
final String _dependencyGraph = nativeScreenPackageGraph(
  const {'flutter', 'restage', 'rfw_catalog_schema'},
);

Map<String, String> _packageSources(Map<String, String> dartSources) => {
      'apps_examples|pubspec.yaml': 'name: apps_examples\n'
          'dependencies:\n'
          '  flutter: any\n'
          '  restage: any\n'
          '  rfw_catalog_schema: any\n',
      'apps_examples|.dart_tool/package_graph.json': _dependencyGraph,
      for (final entry in dartSources.entries)
        'apps_examples|${entry.key}': entry.value,
    };

Future<TestReaderWriter> _writer(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

final class _NativeIndexProbe implements Builder {
  const _NativeIndexProbe({required this.consumer, required this.onScreens});

  final NativeScreenSourceConsumer consumer;
  final void Function(List<String>) onScreens;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['native_index_probe.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadNativeScreenSourceIndex(
      buildStep,
      consumer: consumer,
    );
    onScreens([for (final screen in index.screens) screen.id]);
  }
}

final class _WidgetbookIndexProbe implements Builder {
  const _WidgetbookIndexProbe(this.onWidgets);

  final void Function(List<String>) onWidgets;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['widgetbook_index_probe.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadWidgetbookCatalogSourceIndex(buildStep);
    onWidgets([for (final widget in index.widgets) widget.entry.name]);
  }
}

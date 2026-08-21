// Declaration shapes the package source roster must keep finding once it stops
// resolving every file in the package.
//
// The roster is the discovery seam the surface compiler and every emitter read
// from, so a source it misses is a surface that silently stops being built.
// Both shapes here spell the annotation somewhere a naive filter would not
// look: behind an import prefix, and inside a `part` whose owning library
// names no Restage identifier at all.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('package source roster', () {
    test('admits a screen annotated behind an import prefix', () async {
      final ids = await _rosterSourceIds({
        'lib/screens/welcome.dart': '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as rs;

part 'restage.generated/welcome.restage.g.dart';

@rs.Screen(id: 'welcome')
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
        'lib/models/order.dart': '''
class Order {
  const Order(this.id);

  final String id;
}
''',
      });

      expect(ids, contains('welcome'));
    });

    test('admits a screen annotated with an alias declared elsewhere',
        () async {
      final ids = await _rosterSourceIds({
        'lib/screen_annotations.dart': '''
import 'package:restage/restage.dart';

const welcomeScreen = Screen(id: 'welcome');
''',
        'lib/screens/welcome.dart': '''
import 'package:flutter/widgets.dart';

import '../screen_annotations.dart';

part 'restage.generated/welcome.restage.g.dart';

@welcomeScreen
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
      });

      expect(ids, contains('welcome'));
    });

    test('admits a screen declared inside a part of an unannotated library',
        () async {
      final ids = await _rosterSourceIds({
        // Nothing in this library spells a Restage identifier. Its declaration
        // is entirely in the part below.
        'lib/screens/host.dart': '''
library acme_host;

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as rs;

part 'restage.generated/host.restage.g.dart';
part 'greeting_part.dart';
''',
        'lib/screens/greeting_part.dart': '''
part of 'host.dart';

@rs.Screen(id: 'greeting')
class GreetingScreen extends StatelessWidget {
  const GreetingScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
      });

      expect(ids, contains('greeting'));
    });

    test('admits a screen declared inside a generated part', () async {
      // The surface lane never resolves a `.g.dart` — it is not an authored
      // library — but one can still be a `part`, and its declarations reach
      // the roster through the owner. Scanning for tokens therefore has to
      // cover files the walk will not resolve.
      final ids = await _rosterSourceIds({
        'lib/screens/host.dart': '''
library acme_host;

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as rs;

part 'restage.generated/host.restage.g.dart';
part 'greeting.g.dart';
''',
        'lib/screens/greeting.g.dart': '''
part of 'host.dart';

@rs.Screen(id: 'greeting')
class GreetingScreen extends StatelessWidget {
  const GreetingScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
      });

      expect(ids, contains('greeting'));
    });
  });
}

/// Builds [sources] with the roster builder and returns the admitted source
/// ids.
Future<List<String>> _rosterSourceIds(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );

  final result = await testBuilder(
    restageSourceRosterBuilder(BuilderOptions.empty),
    {
      for (final entry in sources.entries)
        'apps_examples|${entry.key}': entry.value,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));

  final index = jsonDecode(
    readerWriter.testing.readString(
      AssetId('apps_examples', 'assets/restage/source-index.json'),
    ),
  ) as Map<String, Object?>;
  return [
    for (final source in index['sources']! as List<Object?>)
      (source! as Map<String, Object?>)['id']! as String,
  ];
}

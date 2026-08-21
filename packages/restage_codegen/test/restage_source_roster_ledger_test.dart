// When the roster writes its two ledger files into the package.
//
// Both land in the customer's own tree rather than the build cache, so a
// package that declares no Restage source should not acquire them: two files
// recording nothing is not a useful artifact, it is a diff. Once there is
// something to record — a declaration, or a problem with one — the ledgers are
// written exactly as before, including on the failing path, where they are
// materialized before the build is failed.

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final AssetId _sourceIndex =
    AssetId('apps_examples', 'assets/restage/source-index.json');
final AssetId _outputRoster =
    AssetId('apps_examples', 'assets/restage/output-roster.json');

const String _screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome')
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

/// A `@Screen` on a class that is not a widget: admitted as a declaration
/// attempt, then rejected.
const String _invalidScreen = '''
import 'package:restage/restage.dart';

@Screen(id: 'broken')
class NotAWidget {
  const NotAWidget();
}
''';

const String _ordinaryCode = '''
class Order {
  const Order(this.id);

  final String id;
}
''';

void main() {
  group('source roster ledgers', () {
    test('are not written for a package with no Restage source', () async {
      final readerWriter = await _run(
        const {'lib/models/order.dart': _ordinaryCode},
        succeeds: true,
      );

      expect(readerWriter.testing.exists(_sourceIndex), isFalse);
      expect(readerWriter.testing.exists(_outputRoster), isFalse);
    });

    test('are written for a package with a declaration', () async {
      final readerWriter = await _run(
        const {
          'lib/models/order.dart': _ordinaryCode,
          'lib/screens/welcome.dart': _screen,
        },
        succeeds: true,
      );

      expect(readerWriter.testing.exists(_sourceIndex), isTrue);
      expect(readerWriter.testing.exists(_outputRoster), isTrue);
      expect(
        readerWriter.testing.readString(_sourceIndex),
        contains('welcome'),
      );
    });

    test('are written before an invalid roster fails the build', () async {
      final readerWriter = await _run(
        const {'lib/screens/broken.dart': _invalidScreen},
        succeeds: false,
      );

      expect(readerWriter.testing.exists(_sourceIndex), isTrue);
      expect(readerWriter.testing.exists(_outputRoster), isTrue);
      expect(
        readerWriter.testing.readString(_sourceIndex),
        contains('"valid": false'),
      );
    });
  });
}

Future<TestReaderWriter> _run(
  Map<String, String> sources, {
  required bool succeeds,
}) async {
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
  expect(
    result.succeeded,
    succeeds,
    reason: result.errors.join('\n'),
  );
  return readerWriter;
}

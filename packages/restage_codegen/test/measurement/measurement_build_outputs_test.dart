// A build that fails keeps the outputs the last build wrote, and an inherited
// build that reads a Widget getter is measured.

import 'dart:convert';

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/output_builder.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

const _package = 'apps_examples';
const _policyOptions = BuilderOptions({
  kMeasurementMinimumClientOption: 1,
  kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
  kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
});

const _go = '''
      TextButton(onPressed: _turnOn, child: const Text('go')),
''';
// A measured callback that runs a different handler in each arm refuses.
const _stopRefusing = '''
      TextButton(onPressed: _on ? _off : _turnOn, child: const Text('stop')),
''';
const _stop = '''
      TextButton(onPressed: _off, child: const Text('stop')),
''';

String _x(String children) =>
    """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/x.restage.g.dart';

@Screen(id: 'x', surface: Surface.onboarding)
final class XPage extends StatefulWidget {
  const XPage({super.key});
  @override
  State<XPage> createState() => _XPageState();
}

class _XPageState extends State<XPage> {
  bool _on = false;
  void _off() => setState(() => _on = false);
  void _turnOn() => setState(() => _on = true);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(_on ? 'on' : 'off'),
$children    ],
  );
}
""";

String _good({String label = 'ok', String extra = ''}) =>
    """
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/good.restage.g.dart';

@Screen(id: 'good', surface: Surface.onboarding)
final class GoodPage extends StatelessWidget {
  const GoodPage({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('good'),
      TextButton(onPressed: () {}, child: const Text('$label')),
    ],
  );
}
$extra""";

// A widget the app registers in its own catalog library.
const _chip = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget(
  name: 'ProbeChip',
  library: WidgetLibrary.custom('app.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip.',
)
class ProbeChip extends StatelessWidget {
  const ProbeChip({super.key, required this.label});

  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

// good without its annotation. The build no longer publishes it.
const _goodRemoved = '''
import 'package:flutter/material.dart';

final class GoodPage extends StatelessWidget {
  const GoodPage({super.key});
  @override
  Widget build(BuildContext context) => const Text('good');
}
''';

const _broken = "\nfinal int brokenOnPurpose = 'x';\n";

const _inherit = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/inherit.restage.g.dart';

abstract class BasePage extends StatelessWidget {
  const BasePage({super.key});
  Widget get badge => const Text('base badge');
  @override
  Widget build(BuildContext context) => Column(
    children: [
      badge,
      TextButton(onPressed: () {}, child: const Text('go')),
    ],
  );
}

@Screen(id: 'inherit', surface: Surface.onboarding)
final class InheritPage extends BasePage {
  const InheritPage({super.key});
  @override
  Widget get badge => const Text('page badge');
}
''';

void main() {
  test('an inherited build that reads a Widget getter is measured', () async {
    final built = await _build(
      x: _x(_go + _stop),
      extra: {'lib/inherit.dart': _inherit},
    );
    expect(built.succeeded, isTrue, reason: built.errors.join('\n'));
    expect(
      built.warnings.where((w) => w.contains('Measurement is unavailable')),
      isEmpty,
    );
    expect(
      built.ledger!.publications.map((p) => p.selector.slug),
      contains('inherit'),
    );
  });

  test(
    'a refused surface fails the build, and every surface keeps its '
    'previous outputs',
    () async {
      final prior = await _settledOutputs();
      expect(prior.keys, containsAll(_kParts));

      // good's changed label would change its outputs if it built.
      final failed = await _build(
        x: _x(_go + _stopRefusing),
        good: _good(label: 'changed'),
        priorOutputs: prior,
      );
      _expectFailedKeeping(
        failed,
        prior,
        error: contains('can run only one handler'),
        paths: [..._kOutputs, ..._kMetadata, ..._kParts],
      );
    },
  );

  test(
    'a build whose generated code check fails keeps the previous outputs',
    () async {
      final prior = await _settledOutputs();

      // A changed label would change the outputs, and the library no longer
      // compiles.
      final failed = await _build(
        x: _x(_go + _stop),
        good: _good(label: 'changed', extra: _broken),
        priorOutputs: prior,
      );
      _expectFailedKeeping(
        failed,
        prior,
        error: startsWith("lib/good.dart doesn't compile: lib/good.dart:"),
        paths: [..._kOutputs, ..._kMetadata],
      );
      expect(failed.stamp['errors'], hasLength(1));
    },
  );

  test(
    "a check failure in a build that removes a surface keeps that surface's "
    'bundle',
    () async {
      final prior = await _settledOutputs();

      final failed = await _build(
        x: _x(_go + _stop) + _broken,
        good: _goodRemoved,
        priorOutputs: prior,
      );
      _expectFailedKeeping(
        failed,
        prior,
        error: startsWith("lib/x.dart doesn't compile: lib/x.dart:"),
        paths: [..._kOutputs, ..._kMetadata],
      );
      expect(failed.stamp['errors'], hasLength(1));
    },
  );

  test(
    'the outputs step alone keeps the outputs of a failed build and its '
    'errors, and fails the build',
    () async {
      final refused = await _build(
        x: _x(_go + _stopRefusing),
        priorOutputs: await _settledOutputs(),
      );
      expect(refused.succeeded, isFalse);
      final prior = refused.outputs();
      expect(prior.keys, containsAll([..._kOutputs, ..._kMetadata, _kStamp]));

      // Only the outputs step runs again after a developer deletes one output.
      const deleted = '.restage/build/metadata/restage.outputs.json';
      final rerun = await _rerunOutputs(
        {...prior}..remove(deleted),
        sources: {
          'lib/x.dart': _x(_go + _stopRefusing),
          'lib/good.dart': _good(),
          'lib/chip.dart': _chip,
        },
      );
      expect(rerun.succeeded, isFalse);
      expect(rerun.severe.join('\n'), contains('can run only one handler'));
      for (final path in [..._kOutputs, ..._kMetadata, _kStamp]) {
        if (path == deleted) continue;
        expect(rerun.outputs[path], orderedEquals(prior[path]!), reason: path);
      }
    },
  );

  test(
    "a compiler that stops doesn't record the last build's errors",
    () async {
      final refused = await _build(
        x: _x(_go + _stopRefusing),
        priorOutputs: await _settledOutputs(),
      );
      expect(refused.succeeded, isFalse);
      final prior = refused.outputs();

      final stopped = await _build(
        x: _x(_go + _stop),
        priorOutputs: prior,
        ledgerWriter: _stopLedgerSource,
      );
      _expectFailedKeeping(
        stopped,
        prior,
        error: equals(
          "Restage has no result from compiling the package's surfaces. Try "
          'running `dart run build_runner clean`, then '
          '`dart run build_runner build`.',
        ),
        paths: [..._kOutputs, ..._kMetadata],
      );
      expect(stopped.stamp['errors'], hasLength(1));
    },
  );
}

// The outputs a lifecycle command and a push read, besides the stamp.
const _kOutputs = [
  '.restage/build/metadata/restage.publication.json',
  '.restage/build/metadata/restage.outputs.json',
  '.restage/build/metadata/restage.measurement.index.json',
  '.restage/build/bundles/lib/good.rsbundle',
  '.restage/build/bundles/lib/x.rsbundle',
];

// The package metadata a custom widget and a push's images add.
const _kMetadata = [
  '.restage/build/widget_catalog/catalog.json',
  '.restage/build/metadata/restage.analytics-id.metadata.json',
  '.restage/build/metadata/restage.capture.json',
];

const _kStamp = '.restage/build/metadata/restage.build.json';

// The generated parts, which a compiler refusal restores too.
const _kParts = [
  'lib/restage.generated/good.restage.g.dart',
  'lib/restage.generated/x.restage.g.dart',
];

typedef _Built = ({
  bool succeeded,
  List<String> errors,
  Map<String, Object?> stamp,
  RestageMeasurementCompilerOutputV1? ledger,
  Map<String, List<int>> Function() outputs,
  List<String> warnings,
});

Future<_Built> _build({
  required String x,
  String? good,
  Map<String, List<int>> priorOutputs = const {},
  Map<String, String> extra = const {},
  MeasurementCompilerLedgerWriter ledgerWriter = _discardLedgerSource,
}) async {
  final warnings = <String>[];
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final result = await testBuilders(
    [
      ...surfaceBuildChain(
        compiler: PackageSurfaceCompilerBuilder(
          _policyOptions,
          ledgerWriter: ledgerWriter,
        ),
        priorOutputs: priorOutputs,
      ),
    ],
    <String, Object>{
      '$_package|lib/x.dart': x,
      '$_package|lib/good.dart': good ?? _good(),
      // Every build carries a custom widget. Its catalog is an output too.
      '$_package|lib/chip.dart': _chip,
      for (final MapEntry(:key, :value) in extra.entries)
        '$_package|$key': value,
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level == Level.WARNING) warnings.add(record.message);
    },
  );
  bool exists(String path) =>
      readerWriter.testing.exists(AssetId(_package, path));
  String read(String path) =>
      readerWriter.testing.readString(AssetId(_package, path));
  return (
    warnings: warnings,
    succeeded: result.succeeded,
    errors: result.errors.toList(),
    stamp:
        jsonDecode(read('.restage/build/metadata/restage.build.json'))
            as Map<String, Object?>,
    ledger: exists(kRestageMeasurementCompilerOutputPath)
        ? RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
            utf8.encode(read(kRestageMeasurementCompilerOutputPath)),
          )
        : null,
    outputs: () => {
      for (final path in [..._kOutputs, ..._kMetadata, _kStamp, ..._kParts])
        if (exists(path))
          path: readerWriter.testing.readBytes(AssetId(_package, path)),
    },
  );
}

// The outputs of a build that succeeds, custom catalog included.
Future<Map<String, List<int>>> _settledOutputs() async {
  final settled = await _build(x: _x(_go + _stop));
  expect(settled.succeeded, isTrue, reason: settled.errors.join('\n'));
  final outputs = settled.outputs();
  expect(outputs.keys, containsAll([..._kOutputs, ..._kMetadata]));
  return outputs;
}

// [failed] failed with no duplicate write, its stamp's errors match [error],
// and each of [paths] holds what [prior] held.
void _expectFailedKeeping(
  _Built failed,
  Map<String, List<int>> prior, {
  required Matcher error,
  required List<String> paths,
}) {
  expect(failed.succeeded, isFalse);
  expect(failed.errors.join('\n'), isNot(contains('InvalidOutputException')));
  expect(failed.stamp['result'], 'failed');
  expect((failed.stamp['errors']! as List).join('\n'), error);
  final after = failed.outputs();
  for (final path in paths) {
    expect(after[path], orderedEquals(prior[path]!), reason: path);
  }
}

// Runs only the outputs step, as a build does when one of its outputs is
// deleted after a failed build.
Future<({bool succeeded, List<String> severe, Map<String, List<int>> outputs})>
_rerunOutputs(
  Map<String, List<int>> priorOutputs, {
  required Map<String, String> sources,
}) async {
  final severe = <String>[];
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final result = await testBuilders(
    [
      RestageOutputsBuilder(
        BuilderOptions.empty,
        priorOutputReader: (_, _) async => priorOutputs,
      ),
    ],
    {
      for (final MapEntry(:key, :value) in sources.entries)
        '$_package|$key': value,
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      // Without the `<builder> on <input>:` line build_runner prefixes.
      if (record.level >= Level.SEVERE) {
        severe.add(record.message.substring(record.message.indexOf('\n') + 1));
      }
    },
  );
  return (
    succeeded: result.succeeded,
    severe: severe,
    outputs: {
      for (final path in [..._kOutputs, ..._kMetadata, _kStamp])
        if (readerWriter.testing.exists(AssetId(_package, path)))
          path: readerWriter.testing.readBytes(AssetId(_package, path)),
    },
  );
}

Future<void> _discardLedgerSource({
  required String package,
  required RestageMeasurementCompilerOutputV1 output,
}) async {}

Future<void> _stopLedgerSource({
  required String package,
  required RestageMeasurementCompilerOutputV1 output,
}) async => throw StateError('The ledger source could not be written.');

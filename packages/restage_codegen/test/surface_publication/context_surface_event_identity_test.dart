import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _sourceAsset = 'apps_examples|lib/features/measured.dart';

// Values the same screen compiled to when it fired its events through the
// earlier top-level helper.
const _helperIdentity = {
  'contractFingerprint':
      'sha256:f8c49d4aa32a02bba20faf2ab8f4c0d923c5f7bdfe466e9da44f811b5f2a131f',
  'eventContractHash':
      'sha256:4bb43b2d0b8d4c37167ff6d12314ede74781f30782529c73ffd449468bcc986e',
  'eventContract':
      '{"schemaVersion":1,"events":['
      '{"id":"close","arguments":{"encoding":"none"}},'
      '{"id":"pick","arguments":'
      '{"encoding":"value","shape":{"kind":"string"}}},'
      '{"id":"toggle","arguments":'
      '{"encoding":"value","shape":{"kind":"bool"}}}'
      ']}',
  'payloadContentHash':
      'sha256:7259c1313d87683993bfdb4225ab7591e7f78586fc2f3640b38480aee09663f9',
  'artifacts':
      'capabilitySidecar:'
      'sha256:d2205c951f1546a9048dc2167454619ee7c44827dc43c68b190a696b3872eff8 '
      'screenBlob:'
      'sha256:d45ee199d40bcb7df721e2c1eb09502da382fb8357afb086f038340c63f0423a',
};

void main() {
  test(
    'context.surfaceEvent compiles to the payload and contract of the helper',
    () async {
      expect(await _identity(), _helperIdentity);
    },
  );

  // A screen names the shared events it fires, so they stay in its contract.
  test(
    'events declared in a shared file compile to the same contract',
    () async {
      expect(_shared, contains('static const close = CommonEvents.close;'));
      expect(
        await _identity({_sourceAsset: _shared, _eventsAsset: _events}),
        _helperIdentity,
      );
    },
  );

  // A screen that fires shared events without declaring them still has them
  // in its contract, through a widget the build inlines. The inlined widget
  // is its own definition, so only the payload differs.
  test(
    'shared events fired through an inlined widget need no declaration',
    () async {
      final identity = await _identity({
        _sourceAsset: _undeclared,
        _eventsAsset: _events,
        _actionAsset: _action,
      });
      for (final key in [
        'contractFingerprint',
        'eventContractHash',
        'eventContract',
      ]) {
        expect(identity[key], _helperIdentity[key], reason: key);
      }
    },
  );

  test('shared events fired in the build need no declaration', () async {
    final direct = _undeclared
        .replaceAll("import '../shared/close_action.dart';\n", '')
        .replaceAll(
          'const CloseAction(),',
          'TextButton(\n'
              '            onPressed: '
              'context.surfaceEvent(CommonEvents.close),\n'
              "            child: const Text('Close'),\n"
              '          ),',
        );
    expect(
      await _identity({_sourceAsset: direct, _eventsAsset: _events}),
      _helperIdentity,
    );
  });

  test('a declared alias and a direct reference are one event', () async {
    final both = _shared.replaceFirst(
      'context.surfaceEvent(pick, ',
      'context.surfaceEvent(CommonEvents.pick, ',
    );
    expect(both, contains('CommonEvents.pick, '));
    expect(
      await _identity({_sourceAsset: both, _eventsAsset: _events}),
      _helperIdentity,
    );
  });

  test('one ID with two payload types refuses', () async {
    final conflicting = _undeclared.replaceFirst(
      'const EventIdentity({super.key});',
      'const EventIdentity({super.key});\n\n'
          "  static const pick = SurfaceEvent<int>('pick');",
    );
    final errors = await _errors({
      _sourceAsset: conflicting,
      _eventsAsset: _events,
      _actionAsset: _action,
    });
    expect(errors, hasLength(1));
    expect(
      errors.single,
      contains(
        'Duplicate standalone SurfaceEvent ID "pick" declared by '
        'EventIdentity.pick, CommonEvents.pick. Try giving each event its own '
        'ID, or the same payload type.',
      ),
    );
  });

  test(
    'two events under one name refuse with the declaration to add',
    () async {
      final colliding = _undeclared.replaceFirst(
        'const EventIdentity({super.key});',
        'const EventIdentity({super.key});\n\n'
            "  static const close = SurfaceEvent<void>('shut');",
      );
      final errors = await _errors({
        _sourceAsset: colliding,
        _eventsAsset: _events,
        _actionAsset: _action,
      });
      expect(errors, hasLength(1));
      expect(
        errors.single,
        contains(
          'EventIdentity fires events with different IDs under one name, '
          '`EventIdentity.close` and `CommonEvents.close`. Try declaring '
          '`static const commonEventsClose = CommonEvents.close;` on '
          'EventIdentity.',
        ),
      );
    },
  );
}

// [_source] with its events declared in [_events].
final String _shared = _source
    .replaceAll(
      "import 'package:restage/restage.dart';\n",
      "import 'package:restage/restage.dart';\n\n"
          "import '../shared/common_events.dart';\n",
    )
    .replaceAllMapped(
      RegExp(r"  static const (\w+) = SurfaceEvent<\w+>\('\w+'\);"),
      (match) => '  static const ${match[1]} = CommonEvents.${match[1]};',
    );

// [_source] firing [_events] without declaring them, its close button an
// inlined widget.
final String _undeclared = _source
    .replaceAll(
      "import 'package:restage/restage.dart';\n",
      "import 'package:restage/restage.dart';\n\n"
          "import '../shared/close_action.dart';\n"
          "import '../shared/common_events.dart';\n",
    )
    .replaceAll(
      RegExp(r"  static const \w+ = SurfaceEvent<\w+>\('\w+'\);\n"),
      '',
    )
    .replaceAll(
      'Widget action(BuildContext context) => TextButton(\n'
          '        onPressed: context.surfaceEvent(close),\n'
          "        child: const Text('Close'),\n"
          '      );\n',
      '',
    )
    .replaceAll('action(context),', 'const CloseAction(),')
    .replaceAll('surfaceEvent(pick', 'surfaceEvent(CommonEvents.pick')
    .replaceAll('surfaceEvent(toggle', 'surfaceEvent(CommonEvents.toggle');

const _actionAsset = 'apps_examples|lib/shared/close_action.dart';

const _action = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'common_events.dart';

class CloseAction extends StatelessWidget {
  const CloseAction({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(CommonEvents.close),
        child: const Text('Close'),
      );
}
''';

Future<List<String>> _errors(Map<String, String> sources) async {
  final compilation = await testBuilder(
    const PackageSurfaceCompilerBuilder(
      BuilderOptions({
        kMeasurementMinimumClientOption: 1,
        kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
        kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
        'bundled_runtime': true,
      }),
    ),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    ),
    flattenOutput: true,
  );
  expect(compilation.succeeded, isFalse);
  return compilation.errors.toList();
}

const _eventsAsset = 'apps_examples|lib/shared/common_events.dart';

const _events = '''
import 'package:restage/restage.dart';

abstract final class CommonEvents {
  static const close = SurfaceEvent<void>('close');
  static const pick = SurfaceEvent<String>('pick');
  static const toggle = SurfaceEvent<bool>('toggle');
}
''';

Future<Map<String, String>> _identity([
  Map<String, String> sources = const {_sourceAsset: _source},
]) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final compilation = await testBuilder(
    const PackageSurfaceCompilerBuilder(
      BuilderOptions({
        kMeasurementMinimumClientOption: 1,
        kMeasurementPrivacyPolicyRevisionOption: 'privacy.automatic-v1',
        kMeasurementCollectionBudgetRevisionOption: 'budget.automatic-v1',
        'bundled_runtime': true,
      }),
    ),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(compilation.succeeded, isTrue, reason: compilation.errors.join());
  final bundle =
      jsonDecode(
            readerWriter.testing.readString(
              AssetId(
                'apps_examples',
                kRestageSurfacePublicationCompilerBundlePath,
              ),
            ),
          )
          as Map<String, Object?>;
  final entry =
      ((bundle['manifest']! as Map)['publications']! as List).single as Map;
  final publication = entry['publication']! as Map;
  final artifacts = [
    for (final artifact in entry['artifacts']! as List)
      '${(artifact as Map)['role']}:${artifact['contentHash']}',
  ];
  return {
    'contractFingerprint': publication['contractFingerprint'] as String,
    'eventContractHash': publication['eventContractHash'] as String,
    'eventContract': jsonEncode(publication['eventContract']),
    'payloadContentHash': publication['payloadContentHash'] as String,
    'artifacts': artifacts.join(' '),
  };
}

const _source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/measured.restage.g.dart';

@Screen(id: 'event_identity', surface: Surface.general)
final class EventIdentity extends StatelessWidget {
  const EventIdentity({super.key});

  static const close = SurfaceEvent<void>('close');
  static const pick = SurfaceEvent<String>('pick');
  static const toggle = SurfaceEvent<bool>('toggle');

  Widget action(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(close),
        child: const Text('Close'),
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          action(context),
          FilledButton(
            onPressed: context.surfaceEvent(pick, 'b'),
            child: const Text('Pick'),
          ),
          Switch(value: false, onChanged: context.surfaceEvent(toggle)),
        ],
      );
}
''';

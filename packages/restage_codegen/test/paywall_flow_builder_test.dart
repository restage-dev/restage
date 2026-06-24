@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PaywallFlowBuilder', () {
    test('synthesizes a flow document from a navigation paywall', () async {
      final sources = _navigationPaywallSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          restageCodegenBuilder(BuilderOptions.empty),
          paywallFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue);

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/paywalls/entry.flow.json'),
      );
      final document = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
      final entryBytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'assets/onboarding/screens/paywall_entry.rfw',
        ),
      );
      final pushedBytes = result.readerWriter.testing.readBytes(
        AssetId(
          'apps_examples',
          'assets/onboarding/screens/paywall_choose_plan.rfw',
        ),
      );

      expect(FlowDocumentValidation.validate(document), isEmpty);
      expect(document.flow, 'entry');
      expect(document.version, 1);
      expect(document.schemaVersion, 1);
      expect(document.minClient, kBaselineCatalogVersion);
      expect(document.initial, 'paywall_entry');
      expect(document.actions, isEmpty);
      expect(document.flowState, isEmpty);
      expect(document.outbound.isEmpty, isTrue);

      final entry = document.states['paywall_entry']! as ScreenFlowState;
      expect(entry.screen, 'paywall_entry');
      expect(entry.on['restageNav0']?.target, 'paywall_choose_plan');
      expect(entry.on['skip']?.target, 'done');
      expect(entry.on, isNot(contains('purchase')));

      expect(
        document.states['done'],
        isA<EndFlowState>().having((state) => state.result, 'result', isEmpty),
      );
      expect(
        document.states['paywall_choose_plan'],
        isA<ScreenFlowState>().having(
          (state) => state.screen,
          'screen',
          'paywall_choose_plan',
        ),
      );

      expect(
        document.screenArtifacts['paywall_entry'],
        isA<ScreenArtifact>()
            .having((artifact) => artifact.path, 'path', 'paywall_entry.rfw')
            .having((artifact) => artifact.version, 'version', 1)
            .having((artifact) => artifact.schemaVersion, 'schemaVersion', 1)
            .having(
              (artifact) => artifact.minClient,
              'minClient',
              kBaselineCatalogVersion,
            )
            .having(
              (artifact) => artifact.contentHash,
              'contentHash',
              FlowContentHash.compute(entryBytes),
            ),
      );
      expect(
        document.screenArtifacts['paywall_choose_plan'],
        isA<ScreenArtifact>()
            .having(
              (artifact) => artifact.path,
              'path',
              'paywall_choose_plan.rfw',
            )
            .having(
              (artifact) => artifact.minClient,
              'minClient',
              kBaselineCatalogVersion,
            )
            .having(
              (artifact) => artifact.contentHash,
              'contentHash',
              FlowContentHash.compute(pushedBytes),
            ),
      );
    });

    test(
        'stamps each screen its own derived capability floor and the flow '
        'document the max of its screens', () async {
      // The pushed `choose_plan` screen embeds a single-select picker — a
      // catalog widget introduced after the baseline content version (its
      // `sinceVersion` is 2). The entry screen uses only baseline widgets.
      // Each screen artifact must carry the floor derived from the built-ins
      // *that screen* references, and the flow document must carry the max
      // across its screens — never a blanket baseline stamp, which would
      // under-declare the client a sub-floor renderer cannot satisfy.
      final sources = _higherFloorNavigationPaywallSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          restageCodegenBuilder(BuilderOptions.empty),
          paywallFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue);

      final flowBytes = result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'assets/paywalls/entry.flow.json'),
      );
      final document = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));

      // The entry screen references only baseline built-ins → floors at the
      // baseline; the pushed screen references the version-2 picker → floors
      // at 2; the flow document is the max across its screens.
      expect(
        document.screenArtifacts['paywall_entry']!.minClient,
        kBaselineCatalogVersion,
      );
      expect(document.screenArtifacts['paywall_choose_plan']!.minClient, 2);
      expect(document.minClient, 2);
    });

    test('non-navigation paywalls do not emit a flow document', () async {
      final sources = _plainPaywallSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          restageCodegenBuilder(BuilderOptions.empty),
          paywallFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );

      expect(result.succeeded, isTrue);
      expect(
        await result.readerWriter.canRead(
          AssetId('apps_examples', 'assets/paywalls/plain.flow.json'),
        ),
        isFalse,
      );
    });

    test('missing referenced screen artifact fails before JSON emit', () async {
      final logs = <LogRecord>[];
      final sources = {
        'apps_examples|lib/paywalls/entry.dart': 'class Entry {}',
      };
      final readerWriter = await _readerWriterWith(sources);
      readerWriter.testing
        ..writeString(
          AssetId('apps_examples', 'assets/paywalls/entry.navplan.json'),
          jsonEncode({
            'entryId': 'entry',
            'transitions': [
              {'event': 'restageNav0', 'pushedId': 'choose_plan'},
            ],
            'terminatingEvent': 'skip',
          }),
        )
        ..writeBytes(
          AssetId(
            'apps_examples',
            'assets/onboarding/screens/paywall_entry.rfw',
          ),
          [1, 2, 3],
        );

      final result = await testBuilders(
        [paywallFlowBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: logs.add,
      );

      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        contains('missingScreenDescriptor'),
      );
      expect(
        await result.readerWriter.canRead(
          AssetId('apps_examples', 'assets/paywalls/entry.flow.json'),
        ),
        isFalse,
      );
    });

    test('nested navigation (depth > 1) fatal-defers the entry flow', () async {
      final logs = <LogRecord>[];
      final sources = _nestedNavigationPaywallSources();
      final readerWriter = await _readerWriterWith(sources);

      final result = await testBuilders(
        [
          restageCodegenBuilder(BuilderOptions.empty),
          paywallFlowBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: logs.add,
      );

      // The entry flow must fatal-defer because its pushed screen
      // `choose_plan` itself navigates (depth > 1), which v1 does not lower —
      // a silent drop would be the one unacceptable error class.
      expect(result.succeeded, isFalse);
      expect(
        logs.map((log) => log.message).join('\n'),
        contains('navigationFormUnsupported'),
      );
      expect(
        await result.readerWriter.canRead(
          AssetId('apps_examples', 'assets/paywalls/entry.flow.json'),
        ),
        isFalse,
      );
    });
  });
}

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

Map<String, String> _navigationPaywallSources() => {
      'apps_examples|lib/paywalls/entry.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'choose_plan.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlanPaywall()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''',
      'apps_examples|lib/paywalls/choose_plan.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlanPaywall extends StatelessWidget {
  const ChoosePlanPaywall({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    };

Map<String, String> _nestedNavigationPaywallSources() => {
      'apps_examples|lib/paywalls/entry.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'choose_plan.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlanPaywall()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''',
      'apps_examples|lib/paywalls/choose_plan.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'confirm_plan.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlanPaywall extends StatelessWidget {
  const ChoosePlanPaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ConfirmPlanPaywall()),
        ),
        child: const Text('Confirm'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''',
      'apps_examples|lib/paywalls/confirm_plan.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'confirm_plan')
class ConfirmPlanPaywall extends StatelessWidget {
  const ConfirmPlanPaywall({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    };

Map<String, String> _higherFloorNavigationPaywallSources() => {
      'apps_examples|lib/paywalls/entry.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'choose_plan.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlanPaywall()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''',
      // The pushed screen embeds a vanilla RadioGroup, which lowers to the
      // single-select catalog widget whose content version is 2.
      'apps_examples|lib/paywalls/choose_plan.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlanPaywall extends StatelessWidget {
  const ChoosePlanPaywall({super.key});

  @override
  Widget build(BuildContext context) => RadioGroup<String>(
    groupValue: 'annual',
    child: Column(
      children: const [
        RadioListTile<String>(value: 'monthly', title: Text('Monthly')),
        RadioListTile<String>(value: 'annual', title: Text('Annual')),
      ],
    ),
  );
}
''',
    };

Map<String, String> _plainPaywallSources() => {
      'apps_examples|lib/paywalls/plain.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'plain')
class PlainPaywall extends StatelessWidget {
  const PlainPaywall({super.key});

  @override
  Widget build(BuildContext context) => const Text('Plain');
}
''',
    };

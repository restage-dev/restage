import 'dart:convert';

import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/placement_self_fit.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../support/surface_build_chain.dart';

const _package = 'apps_examples';

// App tokens the steps style text with, as a design system would.
const _tokens = '''
import 'package:flutter/widgets.dart';

class AppColors {
  const AppColors({required this.ink, required this.ink2});
  final Color ink;
  final Color ink2;
  static AppColors of(BuildContext context) =>
      const AppColors(ink: Color(0xFF111111), ink2: Color(0xFF555555));
}

abstract final class AppType {
  static const title = TextStyle(fontSize: 28);
  static const lede = TextStyle(fontSize: 16);
}

enum Preset {
  early(7),
  usual(8),
  late(9);

  const Preset(this.hour);
  final int hour;
}

class Settings {
  Settings(this.hour);
  int hour;
  void pick(Preset preset) => hour = preset.hour;
  static Settings of(BuildContext context) => _settings;
}

final _settings = Settings(8);

abstract final class Copy {
  static String time(int hour) {
    final buffer = StringBuffer()
      ..write(hour)
      ..write(':00');
    return buffer.toString();
  }
}
''';

const _welcome = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'tokens.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen()
class WelcomeStep extends StatelessWidget {
  static const start = SurfaceEvent<void>('start');

  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text('Happy plants', style: AppType.title.copyWith(color: c.ink)),
        Text('One small drink at a time',
            style: AppType.lede.copyWith(color: c.ink2)),
        FilledButton(
          onPressed: () => context.surfaceEvent(start),
          child: const Text('Get started'),
        ),
      ],
    );
  }
}
''';

const _time = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'tokens.dart';

part 'restage.generated/time.restage.g.dart';

@Screen()
class TimeStep extends StatelessWidget {
  static const next = SurfaceEvent<void>('next');

  const TimeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final settings = Settings.of(context);
    final time = Copy.time(settings.hour);
    return Column(
      children: [
        Text('One reminder at \$time',
            style: AppType.lede.copyWith(color: c.ink2)),
        for (final (index, preset) in Preset.values.indexed)
          TextButton(
            onPressed: () => settings.pick(preset),
            child: Text('\${index + 1}. \${Copy.time(preset.hour)}'),
          ),
        FilledButton(
          onPressed: () => context.surfaceEvent(TimeStep.next),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
''';

const _flow = '''
import 'package:restage/restage.dart';

import 'time.dart';
import 'welcome.dart';

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(
  id: 'first_run',
  surface: Surface.onboarding,
  delivery: FlowDeliveryMode.general,
)
const firstRun = FlowDefinition(
  start: WelcomeStep,
  transitions: [
    Transition(WelcomeStep.start, to: TimeStep),
    Transition.complete(TimeStep.next),
  ],
);
''';

// The same flow, written as a class.
const _classFlow = '''
import 'package:restage/restage.dart';

import 'time.dart';
import 'welcome.dart';

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(
  id: 'first_run',
  surface: Surface.onboarding,
  delivery: FlowDeliveryMode.general,
)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: welcomeStepRef,
      states: [
        screen(welcomeStepRef).on(WelcomeStep.start).goTo(timeStepRef),
        screen(timeStepRef).on(TimeStep.next).goTo(done),
        end(done, result: const {}),
      ],
    );
  }
}
''';

// The steps as an earlier build had them: nothing computed in the app.
const _plainWelcome = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen()
class WelcomeStep extends StatelessWidget {
  static const start = SurfaceEvent<void>('start');

  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () => context.surfaceEvent(start),
        child: const Text('Get started'),
      );
}
''';

const _plainTime = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/time.restage.g.dart';

@Screen()
class TimeStep extends StatelessWidget {
  static const next = SurfaceEvent<void>('next');

  const TimeStep({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () => context.surfaceEvent(TimeStep.next),
        child: const Text('Continue'),
      );
}
''';

// The welcome step's styled lede moved to the time step.
const _movedWelcome = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen()
class WelcomeStep extends StatelessWidget {
  static const start = SurfaceEvent<void>('start');

  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () => context.surfaceEvent(start),
        child: const Text('Get started'),
      );
}
''';

const _movedTime = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'tokens.dart';

part 'restage.generated/time.restage.g.dart';

@Screen()
class TimeStep extends StatelessWidget {
  static const next = SurfaceEvent<void>('next');

  const TimeStep({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        Text('One small drink at a time',
            style: AppType.lede.copyWith(color: c.ink2)),
        FilledButton(
          onPressed: () => context.surfaceEvent(TimeStep.next),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
''';

const _pushedNative = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart' as rs;
part 'restage.generated/entry.restage.g.dart';

@rs.Paywall()
class PlanPicker extends StatefulWidget {
  const PlanPicker({super.key});
  @override
  State<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends State<PlanPicker> {
  bool annualSelected = true;
  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(
          onTap: () => setState(() => annualSelected = true),
          child: Text(annualSelected ? 'Annual (selected)' : 'Annual'),
        ),
        GestureDetector(onTap: context.surfaceEvent(rs.PaywallEvents.skip), child: const Text('Skip')),
        GestureDetector(onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const Details())), child: const Text('More')),
      ]);
}

@rs.Paywall(id: 'details')
class Details extends StatelessWidget {
  const Details({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
    TextButton(onPressed: () { debugPrint('d'); }, child: const Text('DetailsNative')),
    GestureDetector(onTap: context.surfaceEvent(rs.PaywallEvents.skip), child: const Text('Skip2')),
  ]);
}
''';

// A flow whose subflow's step places an app widget.
const _subflowIsland = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/journey.restage.g.dart';

class Probe extends StatelessWidget {
  const Probe({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: null, child: Text(label));
}

@Screen(id: 'entry')
final class Entry extends StatelessWidget {
  const Entry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: () => context.surfaceEvent(next),
        child: const Text('Next'),
      );
}

@Screen(id: 'child_screen')
final class ChildScreen extends StatelessWidget {
  const ChildScreen({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => Column(children: [
        const Probe(label: 'child'),
        FilledButton(
          onPressed: () => context.surfaceEvent(finish),
          child: const Text('Done'),
        ),
      ]);
}

@FlowGraph(id: 'child_flow', surface: Surface.onboarding)
const childFlow = FlowDefinition(
  start: ChildScreen,
  transitions: [Transition.complete(ChildScreen.finish)],
);

final parentDone = Completion('parent_done');
final childStep = Subflow('child_step', flow: childFlow, onComplete: parentDone);

@FlowGraph(id: 'parent_flow', surface: Surface.onboarding)
final parentFlow = FlowDefinition(
  start: Entry,
  transitions: [Transition(Entry.next, to: childStep)],
);
''';

// A flow whose steps read only their own constructor inputs, both named
// `title`, as [first] and [second].
String _namedSteps(String first, String second) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/named.restage.g.dart';

@Screen(id: 'first_step')
final class FirstStep extends StatelessWidget {
  const FirstStep({required this.title, super.key});
  final $first title;
  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(next),
        child: Text('\$title'),
      );
}

@Screen(id: 'second_step')
final class SecondStep extends StatelessWidget {
  const SecondStep({required this.title, super.key});
  final $second title;
  static const done = SurfaceEvent<void>('done');

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: context.surfaceEvent(done),
        child: Text('\$title'),
      );
}

@FlowGraph(id: 'named', surface: Surface.onboarding)
const named = FlowDefinition(
  start: FirstStep,
  transitions: [
    Transition(FirstStep.next, to: SecondStep),
    Transition.complete(SecondStep.done),
  ],
);
''';

void main() {
  // A step that reads only its own inputs still renders under its mount, so
  // the placement passes those inputs.
  test('a step reading only its inputs gets a step mount', () async {
    const part = 'lib/restage.generated/named.restage.g.dart';
    final out = await _build(
      {
        '$_package|lib/named.dart': _namedSteps('String', 'String'),
      },
      parts: const [part],
    );
    expect(out.errors, isEmpty);
    expect(out.unfit, isEmpty);
    expect(
      out.parts[part],
      allOf(
        contains(r'Widget restageStepMount$first_step('),
        contains(r'Widget restageStepMount$second_step('),
      ),
    );
  });

  test(
    'two steps passing one name with different types are not pushed',
    () async {
      final out = await _build({
        '$_package|lib/named.dart': _namedSteps('String', 'int'),
      }, parts: const []);
      expect(out.errors, isEmpty);
      expect(out.unfit.keys, ['onboarding/named']);
      expect(
        out.unfit['onboarding/named'],
        "The onboarding 'named' can't be published: `FirstStep` and "
        '`SecondStep` both pass `title`, as `String` and as `int`. Its '
        'placement passes one type for each name. Try renaming one of them.',
      );
    },
  );

  test('a subflow step that places an app widget fits its flow', () async {
    const part = 'lib/restage.generated/journey.restage.g.dart';
    final out = await _build(
      {
        '$_package|lib/journey.dart': _subflowIsland,
      },
      parts: const [part],
    );
    expect(out.errors, isEmpty);
    final requirement = out.manifest.publications
        .singleWhere((entry) => entry.publication.slug == 'parent_flow')
        .publication
        .fitRequirement!;
    expect(requirement.requiredIslands, isNotEmpty);
    final definition = generatedPlacementDefinitions(
      out.parts[part]!,
    ).singleWhere((definition) => definition.locator['slug'] == 'parent_flow');
    expect(
      SurfaceHostContractV1.fromJson(definition.host).islands.keys,
      containsAll(requirement.requiredIslands.keys),
    );
  });

  // A paywall flow shows a pushed paywall without that paywall's own mount,
  // so a value the pushed build computes reaches no placement: the build
  // warns, and the paywall isn't pushed.
  test('a value a pushed paywall computes builds, but is not pushed', () async {
    final out = await _build({
      '$_package|lib/entry.dart': _pushedNative,
    }, parts: const []);
    expect(out.errors, isEmpty);
    expect(
      out.warnings,
      contains(
        startsWith(
          '[surfaceDoesNotFitPlacement] paywall/entry: The paywall '
          "'entry' needs what its own placement doesn't pass",
        ),
      ),
    );
    expect(out.unfit.keys, ['paywall/entry']);
    expect(
      out.unfit['paywall/entry'],
      contains("it reads `() {debugPrint('d');}` from the app"),
    );
  });

  // Host data is declared flat across a flow's steps, so a version that
  // moves a computed value to a step whose installed mount doesn't compute it
  // still fits. A per-step contract would refuse it.
  test(
    'known flat-contract gap: a value moved between steps still fits',
    () async {
      final installed = await _build({
        '$_package|lib/onboarding/tokens.dart': _tokens,
        '$_package|lib/onboarding/welcome.dart': _welcome,
        '$_package|lib/onboarding/time.dart': _plainTime,
        '$_package|lib/onboarding/first_run.dart': _flow,
      });
      final moved = await _build({
        '$_package|lib/onboarding/tokens.dart': _tokens,
        '$_package|lib/onboarding/welcome.dart': _movedWelcome,
        '$_package|lib/onboarding/time.dart': _movedTime,
        '$_package|lib/onboarding/first_run.dart': _flow,
      });
      expect(installed.errors, isEmpty);
      expect(moved.errors, isEmpty);
      final requirement = moved.manifest.publications
          .singleWhere((entry) => entry.publication.slug == 'first_run')
          .publication
          .fitRequirement!;
      expect(requirement.requiredContext.inputs, hasLength(1));
      expect(
        placementSelfFitIssues(moved.manifest, installed.parts.values),
        isEmpty,
      );
    },
  );
  test(
    "a publication that needs what its placement lacks doesn't fit it",
    () async {
      final plain = await _build({
        '$_package|lib/onboarding/welcome.dart': _plainWelcome,
        '$_package|lib/onboarding/time.dart': _plainTime,
        '$_package|lib/onboarding/first_run.dart': _flow,
      });
      final computed = await _build({
        '$_package|lib/onboarding/tokens.dart': _tokens,
        '$_package|lib/onboarding/welcome.dart': _welcome,
        '$_package|lib/onboarding/time.dart': _time,
        '$_package|lib/onboarding/first_run.dart': _flow,
      });
      expect(plain.errors, isEmpty);
      expect(computed.errors, isEmpty);
      final issues = placementSelfFitIssues(
        computed.manifest,
        plain.parts.values,
      );
      expect(issues, hasLength(1));
      expect(
        issues.single.message,
        allOf(
          startsWith(
            "The onboarding 'first_run' needs what its own placement doesn't "
            'pass: it reads `',
          ),
          contains('it reads `time` from the app'),
          contains(
            "and 1 more. A device would show the placement's fallback instead "
            'of a published version. ',
          ),
          endsWith(
            'Try computing that value inside a widget marked '
            '`@RenderInApp()`.',
          ),
        ),
      );
      expect(
        placementSelfFitIssues(computed.manifest, computed.parts.values),
        isEmpty,
      );
    },
  );

  for (final (form, flow) in [('definition', _flow), ('class', _classFlow)]) {
    test(
      'a general flow $form whose steps compute values fits its own placement',
      () async {
        final out = await _build({
          '$_package|lib/onboarding/tokens.dart': _tokens,
          '$_package|lib/onboarding/welcome.dart': _welcome,
          '$_package|lib/onboarding/time.dart': _time,
          '$_package|lib/onboarding/first_run.dart': flow,
        });
        expect(out.errors, isEmpty);
        final publication = out.manifest.publications
            .singleWhere((entry) => entry.publication.slug == 'first_run')
            .publication;
        final requirement = publication.fitRequirement!;
        // The steps read what the app computes: styles, `$time`, the loop.
        expect(requirement.requiredContext.inputs, isNotEmpty);
        final flowPart = out
            .parts['lib/onboarding/restage.generated/first_run.restage.g.dart']!;
        final definition = generatedPlacementDefinitions(flowPart).single;
        final verdict = SurfaceFitEvaluator.evaluate(
          host: SurfaceHostContractV1.fromJson(definition.host),
          requirement: requirement,
          installed: InstalledCapability(
            builtInCatalogVersion: requirement.capabilities.builtInFloor,
            installedLibraries: const [],
          ),
        );
        expect(
          [
            for (final failure in verdict.failures)
              if (failure.code == SurfaceFitFailureCodeV1.missingHostField ||
                  failure.code == SurfaceFitFailureCodeV1.incompatibleHostField)
                '${failure.code.name} ${failure.path}',
          ],
          isEmpty,
        );
        // Exactly what the step mounts pass: no more, no less.
        expect(
          SurfaceHostContractV1.fromJson(
            definition.host,
          ).providedContext.inputs.keys.toSet(),
          containsAll(requirement.requiredContext.inputs.keys),
        );
      },
    );
  }
}

Future<
  ({
    List<String> errors,
    List<String> warnings,
    SurfacePublicationManifest manifest,
    Map<String, String> unfit,
    Map<String, String> parts,
  })
>
_build(
  Map<String, String> sources, {
  List<String> parts = const [
    'lib/onboarding/restage.generated/first_run.restage.g.dart',
    'lib/onboarding/restage.generated/welcome.restage.g.dart',
    'lib/onboarding/restage.generated/time.restage.g.dart',
  ],
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final errors = <String>[];
  final warnings = <String>[];
  final result = await testBuilders(
    [
      ...surfaceBuildChain(),
    ],
    sources,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) {
      if (record.level >= Level.SEVERE) errors.add(record.message);
      if (record.level == Level.WARNING) {
        warnings.add(
          record.message.substring(record.message.indexOf('\n') + 1),
        );
      }
    },
  );
  if (!result.succeeded) {
    return (
      errors: [...errors, for (final e in result.errors) '$e'],
      warnings: warnings,
      manifest: SurfacePublicationManifest(publications: const []),
      unfit: const <String, String>{},
      parts: const <String, String>{},
    );
  }
  final bundle = RestageSurfacePublicationBundle.fromJson(
    jsonDecode(
          readerWriter.testing.readString(
            AssetId(_package, kRestageSurfacePublicationCompilerBundlePath),
          ),
        )
        as Map<String, Object?>,
  );
  String part(String path) =>
      readerWriter.testing.readString(AssetId(_package, path));
  return (
    errors: errors,
    warnings: warnings,
    manifest: bundle.manifest!,
    unfit: bundle.unfitPublications,
    parts: {for (final path in parts) path: part(path)},
  );
}

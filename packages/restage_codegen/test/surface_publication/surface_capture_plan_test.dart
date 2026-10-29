import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/surface_publication/surface_capture_plan.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  Future<Map<String, Object?>> plans(Map<String, String> sources) async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    return jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', kRestageSurfaceCapturePlanCompilerPath),
      ),
    ) as Map<String, Object?>;
  }

  test('plans a widget from its resolved constructor', () async {
    final plan = await plans({
      'apps_examples|lib/screens/checklist.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/checklist.restage.g.dart';

typedef Steps = List<ChecklistStep>;

final class ChecklistStep {
  const ChecklistStep({
    required String label,
    required this.note,
    required this.hint,
  }) : label = label;

  final String label;
  final String note, hint;
}

@Screen(surface: Surface.general)
final class Checklist extends StatelessWidget {
  const Checklist({
    Key? key,
    required this.steps,
    required this.title,
    required this.since,
    required this.wait,
    required this.tint,
  }) : super(key: key);

  final Steps steps;
  final String /* shown */ title;
  final DateTime since;
  final Duration wait;
  final Color tint;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(title),
          for (final step in steps) Text(step.label),
        ],
      );
}
''',
    });

    Map<String, Object?> parameter(
      String name,
      Map<String, Object?> type, {
      bool required = true,
      String? sampleKey,
    }) =>
        {
          'name': name,
          'named': true,
          'required': required,
          'hasDefault': false,
          'sampleKey': sampleKey ?? name,
          'type': type,
        };
    const string = {'kind': 'string'};
    expect(plan, {
      'general.checklist': {
        'kind': 'object',
        'importUri': 'package:apps_examples/screens/checklist.dart',
        'name': 'Checklist',
        'parameters': [
          // A plain `Key? key` is an optional nullable input.
          parameter(
            'key',
            {'kind': 'unbuildable', 'display': 'Key?', 'nullable': true},
            required: false,
          ),
          // The typedef is resolved to the list it names.
          parameter('steps', {
            'kind': 'list',
            'item': {
              'kind': 'object',
              'importUri': 'package:apps_examples/screens/checklist.dart',
              'name': 'ChecklistStep',
              'parameters': [
                // An initializer list binds the parameter to its field.
                parameter('label', string, sampleKey: 'label'),
                // Fields declared together each keep their own type.
                parameter('note', string),
                parameter('hint', string),
              ],
            },
          }),
          // A comment inside the type does not change it.
          parameter('title', string),
          parameter('since', {'kind': 'value', 'name': 'DateTime'}),
          parameter('wait', {'kind': 'value', 'name': 'Duration'}),
          parameter('tint', {'kind': 'value', 'name': 'Color'}),
        ],
      },
    });
  });

  test('keys a nested class by field and the widget by parameter', () async {
    final plan = await plans({
      'apps_examples|lib/screens/offer.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

final class Price {
  const Price({required String amount}) : label = amount;

  final String label;
}

@Screen(surface: Surface.general)
final class Offer extends StatelessWidget {
  const Offer({super.key, required this.price});

  final Price price;

  @override
  Widget build(BuildContext context) => Text(price.label);
}
''',
    });

    final offer = plan['general.offer']! as Map<String, Object?>;
    final price = ((offer['parameters']! as List)[1] as Map)['type'] as Map;
    expect(
      ((price['parameters']! as List).single as Map)['sampleKey'],
      'label',
    );
    expect(((offer['parameters']! as List)[1] as Map)['sampleKey'], 'price');
  });

  test('an unbound parameter has no sample key; a private class is named',
      () async {
    final plan = await plans({
      'apps_examples|lib/screens/offer.dart': r'''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

final class Price {
  const Price({required String amount}) : label = '$amount USD';

  final String label;
}

final class Fallback {
  const Fallback({String? amount}) : label = amount ?? '';

  final String label;
}

final class Redirect {
  const Redirect(String text) : this._(text);
  const Redirect._(this.text);

  final String text;
}

final class _Hidden {
  const _Hidden({required this.note});

  final String note;
}

@Screen(surface: Surface.general)
final class Offer extends StatelessWidget {
  const Offer({
    super.key,
    required this.price,
    required this.fallback,
    required this.redirect,
    required this.hidden,
  });

  final Price price;
  final Fallback fallback;
  final Redirect redirect;
  final _Hidden hidden;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(price.label),
          Text(fallback.label),
          Text(redirect.text),
          Text(hidden.note),
        ],
      );
}
''',
    });

    final offer = plan['general.offer']! as Map<String, Object?>;
    Map<Object?, Object?> type(String name) => (offer['parameters']! as List)
            .cast<Map<Object?, Object?>>()
            .singleWhere((parameter) => parameter['name'] == name)['type']!
        as Map<Object?, Object?>;
    Object? sampleKey(String name) =>
        ((type(name)['parameters']! as List).single as Map)['sampleKey'];
    // A transformed value is held by no field of the parameter's name.
    expect(sampleKey('price'), isNull);
    expect(sampleKey('fallback'), isNull);
    // A field of the same name holds it through the redirect.
    expect(sampleKey('redirect'), 'text');
    expect(type('hidden'), {'kind': 'private', 'name': '_Hidden'});
  });

  test('a paywall and a screen sharing an id each plan their own', () async {
    final plan = await plans({
      'apps_examples|lib/surfaces/offer.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'offer')
final class OfferPaywall extends StatelessWidget {
  const OfferPaywall({super.key});

  @override
  Widget build(BuildContext context) => const Text('Paywall');
}

@Screen(id: 'offer', surface: Surface.message)
final class OfferMessage extends StatelessWidget {
  const OfferMessage({super.key});

  @override
  Widget build(BuildContext context) => const Text('Message');
}
''',
    });

    expect((plan['paywall.offer']! as Map)['name'], 'OfferPaywall');
    expect((plan['message.offer']! as Map)['name'], 'OfferMessage');
  });

  test('plans a flow by its generated ref', () async {
    final plan = await plans({
      'apps_examples|lib/features/announcement.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''',
      'apps_examples|lib/journeys/launch.dart': '''
import 'package:restage/restage.dart';

import '../features/announcement.dart';

part 'restage.generated/launch.restage.g.dart';

@FlowGraph(surface: Surface.general)
const launch = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
''',
    });

    expect(plan['general.launch'], {
      'kind': 'flow',
      'importUri': 'package:apps_examples/journeys/launch.dart',
      'ref': 'launchRef',
    });
    expect(
      (plan['general.announcement']! as Map)['name'],
      'FeatureAnnouncement',
    );
  });
}

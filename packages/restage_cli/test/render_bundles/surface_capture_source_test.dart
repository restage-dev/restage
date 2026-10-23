import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/surface_capture_source.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

void main() {
  late Directory app;

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_capture_source_');
  });

  tearDown(() => app.deleteSync(recursive: true));

  void write(String path, String text) =>
      File(p.joinAll([app.path, ...path.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  Future<String> source() async {
    final entry = await seedGeneratedPaywall(
      app,
      sources: const ['lib/paywalls/pro_upgrade.dart'],
    );
    return surfaceCaptureTestSource(
      projectRoot: app,
      appName: 'demo',
      entry: entry,
      name: 'paywall.pro_upgrade',
      sample: const <String, Object?>{},
    );
  }

  test('builds the authored paywall named by its file', () async {
    write('lib/paywalls/pro_upgrade.dart', '''
import 'package:flutter/material.dart';

/// The upgrade offer.
@Paywall()
class ProUpgradePaywall extends StatefulWidget {
  const ProUpgradePaywall({super.key});
}
''');

    final text = await source();

    expect(
      text,
      contains("import 'package:demo/paywalls/pro_upgrade.dart' as "),
    );
    expect(
      text,
      matches(RegExp(r'return restage_capture_type0\.ProUpgradePaywall\(\);')),
    );
  });

  test('says why a surface it cannot find has no image', () async {
    write('lib/paywalls/pro_upgrade.dart', '''
@Paywall(id: 'another')
class Another extends StatelessWidget {}
''');

    await expectLater(
      source,
      throwsA(
        isA<SurfaceCaptureSourceException>().having(
          (error) => error.reason,
          'reason',
          'its widget was not found',
        ),
      ),
    );
  });

  /// [entry] with the generated widget named [mountName].
  SurfacePublicationManifestEntry mounted(
    SurfacePublicationManifestEntry entry,
    String mountName,
  ) {
    final json = jsonDecode(jsonEncode(entry.toJson())) as Map<String, Object?>;
    (json['publication']! as Map<String, Object?>)['mountName'] = mountName;
    return SurfacePublicationManifestEntry.fromJson(json, path: 'entry');
  }

  Future<String> screenSource(
    String library, {
    Map<String, Object?> sample = const <String, Object?>{},
  }) async {
    write('lib/screens/checklist_screen.dart', library);
    final entry = await seedGeneratedPaywall(
      app,
      slug: 'checklist',
      surface: Surface.onboarding,
      sources: const ['lib/screens/checklist_screen.dart'],
    );
    return surfaceCaptureTestSource(
      projectRoot: app,
      appName: 'demo',
      entry: mounted(entry, 'ChecklistSurface'),
      name: 'onboarding.checklist',
      sample: sample,
    );
  }

  test('fills a screen\'s host data with sample values', () async {
    final text = await screenSource(
      '''
import 'package:flutter/material.dart';

final class ChecklistItem {
  const ChecklistItem({required this.title, required this.done});

  final String title;
  final bool done;
}

@Screen(id: 'checklist', surface: Surface.onboarding)
class Checklist extends StatelessWidget {
  const Checklist({required this.owner, required this.items, super.key});

  final String owner;
  final List<ChecklistItem> items;
}
''',
      sample: const <String, Object?>{
        'owner': 'Ada',
        'items': [
          {'title': 'First', 'done': true},
        ],
      },
    );

    expect(
      text,
      contains("import 'package:demo/screens/checklist_screen.dart' as"),
    );
    expect(
      text,
      matches(
        RegExp(
          r"return restage_capture_type0\.Checklist\(owner: 'Ada', items: "
          r"\[restage_capture_type0\.ChecklistItem\(title: 'First', "
          r'done: true\)\]\);',
        ),
      ),
    );
  });

  test('says why a constructor it cannot call has no image', () async {
    await expectLater(
      () => screenSource('''
@Screen(id: 'checklist', surface: Surface.onboarding)
class Checklist extends StatelessWidget {
  Checklist({required String owner, super.key}) : _owner = owner;

  final String _owner;
}
'''),
      throwsA(
        isA<SurfaceCaptureSourceException>().having(
          (error) => error.reason,
          'reason',
          'its widget Checklist has no constructor this can call',
        ),
      ),
    );
  });

  test('refuses a flow whose ref is private to its library', () async {
    write('lib/flows/tour.dart', '''
part 'restage.generated/tour.restage.g.dart';
''');
    write('lib/flows/restage.generated/tour.restage.g.dart', '''
part of '../tour.dart';

final class TourFlowSurface extends RestageFlowGraph<TourResult> {
  const TourFlowSurface({super.key}) : super(flow: _tourFlowRef);
}
''');
    final entry = await seedGeneratedPaywall(
      app,
      slug: 'tour',
      surface: Surface.onboarding,
      sources: const ['lib/flows/tour.dart'],
    );

    expect(
      () => surfaceCaptureTestSource(
        projectRoot: app,
        appName: 'demo',
        entry: mounted(entry, 'TourFlowSurface'),
        name: 'onboarding.tour',
        sample: const <String, Object?>{},
      ),
      throwsA(
        isA<SurfaceCaptureSourceException>().having(
          (error) => error.reason,
          'reason',
          'its flow is private to its library',
        ),
      ),
    );
  });

  test('draws a flow from its first screen', () async {
    write('lib/flows/tour.dart', '''
import 'package:restage/restage.dart';

part 'restage.generated/tour.restage.g.dart';
''');
    write('lib/flows/restage.generated/tour.restage.g.dart', '''
part of '../tour.dart';

final class TourFlowSurface extends RestageFlowGraph<TourResult> {
  const TourFlowSurface({super.key}) : super(flow: tourFlowRef);
}
''');
    final entry = await seedGeneratedPaywall(
      app,
      slug: 'tour',
      surface: Surface.onboarding,
      sources: const ['lib/flows/tour.dart'],
    );

    final text = surfaceCaptureTestSource(
      projectRoot: app,
      appName: 'demo',
      entry: mounted(entry, 'TourFlowSurface'),
      name: 'onboarding.tour',
      sample: const <String, Object?>{},
    );

    expect(text, contains('return restage_capture.flowEntry(tourFlowRef);'));
    expect(text, contains("import 'package:demo/flows/tour.dart';"));
  });

  test('a paywall is built from its paywall class, not a screen', () async {
    write('lib/paywalls/pro_upgrade.dart', '''
@Screen(id: 'pro_upgrade_intro', surface: Surface.message)
class ProUpgradeIntro extends StatelessWidget {
  const ProUpgradeIntro({super.key});
}

@Paywall()
class ProUpgrade extends StatelessWidget {
  const ProUpgrade({super.key});
}
''');

    expect(
      await source(),
      contains('return restage_capture_type0.ProUpgrade();'),
    );
  });

  test('a screen and a paywall sharing an id each build their own', () async {
    write('lib/surfaces/offer.dart', '''
@Paywall(id: 'offer')
class OfferPaywall extends StatelessWidget {
  const OfferPaywall({super.key});
}

@Screen(id: 'offer', surface: Surface.message)
class OfferMessage extends StatelessWidget {
  const OfferMessage({super.key});
}
''');
    Future<String> build(Surface surface) async {
      final entry = await seedGeneratedPaywall(
        app,
        slug: 'offer',
        surface: surface,
        sources: const ['lib/surfaces/offer.dart'],
      );
      return surfaceCaptureTestSource(
        projectRoot: app,
        appName: 'demo',
        entry: entry,
        name: '${surface.wireName}.offer',
        sample: const <String, Object?>{},
      );
    }

    expect(
      await build(Surface.paywall),
      contains('return restage_capture_type0.OfferPaywall();'),
    );
    expect(
      await build(Surface.message),
      contains('return restage_capture_type0.OfferMessage();'),
    );
  });

  test('a default holding type arguments stays one parameter', () async {
    write('lib/paywalls/pro_upgrade.dart', '''
@Paywall()
class ProUpgrade extends StatelessWidget {
  const ProUpgrade({
    required this.title,
    this.tags = const <String, String>{},
    super.key,
  });

  final String title;
  final Map<String, String> tags;
}
''');
    final entry = await seedGeneratedPaywall(
      app,
      sources: const ['lib/paywalls/pro_upgrade.dart'],
    );

    final text = surfaceCaptureTestSource(
      projectRoot: app,
      appName: 'demo',
      entry: entry,
      name: 'paywall.pro_upgrade',
      sample: const <String, Object?>{'title': 'Go Pro'},
    );

    expect(
      text,
      contains("return restage_capture_type0.ProUpgrade(title: 'Go Pro');"),
    );
  });

  group('the render context of values the app computes', () {
    const library = '''
import 'package:flutter/material.dart';

@Screen(id: 'checklist')
final class ChecklistScreen extends StatelessWidget {
  const ChecklistScreen({super.key, required this.owner});

  final String owner;
}
''';
    final withAppValue = SurfaceScreenHostDataSchema({
      'owner': const SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.string,
      ),
      '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.integer,
      ),
    });

    Future<String?> contextSource(SurfaceScreenHostDataSchema schema) async {
      write('lib/screens/checklist_screen.dart', library);
      final entry = await seedGeneratedPaywall(
        app,
        slug: 'checklist',
        surface: Surface.onboarding,
        sources: const ['lib/screens/checklist_screen.dart'],
        hostDataContract: schema,
      );
      return surfaceContextTestSource(
        projectRoot: app,
        appName: 'demo',
        entry: mounted(entry, 'ChecklistSurface'),
        name: 'onboarding.checklist',
        sample: sampleHostContext(schema),
      );
    }

    test('records them through the generated widget', () async {
      final text = await contextSource(withAppValue);
      expect(text, contains('restage_capture.captureContext('));
      expect(
        text,
        matches(
          RegExp(
            r"return restage_capture_type0\.ChecklistSurface\(owner: 'Owner'\);",
          ),
        ),
      );
    });

    test('skips a surface with none', () async {
      final text = await contextSource(
        SurfaceScreenHostDataSchema({
          'owner': const SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
        }),
      );
      expect(text, isNull);
    });

    test('names each value by the expression it comes from', () {
      expect(
        hostDataAppValueLabels(
          SurfaceScreenHostDataSchema({
            '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
              SurfaceScreenHostDataScalarKind.integer,
            ).withLabel('VColors.of(context).ink'),
            'plants': SurfaceScreenHostDataListShapeV1(
              SurfaceScreenHostDataObjectShapeV1({
                '_hfedcba9876': const SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.integer,
                ).withLabel('Tones.of(context).colorFor(plant.tone)'),
              }),
            ),
          }),
        ),
        ['Tones.of(context).colorFor(plant.tone)', 'VColors.of(context).ink'],
      );
    });

    test('finds a value carried by each item of a list', () {
      expect(
        hostDataHasAppValues(
          SurfaceScreenHostDataSchema({
            'plants': SurfaceScreenHostDataListShapeV1(
              SurfaceScreenHostDataObjectShapeV1({
                '_hfedcba9876': const SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.integer,
                ),
              }),
            ),
          }),
        ),
        isTrue,
      );
    });
  });
}

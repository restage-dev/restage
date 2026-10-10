import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
      'generated const screen and paywall mounts enter presentation with '
      'restricted imports', () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart'
    show
        Paywall,
        Screen,
        Surface,
        Restage,
        RestagePaywall,
        VariantResolver,
        RestageEvent,
        RestagePaywallError,
        RestageScreen,
        SurfaceScreenUnavailablePolicy,
        SurfaceScreenResolver,
        SurfaceScreenUnavailableError,
        SurfaceScreenRef,
        SurfaceScreenEventContract,
        SurfaceScreenRuntimeProvenance,
        CapabilityManifest,
        LibraryRequirement,
        SurfaceVocabulary,
        RestageWidgetLibraries,
        buildText;
part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'offer')
final class Offer extends StatelessWidget {
  const Offer({super.key});
  @override
  Widget build(BuildContext context) => const Text('Offer');
}

@Screen(id: 'details', surface: Surface.general)
final class Details extends StatelessWidget {
  const Details(this.title, [this.count = 2]);
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Text(title);
}
''';
    final readerWriter =
        await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      {'apps_examples|lib/offer.dart': source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    final generated = utf8.decode(
      bundle.ownedOutputs['lib/restage.generated/offer.restage.g.dart']!,
    );
    const calls = '''
const originalDetails = DetailsSurface('original', 3);
const defaultDetails = DetailsSurface('default');
const namedDetails = DetailsSurface.atPlacement('details_card', 'named', 4);
const originalOffer = OfferSurface();
const namedOffer = OfferSurface.atPlacement('offer_card');

Future<void> presentDetails(BuildContext context) => Restage.presentPlacement(
  context,
  builder: (_, presentation) => namedDetails,
);

Future<void> presentOffer(BuildContext context) => Restage.presentPlacement(
  context,
  builder: (_, presentation) => originalOffer,
);
''';
    const sourceId = 'apps_examples|lib/offer.dart';
    await resolveWorkspaceSources(
      {
        sourceId: '$source\n$calls',
        'apps_examples|lib/restage.generated/offer.restage.g.dart': generated,
      },
      (resolver) async {
        final library = await resolver.libraryFor(AssetId.parse(sourceId));
        final resolved =
            await library.session.getResolvedLibraryByElement(library);
        expect(resolved, isA<ResolvedLibraryResult>());
        final errors = [
          for (final unit in (resolved as ResolvedLibraryResult).units)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error)
                '${unit.path}: ${diagnostic.message}',
        ];
        expect(errors, isEmpty, reason: 'generated helper calls must compile');
        for (final name in [
          'originalDetails',
          'defaultDetails',
          'namedDetails',
          'originalOffer',
          'namedOffer',
        ]) {
          expect(
            library.topLevelVariables
                .singleWhere((variable) => variable.name == name)
                .computeConstantValue(),
            isNotNull,
            reason: '$name must remain a const call',
          );
        }
      },
      resolverFor: sourceId,
      rootPackage: 'apps_examples',
    );
  });

  for (final hide in [false, true]) {
    test('optional paywall mount preserves restricted existing imports: $hide',
        () async {
      const template = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart' hide RestagePaywallError;
part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'offer')
final class Offer extends StatelessWidget {
  const Offer({super.key});
  @override
  Widget build(BuildContext context) => const Text('Offer');
}

@Screen(id: 'details')
final class Details extends StatelessWidget {
  const Details({super.key});
  @override
  Widget build(BuildContext context) => const Text('Details');
}
''';
      final source = hide
          ? template
          : template.replaceFirst(' hide RestagePaywallError', '');
      final readerWriter =
          await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
      final messages = <String>[];
      final result = await testBuilder(
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
        {'apps_examples|lib/offer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: (record) => messages.add(record.message),
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final bundle = RestageSurfacePublicationBundle.fromJson(
        jsonDecode(
          readerWriter.testing.readString(
            AssetId(
              'apps_examples',
              kRestageSurfacePublicationCompilerBundlePath,
            ),
          ),
        ),
      );

      expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
      expect(
        messages
            .where((message) => message.contains('OfferSurface was omitted')),
        hasLength(hide ? 1 : 0),
      );
    });
  }
}

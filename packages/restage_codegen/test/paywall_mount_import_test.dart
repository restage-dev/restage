import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
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

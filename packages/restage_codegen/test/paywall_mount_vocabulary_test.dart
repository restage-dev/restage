import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<String> _generatedPart(String source) async {
  final readerWriter =
      await readerWriterWithFilesystemSources(rootPackage: 'apps_examples');
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
    {'apps_examples|lib/entry.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final bundle = RestageSurfacePublicationBundle.fromJson(
    jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
      ),
    ),
  );
  expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
  return utf8.decode(
    bundle.ownedOutputs['lib/restage.generated/entry.restage.g.dart']!,
  );
}

void main() {
  test('a paywall mount installs the widgets its own surface draws', () async {
    final generated = await _generatedPart('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/entry.restage.g.dart';

@Paywall(id: 'entry_offer')
final class EntryOffer extends StatelessWidget {
  const EntryOffer({super.key});
  @override
  Widget build(BuildContext context) => const Card(child: Text('Entry'));
}
''');
    expect(generated, contains("'Text': buildText"));
    expect(generated, contains("'Card': buildCard"));
    expect(generated, contains('.addToInstalled();'));
  });

  test('a paywall mount also installs what its pushed screens draw', () async {
    final generated = await _generatedPart('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'restage.generated/entry.restage.g.dart';

@Paywall(id: 'entry_offer')
final class EntryOffer extends StatelessWidget {
  const EntryOffer({super.key});
  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Text('Entry'),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PushedOffer()),
            ),
            child: const Text('All plans'),
          ),
          GestureDetector(
            onTap: paywallEvent('skip'),
            child: const Text('Not now'),
          ),
        ],
      );
}

@Paywall(id: 'pushed_offer')
final class PushedOffer extends StatelessWidget {
  const PushedOffer({super.key});
  @override
  Widget build(BuildContext context) => const Card(child: Text('Pushed'));
}
''');
    // `Card` is drawn only by the pushed screen, which the entry paywall
    // reaches through its lowered navigation.
    final entryMount = generated.substring(
      generated.indexOf('class EntryOfferSurface'),
      generated.indexOf('class PushedOfferSurface'),
    );
    expect(entryMount, contains("'Card': buildCard"));
    expect(entryMount, contains("'Column': buildColumn"));
  });
}

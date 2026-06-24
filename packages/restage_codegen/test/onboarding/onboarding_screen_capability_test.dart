import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// The no-fail-open invariant for the reachable (inline) Dart-screen case.
///
/// A custom `@RestageWidget` referenced in a Dart-authored onboarding screen is
/// either inlinable (4a) — inlined into the built-ins the client already has —
/// or non-inlinable (4b) — a loud build failure. It is never emitted as a
/// custom-library *reference*, so a Dart screen's emitted RFW carries only
/// built-in widgets and its capability sidecar correctly requires no custom
/// library. (Only the raw-DSL paywall path emits a bare catalog reference; that
/// population link is proven by `builder_end_to_end_test`.)
///
/// This guard locks the consequence `custom_widget_e2e_test` does not assert:
/// that the SCREEN's sidecar `requiredLibraries` is empty *because* the custom
/// widget inlined. If a future codegen change ever made a Dart custom widget
/// emit a silent custom-library reference without updating the derivation, this
/// fails — catching a fail-open before it ships.
void main() {
  test(
      'a custom @RestageWidget in a screen inlines to built-ins → the screen '
      'sidecar requires no custom library (no fail-open)', () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'welcome.rsscreen.g.dart';

@RestageWidget(
  name: 'PromoBanner',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'a promo banner',
)
class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Promo'));
}

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: onboardingEvent(next),
          child: const PromoBanner(),
        ),
      );
}
''';

    final sources = {
      'apps_examples|lib/onboarding/screens/welcome.dart': source,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/onboarding/screens/welcome.dart'),
      source,
    );

    final result = await testBuilders(
      [onboardingScreenBuilder(BuilderOptions.empty)],
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    // The custom widget inlined — the build SUCCEEDS (it did not defer).
    expect(result.succeeded, isTrue);

    final sidecarJson = readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'assets/onboarding/screens/welcome.capability.json',
      ),
    );
    final sidecar = CapabilitySidecar.fromJson(
      jsonDecode(sidecarJson) as Map<String, dynamic>,
    );

    // The inlined screen references only built-ins → no custom library is
    // required, and the floor is baseline. The custom `acme.ds` library does
    // NOT leak into the manifest, because the widget was inlined, not
    // referenced.
    expect(sidecar.manifest.requiredLibraries, isEmpty);
    expect(sidecar.manifest.builtInFloor, kBaselineCatalogVersion);
  });
}

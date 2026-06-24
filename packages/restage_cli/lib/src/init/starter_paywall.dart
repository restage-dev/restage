/// Returns a small Dart source file that scaffolds a usable starter
/// paywall for [paywallName].
///
/// The generated widget is flat enough that the codegen pipeline can
/// translate it into an `.rfw` without any custom-widget registration —
/// the user can run `dart run build_runner build` immediately after
/// `restage init` and have a real paywall to publish.
String starterPaywallSource(String paywallName) {
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A starter paywall — replace this with your own design. Edit, then
/// run `dart run build_runner build` to produce the compiled `.rfw`.
@PaywallSource(id: '$paywallName')
class ${_pascalCase(paywallName)}Paywall extends StatelessWidget {
  const ${_pascalCase(paywallName)}Paywall({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Welcome',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This is a starter paywall — edit it and republish to roll out '
                'your real design.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF555555)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Continue'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
''';
}

String _pascalCase(String slug) {
  return slug
      .split(RegExp('[-_]'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
}

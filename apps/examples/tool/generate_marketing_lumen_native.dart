import 'dart:io';

const _input = 'lib/onboarding/screens/lumen_welcome.dart';
const _output = 'lib/generated/marketing_lumen_welcome.g.dart';

void main() {
  var source = File(_input).readAsStringSync();

  source = _replaceOnce(
    source,
    "import 'package:restage/restage.dart';\n\n"
        "part 'restage.generated/lumen_welcome.restage.g.dart';\n\n",
    '',
  );
  source = _replaceOnce(source, '@Screen()\n', '');
  source = _replaceOnce(
    source,
    'class LumenWelcomeScreen extends StatelessWidget {',
    'class MarketingLumenWelcomeScreen extends StatelessWidget {',
  );
  source = _replaceOnce(
    source,
    "  /// Advances to the experience question.\n"
        "  static const next = SurfaceEvent<void>('next');\n\n"
        "  /// Opens the host's sign-in. Declared by the flow as a custom event.\n"
        "  static const signIn = SurfaceEvent<void>('sign_in');\n\n"
        '  const LumenWelcomeScreen({super.key});',
    "  const MarketingLumenWelcomeScreen({\n"
        "    required this.onNext,\n"
        "    required this.onSignIn,\n"
        "    super.key,\n"
        "  });\n\n"
        "  final VoidCallback onNext;\n"
        "  final VoidCallback onSignIn;",
  );
  source = _replaceOnce(source, 'surfaceEvent(next)', 'onNext');
  source = _replaceOnce(source, 'surfaceEvent(signIn)', 'onSignIn');

  final output = File(_output)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
    '// Source: lib/onboarding/screens/lumen_welcome.dart\n\n'
    '$source',
  );
}

String _replaceOnce(String source, String pattern, String replacement) {
  if (pattern.allMatches(source).length != 1) {
    throw StateError('Expected exactly one source match for: $pattern');
  }
  return source.replaceFirst(pattern, replacement);
}

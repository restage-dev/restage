import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/scratch_app.dart';

const _offer = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

@Paywall(id: 'offer')
class OfferPaywall extends StatelessWidget {
  const OfferPaywall({super.key});

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';

// A second paywall claiming the first one's id.
const _duplicate = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/again.restage.g.dart';

@Paywall(id: 'offer')
class AgainPaywall extends StatelessWidget {
  const AgainPaywall({super.key});

  @override
  Widget build(BuildContext context) => const Text('Again');
}
''';

// A real build records what happened in `restage.build.json`: a refusal and
// code that doesn't compile as failed, also when nothing changed since, and
// a fixed build as succeeded.
void main() {
  test(
    'a real build records each refusal as failed, and its fix as succeeded',
    () async {
      final packages = p.normalize(p.join(Directory.current.path, '..'));
      final root = await Directory.systemTemp.createTemp('build_result_');
      addTearDown(() => root.delete(recursive: true));
      final app = p.join(root.path, 'app');
      writeScratchFile(app, 'pubspec.yaml', scratchAppPubspec(packages));
      writeScratchFile(app, 'lib/paywalls/offer.dart', _offer);
      final get = await Process.run('flutter', [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: app);
      expect(get.exitCode, 0, reason: processOutput(get));
      final stamp = File(
        p.join(app, '.restage/build/metadata/restage.build.json'),
      );
      Map<String, Object?> recorded() =>
          jsonDecode(stamp.readAsStringSync()) as Map<String, Object?>;

      final built = await buildScratchApp(app);
      expect(built.exitCode, 0, reason: processOutput(built));
      expect(recorded()['result'], 'succeeded');

      // A refusal, then the same build again with nothing changed.
      writeScratchFile(app, 'lib/paywalls/again.dart', _duplicate);
      for (final attempt in ['refused', 'unchanged']) {
        final refused = await buildScratchApp(app);
        expect(refused.exitCode, isNot(0), reason: attempt);
        expect(recorded()['result'], 'failed', reason: attempt);
        expect(
          (recorded()['errors']! as List).join(),
          anyOf(contains('[duplicateId]'), contains("couldn't compile")),
          reason: attempt,
        );
      }

      // An author error stops the generated code compiling.
      File(p.join(app, 'lib/paywalls/again.dart')).deleteSync();
      writeScratchFile(
        app,
        'lib/paywalls/offer.dart',
        "$_offer\nfinal int broken = 'x';\n",
      );
      final broken = await buildScratchApp(app);
      expect(broken.exitCode, isNot(0), reason: processOutput(broken));
      expect(recorded()['result'], 'failed');
      expect(
        (recorded()['errors']! as List).first,
        startsWith("lib/paywalls/offer.dart doesn't compile: "),
      );

      writeScratchFile(app, 'lib/paywalls/offer.dart', _offer);
      final fixed = await buildScratchApp(app);
      expect(fixed.exitCode, 0, reason: processOutput(fixed));
      expect(recorded()['result'], 'succeeded');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

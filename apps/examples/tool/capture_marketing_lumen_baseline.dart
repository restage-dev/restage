import 'dart:convert';
import 'dart:io';

import 'package:restage_shared/restage_shared.dart';

/// Freezes the compiled Lumen flow before preparing a new version.
void main(List<String> args) {
  final root = args.isEmpty ? 'assets/restage/bundles' : args.single;
  const sources = [
    'lib/onboarding/flows/lumen_onboarding',
    'lib/onboarding/screens/lumen_welcome',
    'lib/onboarding/screens/lumen_experience',
    'lib/onboarding/screens/lumen_goal',
    'lib/onboarding/screens/lumen_reminder',
    'lib/onboarding/screens/lumen_recap',
    'lib/paywalls/lumen_welcome_offer',
  ];
  final entries = [
    for (final source in sources)
      ...RestageBundleCodec.decode(
        File('$root/$source.rsbundle').readAsBytesSync(),
      ).entries,
  ];
  final document = FlowDocumentCodec.decodeJson(
    utf8.decode(
      entries
          .singleWhere(
            (entry) => entry.role == RestageBundleEntryRole.flowDocument,
          )
          .bytes,
    ),
  );
  final payload = FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {
      for (final screen in document.screenArtifacts.entries)
        screen.key: entries
            .singleWhere(
              (entry) =>
                  entry.role == RestageBundleEntryRole.screenBlob &&
                  entry.logicalPath.endsWith('/${screen.value.path}'),
            )
            .bytes,
    },
  );
  final output = File('assets/marketing/lumen_original.payload');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(payload.canonicalBytes);
  stdout.writeln('Captured ${payload.screenBlobs.length} Lumen screens.');
}

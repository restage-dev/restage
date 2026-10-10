import 'dart:async';

import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/publication_upload.dart';
import 'package:restage_cli/src/commands/publish_selection.dart';
import 'package:test/test.dart';

void main() {
  const path = 'assets/restage/measurement/target-profile.v1.json';

  String report(MeasurementProfileWrite profile, [SelectorSyntax? syntax]) {
    final out = StringBuffer();
    runZoned(
      () => reportMeasurementProfileWrite(profile, out),
      zoneValues: syntax == null ? null : selectorSyntaxZoneValues(syntax),
    );
    return out.toString();
  }

  test('names the file it wrote and the pubspec line it added', () {
    expect(
      report(
        const MeasurementProfileWrite(declared: true, pubspecUpdated: true),
      ),
      "Wrote $path, the app's measurement profile.\n"
      'Added $path to flutter.assets in pubspec.yaml.\n',
    );
  });

  test('says nothing more when pubspec.yaml already ships it', () {
    expect(
      report(
        const MeasurementProfileWrite(declared: true, pubspecUpdated: false),
      ),
      "Wrote $path, the app's measurement profile.\n",
    );
  });

  test('an undeclared profile names the line and the opt-in', () {
    const profile = MeasurementProfileWrite(
      declared: false,
      pubspecUpdated: false,
    );
    expect(report(profile), contains('push with --declare-assets'));
    expect(
      report(profile, SelectorSyntax.mcp),
      contains('push with declareAssets: true'),
    );
  });
}

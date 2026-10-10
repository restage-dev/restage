import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:restage_codegen/restage_codegen.dart';
import 'package:test/test.dart';

void main() {
  // Short and tall style lay out this declaration differently.
  const source = 'final value = SomeType<Argument>.generatedWithAVeryLongName( '
      'provenance: provenanceValue, eventContract: eventContractValue);';

  for (final version in [Version(3, 5, 0), Version(3, 10, 0)]) {
    test('output at $version is what dart format writes for it', () {
      final formatted = formatGeneratedDart(source, languageVersion: version);
      expect(
        formatted,
        DartFormatter(languageVersion: version).format(source),
      );
    });
  }

  test('the style follows the language version', () {
    expect(
      formatGeneratedDart(source, languageVersion: Version(3, 10, 0)),
      isNot(formatGeneratedDart(source, languageVersion: Version(3, 5, 0))),
    );
  });
}

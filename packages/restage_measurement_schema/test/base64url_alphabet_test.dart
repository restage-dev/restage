import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:test/test.dart';

void main() {
  test('accepts exactly the unpadded base64url alphabet', () {
    expect(
      isUnpaddedBase64UrlAlphabet(
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_',
      ),
      isTrue,
    );
    for (final value in ['', 'AA==', 'A+B', 'A/B', 'A B', 'Aé', 'A.B']) {
      expect(isUnpaddedBase64UrlAlphabet(value), isFalse, reason: value);
    }
  });

  test('checks a carrier far past the largest upload without overflow', () {
    expect(isUnpaddedBase64UrlAlphabet('A' * (16 * 1024 * 1024)), isTrue);
    expect(
      isUnpaddedBase64UrlAlphabet('${'A' * (16 * 1024 * 1024)}='),
      isFalse,
    );
  });
}

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('surface slug grammar', () {
    test('accepts lowercase letters, digits, hyphens, and underscores', () {
      expect(isValidSurfaceSlug('checkout'), isTrue);
      expect(isValidSurfaceSlug('capture_exit'), isTrue);
      expect(isValidSurfaceSlug('announcement-general'), isTrue);
      expect(isValidSurfaceSlug('9lives'), isTrue);
      expect(isValidSurfaceSlug('a' * maximumSurfaceSlugLength), isTrue);
    });

    test('refuses anything outside the grammar', () {
      for (final refused in const [
        '',
        'Checkout',
        'check out',
        'check.out',
        'check/out',
        '-leading',
        '_leading',
        'café',
        '\u{1F600}',
        'trailing\n',
      ]) {
        expect(
          isValidSurfaceSlug(refused),
          isFalse,
          reason: 'expected `$refused` to be refused',
        );
      }
    });

    test('refuses a slug longer than the maximum', () {
      expect(isValidSurfaceSlug('a' * (maximumSurfaceSlugLength + 1)), isFalse);
    });

    test('validateSurfaceSlug returns the slug or throws with the message', () {
      expect(validateSurfaceSlug('checkout'), 'checkout');
      expect(
        () => validateSurfaceSlug('\u{1F600}'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            surfaceSlugRefusalMessage,
          ),
        ),
      );
    });
  });
}

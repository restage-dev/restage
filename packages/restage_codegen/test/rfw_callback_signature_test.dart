import 'package:restage_codegen/src/rfw_callback_signature.dart';
import 'package:test/test.dart';

void main() {
  group('RfwCallbackSignature', () {
    test('accepts only the target-supported public payload spellings', () {
      for (final source in [
        'ValueChanged<bool>',
        'ValueChanged<int?>',
        'ValueChanged<double>',
        'ValueChanged<num?>',
        'ValueChanged<String?>',
        'ValueChanged<DateTime>',
        'ValueChanged<Duration?>',
        'ValueChanged<List<String?>>',
        'ValueChanged<List<num>>',
      ]) {
        expect(RfwCallbackSignature.parse(source), isNotNull, reason: source);
      }
    });

    test('rejects private, reserved, numeric, and unsupported payload tokens',
        () {
      for (final source in [
        'ValueChanged<_Hidden>',
        'ValueChanged<class>',
        'ValueChanged<augment>',
        'ValueChanged<dynamic>',
        'ValueChanged<123>',
        'ValueChanged<123Value>',
        'ValueChanged<Widget>',
        'ValueChanged<prefix.Value>',
        'ValueChanged<List<_Hidden>>',
        'ValueChanged<List<class>>',
      ]) {
        expect(RfwCallbackSignature.parse(source), isNull, reason: source);
      }
    });
  });
}

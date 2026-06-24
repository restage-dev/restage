import 'package:restage_codegen/src/translator_kernels.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:test/test.dart';

void main() {
  group('packArgb', () {
    test('packs four channels into a single ARGB int', () {
      // Color.fromARGB(255, 0x12, 0x34, 0x56) baseline.
      expect(packArgb([255, 0x12, 0x34, 0x56]), 0xFF123456);
    });
  });

  group('quantizeUnitToByte', () {
    test('rounds opacity*255 to the nearest byte', () {
      // Color.fromRGBO opacity 0.5 -> 127.5 -> 128 baseline.
      expect(quantizeUnitToByte(0.5), 128);
      expect(quantizeUnitToByte(0), 0);
      expect(quantizeUnitToByte(1), 255);
    });
  });

  group('formatColorHex', () {
    test('formats as 0x + uppercase + 8-digit zero-padded hex', () {
      expect(formatColorHex(0xFF123456), '0xFF123456');
      expect(formatColorHex(0xabcdef01), '0xABCDEF01');
      expect(formatColorHex(0x00000000), '0x00000000');
    });
  });

  group('runValueKernel', () {
    test('dispatches packArgb by enum', () {
      expect(
        runValueKernel(TranslatorKernel.packArgb, [255, 1, 2, 3]),
        (255 << 24) | (1 << 16) | (2 << 8) | 3,
      );
    });

    test('dispatches quantizeUnitToByte by enum', () {
      expect(runValueKernel(TranslatorKernel.quantizeUnitToByte, [0.5]), 128);
    });

    test('accepts an integer opacity literal', () {
      // The hand-authored Color.fromRGBO accepts an IntegerLiteral opacity
      // (Color.fromRGBO(0, 0, 0, 1)) via _doubleLiteralValue, so the kernel
      // path must accept a bare int input rather than reject it.
      expect(runValueKernel(TranslatorKernel.quantizeUnitToByte, [1]), 255);
      expect(runValueKernel(TranslatorKernel.quantizeUnitToByte, [0]), 0);
    });

    test('throws when handed a fragment kernel', () {
      expect(
        () => runValueKernel(TranslatorKernel.formatColorHex, [0]),
        throwsArgumentError,
      );
    });
  });

  group('runFragmentKernel', () {
    test('dispatches formatColorHex by enum', () {
      expect(
        runFragmentKernel(TranslatorKernel.formatColorHex, [0xFF123456]),
        '0xFF123456',
      );
    });

    test('throws when handed a value kernel', () {
      expect(
        () => runFragmentKernel(TranslatorKernel.packArgb, [1, 2, 3, 4]),
        throwsArgumentError,
      );
    });
  });
}

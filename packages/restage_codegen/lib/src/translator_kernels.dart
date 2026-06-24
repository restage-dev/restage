import 'package:restage_codegen/src/translator_recipe.dart';

/// Bit-packs four 0..255 channel values `[a, r, g, b]` into a single
/// 32-bit ARGB integer. Mirrors Flutter's `Color` channel layout.
int packArgb(List<int> argb) =>
    (argb[0] << 24) | (argb[1] << 16) | (argb[2] << 8) | argb[3];

/// Quantizes a 0.0..1.0 unit value to a 0..255 byte using the same
/// rounding rule Flutter's `Color.fromRGBO` applies to opacity.
int quantizeUnitToByte(double x) => (x * 255).round();

/// Formats an ARGB integer as the RFW color literal `0xAARRGGBB`:
/// `0x` prefix, uppercase, zero-padded to 8 hex digits.
String formatColorHex(int v) =>
    '0x${v.toRadixString(16).toUpperCase().padLeft(8, '0')}';

/// Runs a scalar-producing kernel over its already-evaluated [inputs].
///
/// Throws [ArgumentError] when [kernel] is a fragment kernel — recipes are
/// constructed so this never happens at translation time.
Object runValueKernel(TranslatorKernel kernel, List<Object> inputs) {
  switch (kernel) {
    case TranslatorKernel.packArgb:
      return packArgb(inputs.cast<int>());
    case TranslatorKernel.quantizeUnitToByte:
      // Accept an integer opacity literal as well as a double — the
      // hand-authored Color.fromRGBO coerces an int opacity to double.
      return quantizeUnitToByte((inputs.single as num).toDouble());
    case TranslatorKernel.formatColorHex:
      throw ArgumentError('formatColorHex produces a fragment, not a value.');
  }
}

/// Runs a fragment-producing kernel over its already-evaluated [inputs].
///
/// Throws [ArgumentError] when [kernel] is a value kernel — recipes are
/// constructed so this never happens at translation time.
String runFragmentKernel(TranslatorKernel kernel, List<Object> inputs) {
  switch (kernel) {
    case TranslatorKernel.formatColorHex:
      return formatColorHex(inputs.single as int);
    case TranslatorKernel.packArgb:
    case TranslatorKernel.quantizeUnitToByte:
      throw ArgumentError('$kernel produces a value, not a fragment.');
  }
}

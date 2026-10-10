import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show measurementDisclosureFloor;

/// How a held count reads: "<5".
const String heldCountText = '<$measurementDisclosureFloor';

/// A count as shown: [exact] with thousands grouped; "≈N" from [approx] when a
/// held count is inside it; or "<5" when it is one held count.
String countText(int? exact, {int? approx}) => exact != null
    ? groupedCount(exact)
    : approx != null
    ? '≈${groupedCount(approx)}'
    : heldCountText;

/// [value] with thousands separated by commas.
String groupedCount(int value) {
  final digits = value.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$grouped';
}

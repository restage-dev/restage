/// How a missing count reads under the [floor] the response states: "<N", or
/// "Not available" where the floor holds nothing back.
String heldCountText(int floor) => floor <= 1 ? 'Not available' : '<$floor';

/// A count as shown: [exact] with thousands grouped; "≈N" from [approx] when a
/// held count is inside it; or "<N" when it is one held count under [floor].
String countText(int? exact, {required int floor, int? approx}) => exact != null
    ? groupedCount(exact)
    : approx != null
    ? '≈${groupedCount(approx)}'
    : heldCountText(floor);

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

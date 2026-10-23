/// How a user count held under the disclosure floor may be shown.
library;

import 'dart:math' as math;

/// A held total's public stand-in, built only from the parts stated beside
/// it: the stated mass plus two for each held part, rounded to the nearest 10
/// under 1,000, the nearest 100 under 10,000, and three significant figures
/// above. It never reads zero.
int measurementApproxTotalV1({
  required int statedMass,
  required int heldCells,
}) {
  final value = statedMass + 2 * heldCells;
  final step = value < 1000
      ? 10
      : value < 10000
          ? 100
          : math.pow(10, '$value'.length - 3).toInt();
  return math.max(step, (value + step ~/ 2) ~/ step * step);
}

/// A sum over [parts], each stated or held (null), as it may be shown: the
/// exact sum when every part is stated; neither when it is one held part
/// alone, which reads as held; otherwise the rounded stand-in.
({int? exact, int? approx}) measurementDisclosedSumV1(Iterable<int?> parts) {
  var stated = 0;
  var held = 0;
  for (final part in parts) {
    if (part == null) {
      held++;
    } else {
      stated += part;
    }
  }
  if (held == 0) return (exact: stated, approx: null);
  if (held == 1 && stated == 0) return (exact: null, approx: null);
  return (
    exact: null,
    approx: measurementApproxTotalV1(statedMass: stated, heldCells: held),
  );
}

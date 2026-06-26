import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A simple star-rating control — a controlled component the host data model
/// drives: a current [rating] value plus an [onRatingChanged] callback that
/// reports the tapped value back. One value property + one matching-type
/// `ValueChanged` callback, so the A2UI catalog wires the two-way binding
/// automatically (no pairing annotation needed) — tapping a star writes the new
/// rating into the data model and the control re-renders from it.
@RestageWidget(
  name: 'RatingPicker',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
  description: 'A 1–5 star rating control bound to an integer value.',
  fires: [WidgetEventName.onChanged],
)
class RatingPicker extends StatelessWidget {
  /// Creates a rating control showing [rating] stars selected and reporting
  /// taps via [onRatingChanged].
  const RatingPicker({
    required this.rating,
    required this.onRatingChanged,
    super.key,
  });

  /// The currently selected rating (1–5), the two-way-bound value.
  @RestageProperty(description: 'The selected rating, 1 through 5.')
  final int rating;

  /// Fired with the tapped star's value — the write-back callback.
  @RestageProperty(description: 'Reports the newly selected rating.')
  final ValueChanged<int> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          GestureDetector(
            key: ValueKey('rating-star-$star'),
            onTap: () => onRatingChanged(star),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                star <= rating ? '★' : '☆',
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kHostListItemPositionKey, measurementInteractionItemIsValidV1;
import 'package:restage_shared/src/rfw_formats.dart' show LoopReference;

/// Whether [value] is an item a compiled tap may carry: a literal item, or the
/// index of the host list element it sits in.
///
/// Elements a static list repeats share one route and carry one literal item
/// each; a route carried by more than one tap is admitted only when every tap
/// carries an item.
bool isMeasurementTapItemV1(Object? value) =>
    (value is String && measurementInteractionItemIsValidV1(value)) ||
    (value is LoopReference &&
        value.parts.length == 1 &&
        value.parts.single == kHostListItemPositionKey);

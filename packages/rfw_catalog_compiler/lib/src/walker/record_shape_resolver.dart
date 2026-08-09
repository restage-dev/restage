import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/type_alias_unwrapper.dart';
import 'package:rfw_catalog_compiler/src/walker/value_shape_resolver.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One admitted label of a record slot, in the analyzer's canonical name order.
typedef RecordLabel = ({
  String name,
  DartType dartType,
  CatalogValueShape shape,
});

/// Classification of a Dart type at the record-slot boundary.
sealed class RecordClassification {
  const RecordClassification();
}

/// The classified type is not a record at all; the caller falls through to
/// its existing handling.
final class NotARecord extends RecordClassification {
  /// Creates the not-a-record verdict.
  const NotARecord();
}

/// The classified type is a record inside the admitted boundary.
final class RecordAdmitted extends RecordClassification {
  /// Creates the admitted verdict carrying [labels].
  const RecordAdmitted(this.labels);

  /// Admitted labels in the analyzer's canonical name order.
  final List<RecordLabel> labels;
}

/// The classified type is a record outside the admitted boundary.
final class RecordExcluded extends RecordClassification {
  /// Creates the excluded verdict carrying [reason].
  const RecordExcluded(this.reason);

  /// Customer-actionable sentence naming the offending label or property.
  final String reason;
}

/// Classifies [type] against the named-record value boundary.
RecordClassification classifyRecordType(
  DartType type, {
  WidgetLibrary? library,
  PolicyLedger? policy,
  bool admitNullableSlot = false,
}) {
  final originalSlotIsNullable =
      type.nullabilitySuffix != NullabilitySuffix.none;
  final unwrapped = unwrapTypeAliases(type);
  if (unwrapped is! RecordType) return const NotARecord();

  if (originalSlotIsNullable ||
      unwrapped.nullabilitySuffix != NullabilitySuffix.none) {
    if (!admitNullableSlot) {
      return const RecordExcluded(
        'a nullable record slot is unsupported in this position; use a '
        'non-nullable record',
      );
    }
  }
  if (unwrapped.positionalFields.isNotEmpty) {
    return const RecordExcluded(
      'a record slot with positional fields is unsupported; use named labels',
    );
  }
  if (unwrapped.namedFields.isEmpty) {
    return const RecordExcluded(
      'an empty record carries no state; add a non-nullable scalar or enum '
      'label',
    );
  }

  final labels = <RecordLabel>[];
  for (final field in unwrapped.namedFields) {
    final name = field.name;
    if (name.startsWith('_')) {
      return RecordExcluded(
        "record label '$name' is private; use a public label",
      );
    }
    // Read the label's nullability BEFORE any alias unwrapping: unwrapping
    // discards the outer suffix, so a nullable alias would read as
    // non-nullable. The order here is deliberate — do not hoist an unwrap
    // above this check.
    if (field.type.nullabilitySuffix != NullabilitySuffix.none) {
      return RecordExcluded(
        "record label '$name' is nullable; a record slot admits only "
        'non-nullable scalar or enum labels',
      );
    }

    // A record label may not itself be a record. Rejecting that shape before
    // value-shape resolution keeps the contract one level deep and removes
    // any need for a record-depth budget.
    final nestedRecord = classifyRecordType(
      field.type,
      library: library,
      policy: policy,
    );
    if (nestedRecord is! NotARecord) {
      return RecordExcluded(
        "record label '$name' is itself a record; a record slot admits only "
        'non-nullable scalar or enum labels',
      );
    }

    final shape = resolveValueShape(
      field.type,
      library: library,
      policy: policy,
    );
    // The explicit null check is load-bearing for flow analysis as well as for
    // the boundary: Dart cannot promote a variable to the UNION of two negated
    // type tests, so `shape` stays nullable past the guard without it.
    if (shape == null || (shape is! ScalarShape && shape is! EnumShape)) {
      return RecordExcluded(
        "record label '$name' has unsupported type "
        "'${field.type.getDisplayString()}'; a record slot admits only "
        'non-nullable scalar or enum labels',
      );
    }
    labels.add((name: name, dartType: field.type, shape: shape));
  }

  return RecordAdmitted(labels);
}

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'measurement_resolved_flutter_event.dart';
part 'measurement_resolved_opaque_custom_widget_event.dart';

/// Exact compiler-resolved declaration provenance for one source event slot.
///
/// This remains compiler-side evidence. The contract freezes only
/// [sourceSelector] into the point occurrence preimage; library, class, and
/// member are not new wire or hash-domain fields.
final class MeasurementEventDeclarationProvenance {
  /// Creates exact declaration provenance for one resolved event member.
  MeasurementEventDeclarationProvenance({
    required this.libraryUri,
    required this.className,
    required this.memberName,
    required this.sourceSelector,
  }) {
    if (libraryUri.isEmpty || className.isEmpty || memberName.isEmpty) {
      throw ArgumentError(
        'Event declaration provenance requires library, class, and member',
      );
    }
    if (sourceSelector.value != memberName) {
      throw ArgumentError(
        'The frozen source selector must equal the exact declared event member',
      );
    }
  }

  /// Defining library of the declared event member.
  final String libraryUri;

  /// Defining class of the declared event member.
  final String className;

  /// Exact declared callback member name.
  final String memberName;

  /// Frozen source-event selector.
  final SourceEventIdentity sourceSelector;
}

/// A statically resolved compiler event slot admitted to Measurement.
///
/// Implementations retain exact declaration provenance in compiler memory
/// while exposing only the frozen source selector to the producer.
sealed class MeasurementResolvedEvent {
  /// Base constructor for compiler-controlled resolved event evidence.
  const MeasurementResolvedEvent();

  /// Exact compiler-only declaration provenance.
  MeasurementEventDeclarationProvenance get declarationProvenance;

  /// Frozen source-event selector used by the point occurrence identity.
  SourceEventIdentity get sourceEventIdentity =>
      declarationProvenance.sourceSelector;

  /// Stable compiler-only diagnostic identity for the resolved declaration.
  String get resolvedSemanticIdentity;
}

import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kMeasurementPublicationTapEventNameV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

/// Checks a pure integer callback against its installed native signature.
void validateRfwScalarContract(
  Object? value,
  ScalarCallbackContract contract, {
  RfwProgramScope? scope,
  Map<String, ValueOperation> operations = const {
    ...kCollectionValueOperations,
    ...kGridValueOperations,
    ...kIntlValueOperations
  },
}) {
  if (value is Map && value.containsKey('nativeKeyIndex')) {
    if (value.length != 1 ||
        !contract.nullableResult ||
        contract.parameters.singleOrNull != ScalarCallbackParameter.valueKey) {
      throw const FormatException('Native key callback differs from its slot.');
    }
    final native = decodeRfwProgramEnvelope(value['nativeKeyIndex'],
        operations: operations, scope: scope);
    if (native == null ||
        native.builder != null ||
        native.values.parameters.isNotEmpty ||
        native.values.nodes[native.values.root].type.kind != 'native' ||
        native.values.nodes[native.values.root].type.nativeType !=
            'flutter.ChildIndexGetter') {
      throw const FormatException(
          'Native key callback requires its fixed typed value.');
    }
    return;
  }
  final envelope =
      decodeRfwProgramEnvelope(value, operations: operations, scope: scope);
  if (envelope == null || envelope.builder != null) {
    throw const FormatException('Scalar program differs from its callback.');
  }
  validateScalarCallbackProgramContract(envelope.values, contract);
}

/// Unwraps the canonical presence convention shared by native callbacks.
Object? normalizeRfwCallbackPresence(Object? value, PropertyEntry property) {
  if ((property.type == PropertyType.widgetBuilder ||
          property.type == PropertyType.scalarCallback) &&
      RfwConstructorPresenceProtocol.appliesTo(property)) {
    if (value is! Map ||
        value[RfwConstructorPresenceProtocol.markerKey] is! int ||
        value[RfwConstructorPresenceProtocol.markerKey] !=
            RfwConstructorPresenceProtocol.version ||
        value.keys.any((key) =>
            key != RfwConstructorPresenceProtocol.markerKey &&
            key != RfwConstructorPresenceProtocol.valueKey)) {
      throw const FormatException('Malformed native callback presence.');
    }
    value = value[RfwConstructorPresenceProtocol.valueKey];
  }
  return value;
}

/// Validates callback signatures throughout a catalog-linked property value.
int validateRfwPropertyCallbacks(
  Object? value,
  PropertyEntry property,
  Catalog catalog, {
  RfwProgramScope? scope,
  Map<String, ValueOperation> operations = const {
    ...kCollectionValueOperations,
    ...kGridValueOperations,
    ...kIntlValueOperations
  },
}) {
  value = normalizeRfwCallbackPresence(value, property);
  final structured = {
    for (final entry in catalog.structuredTypes)
      (entry.library.namespace, entry.wireId.value): entry,
  };
  final unions = {
    for (final entry in catalog.unions)
      (entry.library.namespace, entry.wireId.value): entry,
  };
  StructuredEntry? resolve(WireIdRef? ref) =>
      ref == null ? null : structured[(ref.library, ref.wireId.value)];
  var floor = 1;
  final admitted = Set<Object>.identity();
  void visit(
      Object? value,
      PropertyType type,
      CatalogValueShape? shape,
      WireIdRef? structuredRef,
      WireIdRef? unionRef,
      WidgetBuilderContract? builder,
      ScalarCallbackContract? scalar,
      int depth,
      {bool nullableCallback = false}) {
    if (value == null &&
        (type == PropertyType.scalarCallback ||
            type == PropertyType.widgetBuilder)) {
      if (nullableCallback) return;
      throw const FormatException(
          'Nonnullable native callback cannot be null.');
    }
    if (depth > 64) {
      throw const FormatException('Callback shape exceeds depth limit.');
    }
    if (value is rfw.Switch) {
      for (final output in value.outputs.values) {
        visit(
          output,
          type,
          shape,
          structuredRef,
          unionRef,
          builder,
          scalar,
          depth + 1,
          nullableCallback: nullableCallback,
        );
      }
      return;
    }
    if (type == PropertyType.event &&
        value is Map &&
        value.containsKey('nativeEvent')) {
      if (type != PropertyType.event ||
          property.callbackSignature != null ||
          value.keys.any(
            (key) => key != 'nativeEvent' && key != 'measurement',
          ) ||
          value.containsKey('measurement') &&
              (value['measurement'] is! rfw.EventHandler ||
                  (value['measurement'] as rfw.EventHandler).eventName !=
                      kMeasurementPublicationTapEventNameV1)) {
        throw const FormatException('Invalid native event slot.');
      }
      final reference = value['nativeEvent'];
      final envelope = decodeRfwProgramEnvelope(
        reference,
        operations: operations,
        scope: scope,
      );
      final valid = envelope != null
          ? envelope.builder == null &&
              envelope.values.nodes[envelope.values.root].type.kind ==
                  'native' &&
              envelope.values.nodes[envelope.values.root].type.nativeType ==
                  kNativeVoidCallbackType
          : reference is rfw.DataReference ||
              reference is Map &&
                  const {
                    'nativeBinding',
                    'nativeLocal',
                  }.contains(reference['kind']) &&
                  reference['type'] == kNativeVoidCallbackType &&
                  reference['nullable'] is bool;
      if (!valid) {
        throw const FormatException('Native event requires a void callback.');
      }
      admitted.add(value);
      floor = 24;
      return;
    }
    if (type == PropertyType.scalarCallback) {
      if (scalar == null) {
        throw const FormatException('Missing native scalar callback contract.');
      }
      validateRfwScalarContract(value, scalar,
          operations: operations, scope: scope);
      admitted.add(value!);
      final required =
          value is Map && value.containsKey('nativeKeyIndex') ? 24 : 20;
      if (floor < required) floor = required;
      return;
    }
    if (type == PropertyType.widgetBuilder) {
      if (builder == null) {
        throw const FormatException('Missing native builder contract.');
      }
      validateRfwBuilderContract(value, builder,
          operations: operations, scope: scope);
      if (floor < 19) floor = 19;
      return;
    }
    if (type == PropertyType.inlineSpan) {
      if (value is rfw.Loop) {
        visit(value.output, type, null, null, null, null, null, depth + 1);
      } else if (value is List) {
        for (final child in value) {
          visit(child, type, null, null, null, null, null, depth + 1);
        }
      } else if (value is Map) {
        final recognizer = value['recognizer'];
        if (recognizer is Map) {
          for (final name
              in kTextSpanRecognizerVoidCallbacks[recognizer['kind']] ??
                  <String>{}) {
            if (recognizer.containsKey(name)) {
              visit(recognizer[name], PropertyType.event, null, null, null,
                  null, null, depth + 1,
                  nullableCallback: true);
            }
          }
        }
        visit(value['children'], type, null, null, null, null, null, depth + 1);
      }
      return;
    }
    if (shape case ListShape(:final itemShape)) {
      if (value is List) {
        for (final item in value) {
          visit(
            item,
            itemShape.propertyType,
            itemShape,
            null,
            null,
            null,
            null,
            depth + 1,
          );
        }
      }
      return;
    }
    if (value is! Map) return;
    final direct = resolve(
      structuredRef ?? (shape is StructuredShape ? shape.structuredRef : null),
    );
    final unionTarget =
        unionRef ?? (shape is UnionShape ? shape.unionRef : null);
    final union = unionTarget == null
        ? null
        : unions[(unionTarget.library, unionTarget.wireId.value)];
    var entry = direct;
    if (union != null) {
      final tag = value[union.discriminator.field];
      final members =
          union.members.map(resolve).whereType<StructuredEntry>().toList();
      final matches = members
          .where(
            (member) =>
                tag == member.wireId.value ||
                tag == member.name ||
                tag == member.sourceType.split('#').last,
          )
          .toList();
      if (matches.length == 1) {
        entry = matches.single;
      } else if (members.any(
        (member) => member.fields.any(
          (field) =>
              field.builderContract != null || field.scalarContract != null,
        ),
      )) {
        throw const FormatException(
          'Unknown structured callback discriminator.',
        );
      }
    }
    if (entry == null) return;
    for (final field in entry.fields) {
      if (!value.containsKey(field.name)) {
        if (field.required &&
            (field.builderContract != null || field.scalarContract != null)) {
          throw const FormatException('Missing required structured callback.');
        }
        continue;
      }
      visit(
        value[field.name],
        field.type,
        field.valueShape,
        field.structuredRef,
        field.unionRef,
        field.builderContract,
        field.scalarContract,
        depth + 1,
        nullableCallback: entry.variants
            .whereType<ConstructorVariant>()
            .expand((variant) => variant.parameters)
            .any((parameter) =>
                parameter.name == field.name && parameter.nullable),
      );
    }
  }

  visit(
    value,
    property.type,
    property.valueShape,
    property.structuredRef,
    null,
    property.builderContract,
    property.scalarContract,
    0,
    nullableCallback: property.constructorNullable,
  );
  void checkAdmission(Object? value) {
    final envelope =
        decodeRfwProgramEnvelope(value, operations: operations, scope: scope);
    if (envelope != null &&
        envelope.builder == null &&
        envelope.values.parameters.entries.any(
          (parameter) => isScalarCallbackParameterValueType(
            parameter.key,
            parameter.value,
          ),
        ) &&
        !admitted.contains(value)) {
      throw const FormatException(
        'Native scalar parameters require a callback slot.',
      );
    }
    if (envelope != null) return;
    switch (value) {
      case rfw.Switch(:final input, :final outputs):
        checkAdmission(input);
        outputs.values.forEach(checkAdmission);
      case rfw.Loop(:final input, :final output):
        checkAdmission(input);
        checkAdmission(output);
      case Map():
        value.values.forEach(checkAdmission);
      case List():
        value.forEach(checkAdmission);
    }
  }

  checkAdmission(value);
  return floor;
}

/// Generated adapters needed by a property's complete callback shape.
int rfwCallbackGeneratedFloor(PropertyEntry property, Catalog catalog) {
  final structured = {
    for (final entry in catalog.structuredTypes)
      (entry.library.namespace, entry.wireId.value): entry,
  };
  final unions = {
    for (final entry in catalog.unions)
      (entry.library.namespace, entry.wireId.value): entry,
  };
  final seen = <(String, String)>{};
  var floor = 1;
  void visit(
    PropertyType type,
    CatalogValueShape? shape,
    WireIdRef? direct,
    WireIdRef? union,
  ) {
    if (type == PropertyType.scalarCallback) floor = 3;
    if (type == PropertyType.widgetBuilder && floor < 3) floor = 3;
    if (shape case ListShape(:final itemShape)) {
      visit(itemShape.propertyType, itemShape, null, null);
    }
    final reference = direct ??
        union ??
        switch (shape) {
          StructuredShape(:final structuredRef) => structuredRef,
          UnionShape(:final unionRef) => unionRef,
          _ => null,
        };
    if (reference == null) return;
    final key = (reference.library, reference.wireId.value);
    if (!seen.add(key)) return;
    final entry = structured[key];
    if (entry != null) {
      for (final field in entry.fields) {
        visit(
          field.type,
          field.valueShape,
          field.structuredRef,
          field.unionRef,
        );
      }
    } else {
      for (final member in unions[key]?.members ?? <WireIdRef>[]) {
        visit(PropertyType.structured, null, member, null);
      }
    }
  }

  visit(property.type, property.valueShape, property.structuredRef, null);
  return floor;
}

import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// The top-level provider shared by a mount and its generated roster entry.
String placementDefinitionProviderName(String declarationName) =>
    '${lowerCamelIdentifier(declarationName, fallback: 'surface')}'
    'PlacementDefinition';

/// Generated declaration names claimed alongside the existing surface handle.
Set<String> placementDefinitionSymbols(String declarationName) {
  final provider = placementDefinitionProviderName(declarationName);
  return {provider, '_${provider}Value'};
}

/// Emits a validated default coordinate and the exact compiler-projected host.
String emitPlacementDefinition({
  required String declarationName,
  required String defaultSurfaceArgument,
  required Surface surface,
  required String slug,
  required SurfaceHostContractV1 hostContract,
  required String sdkHost,
  String? vocabulary,
  int? screenContractVersion,
}) {
  final surfaceType = DeliverySurfaceTypeId(surface.wireName);
  final family = screenContractVersion == null
      ? const DeliveryFamilySelectorV1.general()
      : DeliveryFamilySelectorV1.screenContract(
          contractVersion: screenContractVersion,
        );
  final locator = DeliverySurfaceLocatorV1(
    surfaceType: surfaceType,
    slug: slug,
    family: family,
  );
  PlacementKeyV1.generatedDefault(surfaceType: surfaceType, slug: slug);
  final provider = placementDefinitionProviderName(declarationName);
  return '''
final _${provider}Value = $sdkHost.generatedPlacementDefinition(
  $defaultSurfaceArgument,
  defaultSurfaceLocatorJson: ${_contractLiteral(locator.toJson())},
  hostContractJson: ${_contractLiteral(hostContract.toJson())},
  ${vocabulary == null ? '' : 'vocabulary: $vocabulary,'}
);

final $provider = () => _${provider}Value;
''';
}

String _contractLiteral(Object? value) => switch (value) {
      null => 'null',
      String() => dartStringLiteral(value),
      bool() || num() => '$value',
      // Typed literals keep empty collections decodable as JSON objects.
      List<Object?>() => '<Object?>[${value.map(_contractLiteral).join(', ')}]',
      Map<String, Object?>() => '<String, Object?>{${value.entries.map(
            (entry) => '${dartStringLiteral(entry.key)}: '
                '${_contractLiteral(entry.value)}',
          ).join(', ')}}',
      _ => throw ArgumentError.value(value, 'value'),
    };

/// Builds the inert host-data contract one screen declares.
///
/// The set is exactly what a generated mount publishes under the render
/// context: every non-key constructor parameter that resolved to a host-data
/// shape. A screen declaring none yields the empty schema, whose contract hash
/// is absent, so its fingerprint stays what it was before host data existed.
SurfaceScreenHostDataSchema hostDataContractOf(
  Iterable<RootContextParam> rootParams,
) =>
    SurfaceScreenHostDataSchema(<String, SurfaceScreenHostDataShape>{
      for (final param in rootParams)
        if (!param.forwardsFlutterKey && param.hostDataShape != null)
          param.name: hostDataContractShapeOf(param.hostDataShape!),
    });

/// Converts one resolved host-data shape to its inert contract form.
SurfaceScreenHostDataShape hostDataContractShapeOf(HostDataShape shape) {
  final inner = _nonNullContractShapeOf(shape);
  return shape.type.nullabilitySuffix == NullabilitySuffix.question
      ? SurfaceScreenHostDataNullableShapeV1(inner)
      : inner;
}

SurfaceScreenHostDataShape _nonNullContractShapeOf(HostDataShape shape) =>
    switch (shape) {
      HostDataScalarShape(:final kind) =>
        SurfaceScreenHostDataScalarShapeV1(_scalarKindOf(kind)),
      HostDataListShape(:final elementShape) =>
        SurfaceScreenHostDataListShapeV1(
          hostDataContractShapeOf(elementShape),
        ),
      HostDataMapShape(:final valueShape) => SurfaceScreenHostDataMapShapeV1(
          hostDataContractShapeOf(valueShape),
        ),
      HostDataObjectShape(:final fields) => SurfaceScreenHostDataObjectShapeV1(
          <String, SurfaceScreenHostDataShape>{
            for (final field in fields)
              field.wireKey: hostDataContractShapeOf(field.shape),
          },
        ),
    };

SurfaceScreenHostDataScalarKind _scalarKindOf(HostDataScalarKind kind) =>
    switch (kind) {
      HostDataScalarKind.object => SurfaceScreenHostDataScalarKind.jsonValue,
      HostDataScalarKind.boolean => SurfaceScreenHostDataScalarKind.boolean,
      HostDataScalarKind.integer => SurfaceScreenHostDataScalarKind.integer,
      HostDataScalarKind.doubleValue =>
        SurfaceScreenHostDataScalarKind.doubleValue,
      HostDataScalarKind.number => SurfaceScreenHostDataScalarKind.number,
      HostDataScalarKind.string => SurfaceScreenHostDataScalarKind.string,
    };

import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_shared/restage_shared.dart';

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

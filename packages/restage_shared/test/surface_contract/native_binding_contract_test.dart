import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  const controller = NativeBindingContract(type: 'flutter.ScrollController');
  SurfaceScreenHostDataSchema schema(NativeBindingContract contract) =>
      SurfaceScreenHostDataSchema(
          {'scroll': SurfaceScreenHostDataNativeBindingShapeV1(contract)});

  test('native declaration is strict and part of the host fingerprint', () {
    final original = schema(controller);
    final decoded = SurfaceScreenHostDataSchema.fromJson(original.toJson());
    expect(decoded.toJson(), original.toJson());
    for (final changed in [
      const NativeBindingContract(type: 'flutter.TabController'),
      const NativeBindingContract(
          type: 'flutter.ScrollController', nullable: true),
      const NativeBindingContract(
          type: 'void Function(flutter.TapDownDetails)'),
    ]) {
      expect(SurfaceScreenHostDataContractHash.hash(schema(changed)),
          isNot(SurfaceScreenHostDataContractHash.hash(original)));
    }
    expect(
        () => NativeBindingContract.fromJson({
              'type': controller.type,
              'nullable': false,
              'invoke': 'arbitrary'
            }),
        throwsFormatException);
    expect(
        () => NativeBindingContract.fromJson(
            {'type': controller.type, 'nullable': 'false'}),
        throwsFormatException);
    expect(
        () => NativeBindingContract.fromJson({'type': '', 'nullable': false}),
        throwsFormatException);
  });

  test('fit requires the declared native type and nullability', () {
    const required = SurfaceScreenHostDataNativeBindingShapeV1(controller);
    expect(hostDataShapeAcceptsProvided(required, required), isTrue);
    expect(
        hostDataShapeAcceptsProvided(
            required,
            const SurfaceScreenHostDataNativeBindingShapeV1(
                NativeBindingContract(type: 'flutter.TabController'))),
        isFalse);
    expect(
        hostDataShapeAcceptsProvided(
            required,
            const SurfaceScreenHostDataNativeBindingShapeV1(
                NativeBindingContract(
                    type: 'flutter.ScrollController', nullable: true))),
        isFalse);
  });
}

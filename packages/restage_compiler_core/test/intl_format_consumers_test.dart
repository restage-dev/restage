import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

ValueProgram _program({String operation = 'intl.plural'}) =>
    ValueProgram(nodes: [
      const ValueNode('literal', ValueType.integer, value: 2),
      const ValueNode('literal', ValueType.string, value: 'items'),
      ValueNode(operation, ValueType.string, inputs: const [
        0,
        1
      ], value: const {
        'arguments': ['other']
      }),
    ], root: 2);

Map<String, Object?> _value({String operation = 'intl.plural'}) => {
      'version': 1,
      'program': _program(operation: operation).encode(),
      'captures': <String, Object?>{},
    };
rfw.RemoteWidgetLibrary _library(Object? argument) =>
    rfw.RemoteWidgetLibrary(const [], [
      rfw.WidgetDeclaration(
          'Root', null, rfw.ConstructorCall('Text', {'text': argument})),
    ]);

void main() {
  test('native formatting capability is derived from actual nested use', () {
    expect(surfaceFeatureClientFloor(_library('plain')), 1);
    for (final value in [
      _value(),
      ['prefix', _value()],
      {
        'children': [
          {'text': _value()}
        ]
      },
      {'condition': false, 'then': _value(), 'else': 'plain'},
    ]) {
      expect(surfaceFeatureClientFloor(_library(value)), 23);
    }
    final program = BuilderProgram(
        values: _program(),
        result: BuilderResult.body(0, values: const {'v0': 2}),
        bodyCount: 1);
    expect(
        surfaceFeatureClientFloor(
            _library(rfw.ConstructorCall(kBuilderContinuationWidgetName, {
          'version': 1,
          'program': program.encode(),
          'captures': <String, Object?>{},
          'bodies': [
            rfw.WidgetBuilderDeclaration(
                'frame', const rfw.ConstructorCall('Text', {}))
          ],
        }))),
        23);
  });

  test('actual formatting use rejects an older installed renderer', () {
    final floor = surfaceFeatureClientFloor(_library(_value()));
    final verdict = BlobRenderCapabilityGate.evaluate(
      required:
          CapabilityManifest(builtInFloor: floor, requiredLibraries: const []),
      installed: InstalledCapability(
          builtInCatalogVersion: 22, installedLibraries: const []),
    );
    expect(verdict, isA<BlobRenderRejected>());
    expect((verdict as BlobRenderRejected).reason,
        BlobRenderRejectionReason.capabilityFloorRaised);
  });

  test('publication and fit traversal reject malformed nested operations', () {
    final library = _library({
      'children': [
        {'text': _value(operation: 'intl.unknown')}
      ]
    });
    expect(() => surfaceFeatureClientFloor(library), throwsFormatException);
    expect(
        () => surfaceScreenContractGaps(library,
            events: SurfaceScreenEventSchema(events: const []),
            context: SurfaceScreenHostDataSchema(const {})),
        throwsFormatException);
  });

  test('enum-tagged select rejects incompatible scalar choice types', () {
    for (final (type, value) in <(ValueType, Object?)>[
      (ValueType.integer, 1),
      (ValueType.real, 1.5),
      (ValueType.number, 1.5),
      (ValueType.boolean, true),
      (const ValueType('String', nullable: true), 'active'),
    ]) {
      final program = ValueProgram(nodes: [
        ValueNode('literal', type, value: value),
        const ValueNode('literal', ValueType.string, value: 'fallback'),
        const ValueNode('intl.select', ValueType.string, inputs: [
          0,
          1
        ], value: {
          'choiceEnum': 'package:fixture/status.dart#Status',
          'keys': ['other'],
          'arguments': <String>[],
        }),
      ], root: 2);
      final invalidSelect = throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', 'Invalid intl.select operation'));
      expect(
          () => ValueProgram.decode(program.encode(),
              operations: kIntlValueOperations),
          invalidSelect,
          reason: type.kind);
      expect(
          () => surfaceFeatureClientFloor(_library({
                'version': 1,
                'program': program.encode(),
                'captures': <String, Object?>{},
              })),
          invalidSelect,
          reason: type.kind);
    }
  });

  test('fit traverses the same validated native value vocabulary', () {
    final gaps = surfaceScreenContractGaps(_library({'text': _value()}),
        events: SurfaceScreenEventSchema(events: const []),
        context: SurfaceScreenHostDataSchema(const {}));
    expect(gaps, isEmpty);
  });
}

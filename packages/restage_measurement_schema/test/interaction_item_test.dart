import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

MeasurementOrderedCaptureRouteV1 _route({
  List<MeasurementOccurrenceChannelV1> channels = const [
    MeasurementOccurrenceChannelV1.presentation,
    MeasurementOccurrenceChannelV1.interaction,
  ],
  bool interactionItemsV1 = true,
}) =>
    MeasurementOrderedCaptureRouteV1(
      occurrenceId: CanonicalDigest('a' * 64),
      lineageId: PointLineageId('lineage-a'),
      channels: channels,
      interactionItemsV1: interactionItemsV1,
    );

void main() {
  _completesSurfaceTests();
  group('interaction item values', () {
    test('accept the bounded charset up to 64 characters', () {
      expect(measurementInteractionItemIsValidV1('plan.annual:v2_x-1'), isTrue);
      expect(measurementInteractionItemIsValidV1('a' * 64), isTrue);
      expect(measurementInteractionItemIsValidV1('a' * 65), isFalse);
      expect(measurementInteractionItemIsValidV1(''), isFalse);
      expect(measurementInteractionItemIsValidV1('with space'), isFalse);
      expect(measurementInteractionItemIsValidV1('ümlaut'), isFalse);
      expect(measurementInteractionItemIsValidV1('a/b'), isFalse);
    });

    test('round-trip on an interaction occurrence', () {
      final occurrence = MeasurementTimedOccurrenceV1(
        ordinal: 2,
        channel: MeasurementOccurrenceChannelV1.interaction,
        elapsedMicros: 10,
        itemValueV1: 'plan.annual',
      );
      final json = occurrence.toJson();
      expect(json['itemValueV1'], 'plan.annual');
      final decoded = MeasurementTimedOccurrenceV1.fromJson(json);
      expect(decoded.itemValueV1, 'plan.annual');
      expect(decoded.toJson(), json);
    });

    test('an occurrence without an item keeps its existing shape', () {
      final occurrence = MeasurementTimedOccurrenceV1(
        ordinal: 1,
        channel: MeasurementOccurrenceChannelV1.interaction,
        elapsedMicros: 0,
      );
      expect(occurrence.toJson().containsKey('itemValueV1'), isFalse);
      expect(
          MeasurementTimedOccurrenceV1.fromJson(occurrence.toJson())
              .itemValueV1,
          isNull);
    });

    test('the strict reader rejects an oversize or out-of-charset item', () {
      Map<String, Object?> json(Object? item) => {
            'ordinal': 1,
            'channel': 'interaction',
            'elapsedMicros': 0,
            'itemValueV1': item,
          };
      expect(() => MeasurementTimedOccurrenceV1.fromJson(json('a' * 65)),
          throwsA(anything));
      expect(() => MeasurementTimedOccurrenceV1.fromJson(json('two words')),
          throwsA(anything));
      expect(() => MeasurementTimedOccurrenceV1.fromJson(json(7)),
          throwsA(anything));
    });

    test('an item rides only a plain interaction occurrence', () {
      expect(
          () => MeasurementTimedOccurrenceV1(
                ordinal: 1,
                channel: MeasurementOccurrenceChannelV1.presentation,
                elapsedMicros: 0,
                itemValueV1: 'plan.annual',
              ),
          throwsArgumentError);
      expect(
          () => MeasurementTimedOccurrenceV1(
                ordinal: 1,
                channel: MeasurementOccurrenceChannelV1.interaction,
                elapsedMicros: 0,
                itemValueV1: 'plan.annual',
                answerValueV1: MeasurementCategoryAnswerV1('cost'),
              ),
          throwsArgumentError);
    });
  });

  group('routes whose interactions carry items', () {
    test('round-trip the declaration', () {
      final route = _route();
      final json = route.toJson();
      expect(json['interactionItemsV1'], isTrue);
      final decoded = MeasurementOrderedCaptureRouteV1.fromJson(json);
      expect(decoded.interactionItemsV1, isTrue);
      expect(decoded.toJson(), json);
      expect(_route(interactionItemsV1: false).toJson(),
          isNot(contains('interactionItemsV1')));
    });

    test('require the interaction channel', () {
      expect(
          () => _route(
              channels: const [MeasurementOccurrenceChannelV1.presentation]),
          throwsArgumentError);
    });

    test('never carry a declared answer or a lifecycle callback', () {
      expect(
          () => MeasurementOrderedCaptureRouteV1(
                occurrenceId: CanonicalDigest('a' * 64),
                lineageId: PointLineageId('lineage-a'),
                channels: const [
                  MeasurementOccurrenceChannelV1.presentation,
                  MeasurementOccurrenceChannelV1.interaction,
                ],
                interactionItemsV1: true,
                declaredAnswerV1: MeasurementDeclaredAnswerV1.category(
                    questionId: 'reason',
                    outcomeKey: 'survey.reason',
                    propertyName: 'reason',
                    categoryLabels: {'cost': 'Too expensive'}),
                answerCarrier: 'carrier',
              ),
          throwsArgumentError);
      expect(
          () => MeasurementOrderedCaptureRouteV1(
                occurrenceId: CanonicalDigest('a' * 64),
                lineageId: PointLineageId('lineage-a'),
                channels: const [
                  MeasurementOccurrenceChannelV1.presentation,
                  MeasurementOccurrenceChannelV1.interaction,
                  MeasurementOccurrenceChannelV1.completion,
                ],
                interactionItemsV1: true,
                lifecycle: MeasurementLifecycleCaptureRouteV1(
                    carrier: 'carrier',
                    channel: MeasurementOccurrenceChannelV1.completion),
              ),
          throwsArgumentError);
    });

    test('the compiler declaration carries the same flag', () {
      final declaration = MeasurementOrderedCaptureDeclarationV1(
        channels: const [
          MeasurementOccurrenceChannelV1.presentation,
          MeasurementOccurrenceChannelV1.interaction,
        ],
        interactionItemsV1: true,
      );
      final json = declaration.toJson();
      expect(json['interactionItemsV1'], isTrue);
      expect(
          MeasurementOrderedCaptureDeclarationV1.fromJson(json)
              .interactionItemsV1,
          isTrue);
      expect(
          () => MeasurementOrderedCaptureDeclarationV1(
                channels: const [MeasurementOccurrenceChannelV1.presentation],
                interactionItemsV1: true,
              ),
          throwsArgumentError);
    });
  });
}

void _completesSurfaceTests() {
  group('routes whose taps complete the surface', () {
    MeasurementOrderedCaptureRouteV1 route({
      List<MeasurementOccurrenceChannelV1> channels = const [
        MeasurementOccurrenceChannelV1.presentation,
        MeasurementOccurrenceChannelV1.interaction,
      ],
    }) =>
        MeasurementOrderedCaptureRouteV1(
          occurrenceId: CanonicalDigest('b' * 64),
          lineageId: PointLineageId('lineage-b'),
          channels: channels,
          completesSurfaceV1: true,
        );

    test('round-trip the flag, written only when set', () {
      final json = route().toJson();
      expect(json['completesSurfaceV1'], isTrue);
      final decoded = MeasurementOrderedCaptureRouteV1.fromJson(json);
      expect(decoded.completesSurfaceV1, isTrue);
      expect(decoded.toJson(), json);
      expect(_route(interactionItemsV1: false).toJson(),
          isNot(contains('completesSurfaceV1')));
      expect(
          () => MeasurementOrderedCaptureRouteV1.fromJson(
              {...json, 'completesSurfaceV1': false}),
          throwsA(isA<CanonicalFormatException>()));
    });

    test('require the interaction channel', () {
      expect(
          () => route(
              channels: const [MeasurementOccurrenceChannelV1.presentation]),
          throwsArgumentError);
    });

    test('the compiler declaration carries the same flag', () {
      final declaration = MeasurementOrderedCaptureDeclarationV1(
        channels: const [
          MeasurementOccurrenceChannelV1.presentation,
          MeasurementOccurrenceChannelV1.interaction,
        ],
        completesSurfaceV1: true,
      );
      expect(
          MeasurementOrderedCaptureDeclarationV1.fromJson(declaration.toJson())
              .completesSurfaceV1,
          isTrue);
      expect(
          () => MeasurementOrderedCaptureDeclarationV1(
                channels: const [
                  MeasurementOccurrenceChannelV1.presentation,
                  MeasurementOccurrenceChannelV1.completion,
                ],
                lifecycleChannel: MeasurementOccurrenceChannelV1.completion,
                completesSurfaceV1: true,
              ),
          throwsArgumentError);
    });
  });
}

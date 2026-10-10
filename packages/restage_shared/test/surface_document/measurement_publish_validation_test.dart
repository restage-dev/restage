import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

BlobSurfacePayload _blob(String item, {int minClient = 1}) =>
    BlobSurfacePayload(
      minClient: minClient,
      blob: Uint8List.fromList(
        encodeLibraryBlob(
          parseLibraryFile('''
widget Root = Column(children: [
  ...for plan in data.context.plans:
    TextButton(
      onPressed: event "choose" { __restage_measurement_item_v1: $item },
      child: Text(text: "Choose"),
    ),
]);
'''),
        ),
      ),
    );

MeasurementOrderedCaptureDeclarationV1 _tap({
  bool items = false,
  bool completes = false,
}) =>
    MeasurementOrderedCaptureDeclarationV1(
      channels: const [
        MeasurementOccurrenceChannelV1.presentation,
        MeasurementOccurrenceChannelV1.interaction,
      ],
      interactionItemsV1: items,
      completesSurfaceV1: completes,
    );

void main() {
  group('tap item bindings', () {
    test('a literal item or the loop element index is accepted', () {
      expect(
        () => validatePayloadSectionsForPublish(_blob('"plan.annual"')),
        returnsNormally,
      );
      expect(
        () => validatePayloadSectionsForPublish(_blob('plan.__restage_index')),
        returnsNormally,
      );
    });

    test('an item bound to host context data is refused', () {
      for (final item in [
        'plan.tier',
        'data.context.tier',
        'args.item',
        'state.item',
        '1',
      ]) {
        expect(
          () => validatePayloadSectionsForPublish(_blob(item)),
          throwsFormatException,
          reason: item,
        );
      }
    });
  });

  BlobSurfacePayload library(String source, {int minClient = 1}) =>
      BlobSurfacePayload(
        minClient: minClient,
        blob: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source))),
      );

  test('an item bound to host context inside a builder body is refused', () {
    expect(
      () => validatePayloadSectionsForPublish(
        library('''
widget Root = Sheet(builder: (scope) => TextButton(
  onPressed: event "choose" { __restage_measurement_item_v1: data.context.plan },
  child: Text(text: "Choose"),
));
'''),
      ),
      throwsFormatException,
    );
  });

  group('screen-local value writes', () {
    const source = '''
widget Root = Switch(onChanged: event "restage.local.set" { key: "on" });
''';

    test('need the feature floor', () {
      expect(
        () => validatePayloadSectionsForPublish(library(source)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('screen-local values'),
          ),
        ),
      );
    });

    test('are accepted at the feature floor', () {
      expect(
        () => validatePayloadSectionsForPublish(
          library(source, minClient: kSurfaceFeatureClientFloor),
        ),
        returnsNormally,
      );
    });

    test('inside a builder body need the feature floor too', () {
      expect(
        () => validatePayloadSectionsForPublish(
          library('''
widget Root = Sheet(builder: (scope) => Switch(
  onChanged: event "restage.local.set" { key: "on" },
));
'''),
        ),
        throwsFormatException,
      );
    });
  });

  test('only the route and item measurement keys are admitted', () {
    BlobSurfacePayload payload(String key) => BlobSurfacePayload(
          minClient: 1,
          blob: Uint8List.fromList(
            encodeLibraryBlob(
              parseLibraryFile(
                'widget Root = TextButton(onPressed: event "go" '
                '{ $key: "x" }, child: Text(text: "Go"));',
              ),
            ),
          ),
        );
    expect(
      () => validatePayloadSectionsForPublish(
        payload('__restage_measurement_route_v1'),
      ),
      returnsNormally,
    );
    expect(
      () => validatePayloadSectionsForPublish(
        payload('__restage_measurement_answer_v1'),
      ),
      throwsFormatException,
    );
  });

  group('tap route floor', () {
    test('routes carrying items or completion need the feature floor', () {
      for (final route in [_tap(items: true), _tap(completes: true)]) {
        expect(
          () => validateMeasurementRouteFloorForPublish(
            payload: _blob('"a"', minClient: kSurfaceFeatureClientFloor - 1),
            routes: [route],
          ),
          throwsFormatException,
        );
        expect(
          () => validateMeasurementRouteFloorForPublish(
            payload: _blob('"a"', minClient: kSurfaceFeatureClientFloor),
            routes: [route],
          ),
          returnsNormally,
        );
      }
    });

    test('plain routes keep any floor', () {
      expect(
        () => validateMeasurementRouteFloorForPublish(
          payload: _blob('"a"'),
          routes: [_tap(), null],
        ),
        returnsNormally,
      );
    });
  });
}

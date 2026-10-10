import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('samples every scalar kind', () {
    final schema = SurfaceScreenHostDataSchema(const {
      'name': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.string,
      ),
      'streakDays': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.integer,
      ),
      'ratio': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.doubleValue,
      ),
      'amount': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.number,
      ),
      'is_pro': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.boolean,
      ),
      'first_name': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.string,
      ),
    });

    expect(sampleHostContext(schema), {
      'amount': 3,
      'first_name': 'First name',
      'is_pro': true,
      'name': 'Name',
      'ratio': 1.5,
      'streakDays': 3,
    });
  });

  test('samples nullable, list, map and object shapes recursively', () {
    final inputs = <String, SurfaceScreenHostDataShape>{
      'nickname': const SurfaceScreenHostDataNullableShapeV1(
        SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
      ),
      'tags': const SurfaceScreenHostDataListShapeV1(
        SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
      ),
      'scores': const SurfaceScreenHostDataMapShapeV1(
        SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.integer,
        ),
      ),
      'user': SurfaceScreenHostDataObjectShapeV1({
        'displayName': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
        'friends': SurfaceScreenHostDataListShapeV1(
          SurfaceScreenHostDataObjectShapeV1(const {
            'id': SurfaceScreenHostDataScalarShapeV1(
              SurfaceScreenHostDataScalarKind.integer,
            ),
          }),
        ),
      }),
    };

    expect(sampleHostContext(SurfaceScreenHostDataSchema(inputs)), {
      'nickname': 'Nickname',
      'scores': {'scores': 3},
      'tags': ['Tags', 'Tags'],
      'user': {
        'displayName': 'Display name',
        'friends': [
          {'id': 3},
          {'id': 3},
        ],
      },
    });
  });

  test('is empty for a schema without inputs', () {
    expect(
      sampleHostContext(const SurfaceScreenHostDataSchema.empty()),
      isEmpty,
    );
  });
}

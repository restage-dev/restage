import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

void main() {
  final events = SurfaceScreenEventSchema(
    events: [
      SurfaceScreenEvent(
        id: 'next',
        arguments: const SurfaceScreenEventNoArguments(),
      ),
      SurfaceScreenEvent(
        id: 'choose',
        arguments: const SurfaceScreenEventValueArguments(
          SurfaceScreenEventScalarShapeV1(SurfaceScreenEventScalarKind.integer),
        ),
      ),
      SurfaceScreenEvent(
        id: 'select',
        arguments: SurfaceScreenEventObjectArguments(
          const SurfaceScreenEventMapShapeV1(
            SurfaceScreenEventScalarShapeV1(
              SurfaceScreenEventScalarKind.string,
            ),
          ),
        ),
      ),
    ],
  );
  final context = SurfaceScreenHostDataSchema({
    'plan': SurfaceScreenHostDataObjectShapeV1(const {
      'name': SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.string,
      ),
    }),
  });

  List<String> gaps(String body, {Map<String, Object> local = const {}}) =>
      surfaceScreenContractGaps(
        parseLibraryFile('import core;\n$body'),
        events: events,
        context: context,
        localValues: local,
      ).map((gap) => '$gap').toList();

  test('a screen inside its contract has no gaps', () {
    expect(
      gaps(
        '''
widget Root = Column(children: [
  Text(text: data.context.plan.name),
  Button(onPressed: event "next" {}),
  Button(onPressed: event "choose" { value: 2 }),
  Button(onPressed: event "select" { id: data.context.plan.name }),
  Button(onPressed: event "choose" { value: data.local.count }),
  Button(onPressed: event "restage.local.set" { key: "count", value: 3 }),
]);
''',
        local: {'count': 1},
      ),
      isEmpty,
    );
  });

  test('an undeclared event is a gap, wherever it is emitted', () {
    expect(
      gaps('''
widget Root = Badge(onTap: event "upgrade" {});
widget Parked = Column(children: [
  Button(onPressed: event "dismiss" {}),
  Button(onPressed: event "upgrade" {}),
  Button(onPressed: event "purchase" {}),
]);
'''),
      ['event "dismiss"', 'event "purchase"', 'event "upgrade"'],
    );
  });

  test('an argument outside its event declaration is a gap', () {
    expect(
      gaps('''
widget Root = Column(children: [
  Button(onPressed: event "next" { plan: "pro" }),
  Button(onPressed: event "choose" { value: "two" }),
  Button(onPressed: event "choose" { value: 2, extra: 1 }),
  Button(onPressed: event "select" { id: 4 }),
]);
'''),
      [
        'argument "extra" of event "choose"',
        'argument "value" of event "choose"',
        'argument "plan" of event "next"',
        'argument "id" of event "select"',
      ],
    );
  });

  test('a declared value event emitted without its value is an argument gap',
      () {
    expect(
      gaps('widget Root = Button(onPressed: event "choose" {});'),
      ['argument "value" of event "choose"'],
    );
  });

  test('a context read outside the schema is a gap, in any position', () {
    expect(
      gaps('''
widget Root { open: false } = Column(children: [
  Button(onPressed: set state.open = data.context.trial),
  ...for item in data.context.items:
    Text(text: switch data.context.plan.tier { true: "a", default: "b" }),
  Text(text: data.context.plan.name),
]);
'''),
      [
        'context read "items"',
        'context read "plan.tier"',
        'context read "trial"',
      ],
    );
  });

  test('gaps are sorted by kind and listed once', () {
    expect(
      gaps('''
widget Root = Column(children: [
  Text(text: data.context.coupon),
  Button(onPressed: event "select" { id: data.context.coupon }),
  Button(onPressed: event "upgrade" {}),
  Button(onPressed: event "upgrade" {}),
]);
'''),
      [
        'event "upgrade"',
        'argument "id" of event "select"',
        'context read "coupon"',
      ],
    );
  });
}

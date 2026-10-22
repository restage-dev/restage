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
        id: 'toggle',
        arguments: SurfaceScreenEventObjectArguments(
          const SurfaceScreenEventMapShapeV1(
            SurfaceScreenEventScalarShapeV1(
              SurfaceScreenEventScalarKind.jsonValue,
            ),
          ),
        ),
      ),
      SurfaceScreenEvent(
        id: 'note',
        arguments: SurfaceScreenEventObjectArguments(
          const SurfaceScreenEventMapShapeV1(
            SurfaceScreenEventNullableShapeV1(
              SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.string,
              ),
            ),
          ),
        ),
      ),
      SurfaceScreenEvent(
        id: 'pick',
        arguments: const SurfaceScreenEventValueArguments(
          SurfaceScreenEventListShapeV1(
            SurfaceScreenEventScalarShapeV1(
              SurfaceScreenEventScalarKind.integer,
            ),
          ),
        ),
      ),
      SurfaceScreenEvent(
        id: 'rate',
        arguments: const SurfaceScreenEventValueArguments(
          SurfaceScreenEventScalarShapeV1(
            SurfaceScreenEventScalarKind.doubleValue,
          ),
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
  const string = SurfaceScreenHostDataScalarShapeV1(
    SurfaceScreenHostDataScalarKind.string,
  );
  final context = SurfaceScreenHostDataSchema({
    'plan': SurfaceScreenHostDataObjectShapeV1(const {'name': string}),
    'account': SurfaceScreenHostDataNullableShapeV1(
      SurfaceScreenHostDataObjectShapeV1(const {'name': string}),
    ),
    'nickname': const SurfaceScreenHostDataNullableShapeV1(string),
    'labels': const SurfaceScreenHostDataMapShapeV1(string),
    'names': const SurfaceScreenHostDataListShapeV1(string),
    'scores': const SurfaceScreenHostDataListShapeV1(
      SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.integer,
      ),
    ),
    'ratio': const SurfaceScreenHostDataScalarShapeV1(
      SurfaceScreenHostDataScalarKind.number,
    ),
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

  test('a context value fits a wider declared argument type', () {
    expect(
      gaps('''
widget Root = Column(children: [
  Button(onPressed: event "toggle" { plan: data.context.plan.name, day: 0 }),
  Button(onPressed: event "toggle" { plan: data.context.plan }),
]);
'''),
      isEmpty,
    );
  });

  test('a context value of another type is an argument gap', () {
    expect(
      gaps('''
widget Root = Column(children: [
  Button(onPressed: event "choose" { value: data.context.plan.name }),
  Button(onPressed: event "pick" { value: data.context.names }),
  Button(onPressed: event "rate" { value: data.context.ratio }),
]);
'''),
      [
        'argument "value" of event "choose"',
        'argument "value" of event "pick"',
        'argument "value" of event "rate"',
      ],
    );
  });

  test('a list context value fits a list argument of its item type', () {
    expect(
      gaps('''
widget Root = Button(onPressed: event "pick" { value: data.context.scores });
'''),
      isEmpty,
    );
  });

  test('a loop variable reads as an item of the list it loops over', () {
    expect(
      gaps('''
widget Root = Column(children: [
  ...for name in data.context.names:
    Button(onPressed: event "select" { id: name }),
]);
'''),
      isEmpty,
    );
    expect(
      gaps('''
widget Root = Column(children: [
  ...for name in data.context.names:
    Button(onPressed: event "choose" { value: name }),
]);
'''),
      ['argument "value" of event "choose"'],
    );
  });

  test('a context value that can be absent fits only a nullable argument', () {
    expect(
      gaps('''
widget Root = Column(children: [
  Button(onPressed: event "note" { a: data.context.account.name }),
  Button(onPressed: event "note" { b: data.context.labels.title }),
  Button(onPressed: event "note" { c: data.context.nickname }),
  Button(onPressed: event "toggle" { d: data.context.account.name }),
  Button(onPressed: event "note" { e: data.context.names.0 }),
]);
'''),
      isEmpty,
    );
    expect(
      gaps('''
widget Root = Column(children: [
  Button(onPressed: event "select" { a: data.context.account.name }),
  Button(onPressed: event "select" { b: data.context.labels.title }),
  Button(onPressed: event "select" { c: data.context.nickname }),
  Button(onPressed: event "select" { e: data.context.names.0 }),
]);
'''),
      [
        'argument "a" of event "select"',
        'argument "b" of event "select"',
        'argument "c" of event "select"',
        'argument "e" of event "select"',
      ],
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

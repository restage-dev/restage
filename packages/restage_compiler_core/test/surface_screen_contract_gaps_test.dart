import 'dart:async';

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
    'plans': SurfaceScreenHostDataListShapeV1(
      SurfaceScreenHostDataObjectShapeV1(const {'name': string}),
    ),
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

  test('a widget argument an event reads is what each placement passes', () {
    expect(
      gaps('''
widget Chip = Button(onPressed: event "choose" { value: args.count });
widget Item = Chip(count: args.score);
widget Root = Column(children: [
  Chip(count: 2),
  ...for score in data.context.scores:
    Item(score: score),
]);
'''),
      isEmpty,
    );
    expect(
      gaps('''
widget Chip = Button(onPressed: event "choose" { value: args.count });
widget Root = Column(children: [
  Chip(count: 2),
  Chip(count: data.context.plan.name),
]);
'''),
      ['argument "value" of event "choose"'],
    );
  });

  // A declaration's loop is its own: a placement's loop never rebinds it.
  String chip(String root) => '''
widget Chip = Column(children: [
  ...for item in args.items:
    Button(onPressed: event "select" { id: item, extra: args.label }),
]);
$root''';

  test('a loop over a widget argument of the wrong type is a gap', () {
    expect(
      gaps(
        chip('''
widget Root = Column(children: [
  ...for name in data.context.names:
    Chip(items: data.context.scores, label: name),
]);
'''),
      ),
      ['argument "id" of event "select"'],
    );
  });

  test('a loop over a widget argument fits whatever loop places it', () {
    expect(
      gaps(
        chip('''
widget Root = Column(children: [
  ...for score in data.context.scores:
    Chip(items: data.context.names, label: "x"),
]);
'''),
      ),
      isEmpty,
    );
  });

  test('a list built from a declaration loop reads its own items', () {
    String chip(String loop, String items) => '''
widget Chip = Column(children: [
  ...for c in args.items:
    Button(onPressed: event "pick" { value: [c, args.n] }),
]);
widget Root = Column(children: [
  ...for s in $loop: Chip(items: $items, n: 1),
]);
''';
    expect(
      gaps(chip('data.context.scores', 'data.context.names')),
      ['argument "value" of event "pick"'],
    );
    expect(gaps(chip('data.context.names', 'data.context.scores')), isEmpty);
  });

  // Each declaration's arguments are checked once, not once per path to it.
  test('a chain of declarations that forward an argument checks fast', () {
    final body = StringBuffer(
      'widget Hop0 = Button(onPressed: event "choose" { value: args.v });\n',
    );
    for (var level = 1; level <= 30; level++) {
      body.writeln(
        'widget Hop$level = Row(children: '
        '[Hop${level - 1}(v: args.v), Hop${level - 1}(v: args.v)]);',
      );
    }
    body.writeln('widget Root = Hop30(v: 1);');
    expect(_withBudget(10000, () => gaps('$body')), isEmpty);
  });

  test('a loop item alone reads the list each placement passes', () {
    String chip(String items) => '''
widget Chip = Column(children: [
  ...for item in args.items: Button(onPressed: event "select" { id: item }),
]);
widget Root = Column(children: [
  ...for name in data.context.names: Chip(items: $items),
]);
''';
    expect(gaps(chip('data.context.names')), isEmpty);
    expect(
      gaps(chip('data.context.scores')),
      ['argument "id" of event "select"'],
    );
  });

  test('a switch over an argument a placement omits is checked', () {
    expect(
      gaps('''
widget Chip = Button(
  onPressed: event "choose" { value: switch args.count { 1: 1, default: 2 } },
);
widget Root = Column(children: [Chip()]);
'''),
      isEmpty,
    );
    expect(
      gaps('''
widget Chip = Button(
  onPressed: event "choose" {
    value: switch args.flag { true: args.count, default: 2 },
  },
);
widget Root = Column(children: [Chip(flag: true)]);
'''),
      ['argument "value" of event "choose"'],
    );
  });

  test('a path into a switch a placement passes reads each output', () {
    expect(
      gaps('''
widget Chip = Button(onPressed: event "select" { id: args.plan.name });
widget Root = Chip(
  plan: switch data.context.plan.name {
    "a": data.context.plan,
    default: { name: "fallback" },
  },
);
'''),
      isEmpty,
    );
  });

  test('a list of the wrong item type among fitting lists is a gap', () {
    expect(
      gaps('''
widget Chip = Button(onPressed: event "pick" { value: args.v });
widget Root = Column(children: [Chip(v: ["x,int:5"]), Chip(v: [1, "x"])]);
'''),
      ['argument "value" of event "pick"'],
    );
  });

  test('builder frame values of different types are each checked', () {
    const chip = ConstructorCall('Chip', {
      'v': WidgetBuilderArgReference('frame', ['values', 'v0']),
    });
    ConstructorCall host(ValueType type, Object literal) =>
        ConstructorCall('Host', {
          'builder': ConstructorCall(kBuilderContinuationWidgetName, {
            'version': 1,
            'program': BuilderProgram(
              values: ValueProgram(
                nodes: [ValueNode('literal', type, value: literal)],
                root: 0,
              ),
              result: const BuilderResult.body(0, values: {'v0': 0}),
              bodyCount: 1,
            ).encode(),
            'captures': <String, Object?>{},
            'bodies': [const WidgetBuilderDeclaration('frame', chip)],
          }),
        });
    final library = RemoteWidgetLibrary(const [], [
      const WidgetDeclaration(
        'Chip',
        null,
        ConstructorCall('Button', {
          'onTap': EventHandler('choose', {
            'value': ArgsReference(['v']),
          }),
        }),
      ),
      WidgetDeclaration(
        'Root',
        null,
        ConstructorCall('Column', {
          'children': [
            host(ValueType.integer, 7),
            host(ValueType.string, 'x'),
          ],
        }),
      ),
    ]);
    expect(
      surfaceScreenContractGaps(
        library,
        events: events,
        context: context,
      ).map((gap) => '$gap'),
      ['argument "value" of event "choose"'],
    );
  });

  // Two declarations that place each other read each other's arguments as
  // unbound, whichever is declared first.
  for (final order in ['D first', 'E first']) {
    test('a call cycle is a gap with $order', () {
      const d = '''
widget D = Column(children: [
  Button(onPressed: event "choose" { value: 1 }),
  E(items: args.list),
]);
''';
      const e = '''
widget E = Column(children: [
  ...for c in args.items:
    Button(onPressed: event "choose" { value: c }),
  D(list: args.items),
]);
''';
      const root = 'widget Root = D(list: data.context.scores);\n';
      expect(
        gaps(order == 'D first' ? '$d$e$root' : '$e$d$root'),
        ['argument "value" of event "choose"'],
      );
    });
  }

  test('an index read into a list with a loop reads any item type', () {
    expect(
      gaps('''
widget Chip = Button(onPressed: event "choose" { value: args.v.2 });
widget Root = Chip(v: ["a", ...for x in data.context.scores: x, 5]);
'''),
      ['argument "value" of event "choose"'],
    );
    expect(
      gaps('''
widget Chip = Button(onPressed: event "choose" { value: args.v.1 });
widget Root = Chip(v: [1, ...for x in data.context.scores: x, 5]);
'''),
      isEmpty,
    );
  });

  // RFW reads past the end of a list as missing.
  test('an index a list may not reach is a gap', () {
    String chip(String read, String list) => '''
widget Chip = Button(onPressed: event "choose" { value: args.v.$read });
widget Root = Chip(v: $list);
''';
    expect(gaps(chip('5', '[1, 2]')), ['argument "value" of event "choose"']);
    expect(gaps(chip('0', '[]')), ['argument "value" of event "choose"']);
    expect(gaps(chip('1', '[1, 2]')), isEmpty);
  });

  // Shared types are keyed and checked once, as a value or as JSON.
  for (final (name, kind) in [
    ('a value', SurfaceScreenEventScalarKind.integer),
    ('JSON', SurfaceScreenEventScalarKind.jsonValue),
  ]) {
    test('a chain of maps sharing one argument checks fast as $name', () {
      final body = StringBuffer(
        'widget Hop0 = Button(onPressed: event "choose" { value: args.v });\n',
      );
      for (var level = 1; level <= 30; level++) {
        body.writeln(
          'widget Hop$level = Hop${level - 1}(v: { a: args.v, b: args.v });',
        );
      }
      body.writeln('widget Root = Hop30(v: 1);');
      final found = _withBudget(
        10000,
        () => surfaceScreenContractGaps(
          parseLibraryFile('import core;\n$body'),
          events: SurfaceScreenEventSchema(
            events: [
              SurfaceScreenEvent(
                id: 'choose',
                arguments: SurfaceScreenEventValueArguments(
                  SurfaceScreenEventScalarShapeV1(kind),
                ),
              ),
            ],
          ),
          context: SurfaceScreenHostDataSchema(const {}),
        ).map((gap) => '$gap').toList(),
      );
      expect(
        found,
        kind == SurfaceScreenEventScalarKind.jsonValue
            ? isEmpty
            : ['argument "value" of event "choose"'],
      );
    });
  }

  test('a loop over a long literal list types it once', () {
    final list = [
      for (var item = 0; item < 2000; item++)
        '{ code: "c$item", name: "n$item" }',
    ].join(', ');
    final body = StringBuffer('widget Root = Column(children: [\n')
      ..writeln('  ...for item in [$list]:')
      ..writeln('    Column(children: [');
    for (var button = 0; button < 100; button++) {
      body.writeln(
        '      Button(onPressed: event "select" { id: item.name }),',
      );
    }
    body.writeln('    ]),\n]);');
    expect(_withBudget(100000, () => gaps('$body')), isEmpty);
  });

  test('one large map read many times checks fast', () {
    final entries = [
      for (var key = 0; key < 20000; key++) 'k$key: $key',
    ];
    final map = '{ ${entries.join(', ')} }';
    String chip(String read) => 'widget Chip = Button(onPressed: event "pick" '
        '{ value: [${List.filled(2000, read).join(', ')}] });\n'
        'widget Root = Chip(m: $map);\n';
    final whole = parseLibraryFile('import core;\n${chip('args.m')}');
    final path = parseLibraryFile('import core;\n${chip('args.m.k1')}');
    List<String> gapsIn(RemoteWidgetLibrary library) =>
        surfaceScreenContractGaps(library, events: events, context: context)
            .map((gap) => '$gap')
            .toList();
    expect(
      _withBudget(500000, () => gapsIn(whole)),
      ['argument "value" of event "pick"'],
    );
    expect(_withBudget(500000, () => gapsIn(path)), isEmpty);
  });

  test('a JSON value holding data, a mixed list or an argument fits', () {
    expect(
      gaps('''
widget Chip = Button(onPressed: event "toggle" { x: { a: [1, "s", args.v] } });
widget Root = Column(children: [
  Button(onPressed: event "toggle" { x: { a: data.context.plan.name } }),
  Chip(v: 2),
  Chip(v: "s"),
]);
'''),
      isEmpty,
    );
  });

  // Declarations resolve in order, not by recursion, so depth costs no stack.
  for (final reversed in [false, true]) {
    test('a 50,000-declaration chain checks${reversed ? ', reversed' : ''}',
        () {
      const depth = 50000;
      final chain = [
        for (var level = 1; level <= depth; level++)
          WidgetDeclaration(
            'Hop$level',
            null,
            ConstructorCall('Hop${level - 1}', {
              'v': const ArgsReference(['v']),
            }),
          ),
      ];
      final library = RemoteWidgetLibrary(const [], [
        const WidgetDeclaration(
          'Hop0',
          null,
          ConstructorCall('Button', {
            'onTap': EventHandler('choose', {
              'value': ArgsReference(['v'])
            }),
          }),
        ),
        ...reversed ? chain.reversed : chain,
        const WidgetDeclaration(
          'Root',
          null,
          ConstructorCall('Hop$depth', {
            'v': 'one',
          }),
        ),
      ]);
      expect(
        _withBudget(
          1000000,
          () => surfaceScreenContractGaps(
            library,
            events: events,
            context: context,
          ).map((gap) => '$gap').toList(),
        ),
        ['argument "value" of event "choose"'],
      );
    });
  }

  // The SDK refuses a map key that is not Unicode text.
  test('a map key with a lone surrogate is a gap', () {
    const key = '\uD800';
    List<String> gapsIn(
      List<WidgetDeclaration> widgets, {
      SurfaceScreenEventSchema? schema,
    }) =>
        surfaceScreenContractGaps(
          RemoteWidgetLibrary(const [], widgets),
          events: schema ?? events,
          context: context,
        ).map((gap) => '$gap').toList();
    ConstructorCall button(String event, Map<String, Object?> arguments) =>
        ConstructorCall('Button', {'onTap': EventHandler(event, arguments)});

    expect(
      gapsIn([
        WidgetDeclaration(
          'Root',
          null,
          button('toggle', {
            'x': {key: 1},
          }),
        ),
      ]),
      ['argument "x" of event "toggle"'],
    );
    expect(
      gapsIn([
        WidgetDeclaration(
          'Chip',
          null,
          button('toggle', {
            'x': const ArgsReference(['v']),
          }),
        ),
        const WidgetDeclaration(
          'Root',
          null,
          ConstructorCall('Chip', {
            'v': {key: 1},
          }),
        ),
      ]),
      ['argument "x" of event "toggle"'],
    );
    expect(
      gapsIn([
        WidgetDeclaration(
          'Root',
          null,
          button('select', {key: 'a'}),
        ),
      ]),
      ['argument "$key" of event "select"'],
    );
    expect(
      gapsIn(
        [
          WidgetDeclaration(
            'Root',
            null,
            button('labels', {
              'value': {key: 'a'},
            }),
          ),
        ],
        schema: SurfaceScreenEventSchema(
          events: [
            SurfaceScreenEvent(
              id: 'labels',
              arguments: const SurfaceScreenEventValueArguments(
                SurfaceScreenEventMapShapeV1(
                  SurfaceScreenEventScalarShapeV1(
                    SurfaceScreenEventScalarKind.string,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ['argument "value" of event "labels"'],
    );
    expect(
      gapsIn([
        WidgetDeclaration(
          'Root',
          null,
          button('toggle', {
            'x': {'ok': 1},
          }),
        ),
      ]),
      isEmpty,
    );
  });

  // Nesting past the check's limit is refused, not recursed into.
  test('a value nested too deep is refused without a crash', () {
    List<String> nested(int depth) {
      Object value = 1;
      for (var level = 0; level < depth; level++) {
        value = [value];
      }
      final library = RemoteWidgetLibrary(const [], [
        WidgetDeclaration(
          'Root',
          null,
          ConstructorCall('Button', {
            'onTap': EventHandler('toggle', {'x': value}),
          }),
        ),
      ]);
      return surfaceScreenContractGaps(
        library,
        events: events,
        context: context,
      ).map((gap) => '$gap').toList();
    }

    expect(nested(100), isEmpty);
    for (final depth in [1000, 5000]) {
      expect(
        () => nested(depth),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'The surface is too complex to check its events.',
          ),
        ),
        reason: '$depth',
      );
    }
  });

  test('a switch with no default over an omitted argument is a gap', () {
    expect(
      gaps('''
widget Chip = Button(
  onPressed: event "choose" { value: switch args.count { 1: 1, 2: 2 } },
);
widget Root = Column(children: [Chip()]);
'''),
      ['argument "value" of event "choose"'],
    );
  });

  test('a path through nested lists checks fast', () {
    const depth = 30;
    final zeros = List.filled(depth, '0').join('.');
    final body = StringBuffer(
      'widget Hop0 = Button(\n'
      '  onPressed: event "choose" { value: args.v.$zeros },\n'
      ');\n',
    );
    for (var level = 1; level <= depth; level++) {
      body.writeln(
        'widget Hop$level = Row(children: '
        '[Hop${level - 1}(v: [args.v, 1]), Hop${level - 1}(v: [args.v, 2])]);',
      );
    }
    body.writeln('widget Root = Hop$depth(v: 5);');
    _withBudget(50000, () => gaps('$body'));
  });

  test('a list built by a loop passes the type of its items', () {
    expect(
      gaps('''
widget Picker = Column(children: [
  ...for option in args.options:
    Button(onPressed: event "select" { id: option }),
]);
widget Root = Picker(options: [...for plan in data.context.plans: plan.name]);
'''),
      isEmpty,
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

// [check] run with a step budget, so work beyond it fails as too complex.
T _withBudget<T>(int steps, T Function() check) => runZoned(
      check,
      zoneValues: {#restageSurfaceFitStepBudget: steps},
    );

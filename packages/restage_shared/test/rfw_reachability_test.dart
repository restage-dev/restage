import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

ConstructorCall _call(
  String name, [
  Map<String, Object?> arguments = const <String, Object?>{},
]) {
  return ConstructorCall(name, arguments);
}

WidgetDeclaration _widget(
  String name, {
  Map<String, Object?> initialState = const <String, Object?>{},
  ConstructorCall? root,
}) {
  return WidgetDeclaration(name, initialState, root ?? _call('Container'));
}

RemoteWidgetLibrary _library(
  List<WidgetDeclaration> widgets, {
  List<Import> imports = const <Import>[],
}) {
  return RemoteWidgetLibrary(imports, widgets);
}

List<String> _widgetNames(RemoteWidgetLibrary library) {
  return library.widgets.map((widget) => widget.name).toList();
}

void main() {
  test('nothing to strip returns the input instance', () {
    final library = _library(<WidgetDeclaration>[
      _widget('main', root: _call('Card')),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(identical(result, library), isTrue);
  });

  test('an unreferenced declaration is dropped', () {
    final library = _library(<WidgetDeclaration>[
      _widget('main'),
      _widget('parked'),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['main']);
  });

  test('a declaration referenced by the entry is kept', () {
    final library = _library(<WidgetDeclaration>[
      _widget('main', root: _call('Card')),
      _widget('Card'),
      _widget('parked'),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['main', 'Card']);
  });

  test('transitive references are kept', () {
    final library = _library(<WidgetDeclaration>[
      _widget('main', root: _call('Section')),
      _widget('Section', root: _call('Label')),
      _widget('Label'),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['main', 'Section', 'Label']);
  });

  test('a reference cycle terminates and keeps each declaration', () {
    final library = _library(<WidgetDeclaration>[
      _widget('main', root: _call('First')),
      _widget('First', root: _call('Second')),
      _widget('Second', root: _call('First')),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['main', 'First', 'Second']);
  });

  // This fixture verifies local retention.
  // Imports do not carry declaration lists.
  test(
      'a local declaration is retained when an import could supply the same '
      'name', () {
    final imports = <Import>[
      const Import(LibraryName(<String>['example', 'widgets'])),
    ];
    final library = _library(
      <WidgetDeclaration>[
        _widget('main', root: _call('Card')),
        _widget('Card'),
        _widget('parked'),
      ],
      imports: imports,
    );

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['main', 'Card']);
  });

  test('imports are preserved unchanged', () {
    final imports = <Import>[
      const Import(LibraryName(<String>['first', 'widgets'])),
      const Import(LibraryName(<String>['second', 'widgets'])),
    ];
    final library = _library(
      <WidgetDeclaration>[
        _widget('main'),
        _widget('parked'),
      ],
      imports: imports,
    );

    final result = retainReachableFrom(library, 'main');

    expect(result.imports, same(imports));
    expect(
      result.imports.map((import) => import.name.parts.join('.')),
      <String>['first.widgets', 'second.widgets'],
    );
  });

  test('declaration order is preserved among retained declarations', () {
    final library = _library(<WidgetDeclaration>[
      _widget('Second', root: _call('First')),
      _widget('parked'),
      _widget(
        'main',
        root: _call(
          'Host',
          <String, Object?>{
            'first': _call('First'),
            'second': _call('Second'),
          },
        ),
      ),
      _widget('First'),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['Second', 'main', 'First']);
  });

  test('an absent entry name strips nothing', () {
    final library = _library(<WidgetDeclaration>[
      _widget('main'),
      _widget('parked'),
    ]);

    final result = retainReachableFrom(library, 'missing');

    expect(identical(result, library), isTrue);
  });

  test('references nested inside other node types are found', () {
    final library = _library(<WidgetDeclaration>[
      _widget(
        'main',
        root: _call(
          'Host',
          <String, Object?>{
            'switch': Switch(
              'selected',
              <Object?, Object>{
                'selected': _call('FromSwitch'),
              },
            ),
            'loop': Loop(
              const <Object?>['item'],
              _call('FromLoop'),
            ),
            'builder': WidgetBuilderDeclaration(
              'scope',
              _call('FromBuilder'),
            ),
            'handler': EventHandler(
              'activate',
              <String, Object?>{
                'payload': _call('FromEvent'),
              },
            ),
            'list': <Object?>[
              _call('FromList'),
            ],
            'map': <String, Object?>{
              'value': _call('FromMap'),
            },
          },
        ),
      ),
      _widget('FromSwitch'),
      _widget('FromLoop'),
      _widget('FromBuilder'),
      _widget('FromEvent'),
      _widget('FromList'),
      _widget('FromMap'),
      _widget('parked'),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(
      _widgetNames(result),
      <String>[
        'main',
        'FromSwitch',
        'FromLoop',
        'FromBuilder',
        'FromEvent',
        'FromList',
        'FromMap',
      ],
    );
  });

  test("the entry's initialState is walked", () {
    final library = _library(<WidgetDeclaration>[
      _widget(
        'main',
        initialState: <String, Object?>{
          'content': _call('StateContent'),
        },
      ),
      _widget('StateContent'),
      _widget('parked'),
    ]);

    final result = retainReachableFrom(library, 'main');

    expect(_widgetNames(result), <String>['main', 'StateContent']);
  });

  // Intended test count in this group: 3.
  group('instances keep their definition', () {
    test('a declaration referenced by an instance in the entry is retained',
        () {
      final library = _library(<WidgetDeclaration>[
        _widget(
          'main',
          root: _call(
            'Column',
            <String, Object?>{
              'children': <Object?>[
                _call('Card'),
              ],
            },
          ),
        ),
        _widget('Card'),
      ]);

      final result = retainReachableFrom(library, 'main');

      expect(_widgetNames(result), <String>['main', 'Card']);
    });

    test('a declaration referenced only through a nested instance is retained',
        () {
      final library = _library(<WidgetDeclaration>[
        _widget('main', root: _call('Mid')),
        _widget('Mid', root: _call('Leaf')),
        _widget('Leaf'),
      ]);

      final result = retainReachableFrom(library, 'main');

      expect(_widgetNames(result), <String>['main', 'Mid', 'Leaf']);
    });

    test(
        'an unreferenced declaration is still stripped alongside a '
        'referenced one', () {
      final library = _library(<WidgetDeclaration>[
        _widget('main', root: _call('Referenced')),
        _widget('Referenced'),
        _widget('Unreferenced'),
      ]);

      final result = retainReachableFrom(library, 'main');

      expect(_widgetNames(result), <String>['main', 'Referenced']);
    });
  });

  test(
      "blob entry point returns the caller's bytes object when nothing "
      'strips', () {
    final blob = encodeLibraryBlob(
      _library(<WidgetDeclaration>[_widget('main', root: _call('Card'))]),
    );

    final result = retainReachableFromBlob(blob, 'main');

    // No-strip identity preserves original bytes; decode/re-encode would not.
    expect(identical(result, blob), isTrue);
  });

  test('blob entry point strips an unreachable declaration and re-encodes', () {
    final blob = encodeLibraryBlob(
      _library(<WidgetDeclaration>[
        _widget('main', root: _call('Card')),
        _widget('parked'),
      ]),
    );

    final result = retainReachableFromBlob(blob, 'main');

    expect(identical(result, blob), isFalse);
    expect(_widgetNames(decodeLibraryBlob(result)), <String>['main']);
  });
}

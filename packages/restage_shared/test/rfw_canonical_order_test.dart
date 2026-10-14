import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

void main() {
  final library = RemoteWidgetLibrary(
    [
      Import(LibraryName(['b'])),
      Import(LibraryName(['a']))
    ],
    [
      WidgetDeclaration('Zed', {'y': 1, 'x': 2}, ConstructorCall('Box', {})),
      WidgetDeclaration(
        'Alpha',
        null,
        ConstructorCall('Column', {
          'z': EventHandler('go', {'q': 1, 'p': 2}),
          'children': [
            ConstructorCall('Text', {'text': 'hi', 'maxLines': 1}),
            Switch(ArgsReference(['v']), {
              'b': ConstructorCall('B', {'n': 1, 'm': 2}),
              'a': {'k': 1, 'j': 2},
            }),
            Loop(ArgsReference(['xs']), ConstructorCall('I', {'t': 1, 's': 2})),
          ],
          'a': SetStateHandler(StateReference(['s']), {'d': 1, 'c': 2}),
        }),
      ),
    ],
  );

  test('sorts declarations and map keys recursively, keeps list order', () {
    final out = canonicalizeLibrary(library);
    expect(out.widgets.map((w) => w.name), ['Alpha', 'Zed']);
    expect(out.imports.map((i) => i.name.parts.single), ['b', 'a']);
    expect(out.widgets.last.initialState!.keys, ['x', 'y']);
    final root = out.widgets.first.root as ConstructorCall;
    expect(root.arguments.keys, ['a', 'children', 'z']);
    expect(
      ((root.arguments['z']! as EventHandler).eventArguments).keys,
      ['p', 'q'],
    );
    expect(
      ((root.arguments['a']! as SetStateHandler).value as Map).keys,
      ['c', 'd'],
    );
    final children = root.arguments['children']! as List;
    expect(
        (children[0] as ConstructorCall).arguments.keys, ['maxLines', 'text']);
    final sw = children[1] as Switch;
    expect(sw.outputs.keys, ['b', 'a']);
    expect((sw.outputs['b']! as ConstructorCall).arguments.keys, ['m', 'n']);
    expect((sw.outputs['a']! as Map).keys, ['j', 'k']);
    final loop = children[2] as Loop;
    expect((loop.output as ConstructorCall).arguments.keys, ['s', 't']);
  });

  test('is idempotent and encodes byte-stably', () {
    final once = canonicalizeLibrary(library);
    final twice = canonicalizeLibrary(once);
    expect(encodeLibraryBlob(twice), encodeLibraryBlob(once));
    expect(once.toString(), twice.toString());
  });
}

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart' show Catalog;
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

// A value program whose root calls an installed app function.
const _call =
    r'''{program: "{\"nodes\":[{\"op\":\"native.call\"}]}", captures: {}}''';

final _catalog = Catalog(
  schemaVersion: 1,
  generatedAt: '2026-01-01T00:00:00Z',
  libraries: const {},
  widgets: const [],
);

CompiledScreenContractNeed? _need(String root) => compiledScreenContractNeed(
      parseLibraryFile('import core; widget Paywall = $root;'),
      _catalog,
    );

void main() {
  test('names the widget and property an app function call feeds', () {
    final need = _need('Column(children: [Tap(onTap: {nativeEvent: $_call})])');
    expect(need, isA<AppFunctionCallNeed>());
    need as AppFunctionCallNeed;
    expect((need.widget, need.property), ('Tap', 'onTap'));
  });

  test('names a split widget by the name the app declares', () {
    final need = _need('Chip__split(label: "A")');
    expect((need! as SplitWidgetNeed).widget, 'Chip');
  });

  test('the first reason in source order wins', () {
    expect(
      _need('Column(children: [Chip__split(), Tap(onTap: $_call)])'),
      isA<SplitWidgetNeed>(),
    );
    expect(
      _need('Column(children: [Tap(onTap: $_call), Chip__split()])'),
      isA<AppFunctionCallNeed>(),
    );
  });

  test('a screen that runs no app code needs nothing', () {
    expect(_need('Column(children: [Text(text: "plain")])'), isNull);
  });
}

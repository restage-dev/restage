import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/context_data.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const _localLibrary = LibraryName(<String>['acme', 'widgets']);
const _remoteLibrary = LibraryName(<String>['acme', 'surface']);
const _rootWidget = FullyQualifiedWidgetName(_remoteLibrary, 'Root');

const _defaultSubtitle = 'the factory default';

const _source = '''
import acme.widgets;
widget Root = Group(children: [
  Label(text: data.context.subtitle),
  Label(text: data.context.profile.nickname),
]);
''';

/// A host-supplied value that is absent falls back to the widget's own
/// default, which is what a null host value must resolve to end to end.
Widget _buildLabel(BuildContext context, DataSource source) => Text(
      source.v<String>(const <Object>['text']) ?? _defaultSubtitle,
      textDirection: TextDirection.ltr,
    );

Widget _buildGroup(BuildContext context, DataSource source) => Column(
      children: source.childList(const <Object>['children']),
    );

Future<Runtime> _mount(
  WidgetTester tester,
  Map<String, Object?> hostContext,
) async {
  final runtime = Runtime();
  final data = DynamicContent();
  ContextPublisher(data).publish(hostContext);
  runtime
    ..update(
      _localLibrary,
      LocalWidgetLibrary(<String, LocalWidgetBuilder>{
        'Label': _buildLabel,
        'Group': _buildGroup,
      }),
    )
    ..update(_remoteLibrary, parseLibraryFile(_source));
  await tester.pumpWidget(
    RemoteWidget(
      runtime: runtime,
      data: data,
      widget: _rootWidget,
      onEvent: (_, __) {},
    ),
  );
  await tester.pump();
  addTearDown(runtime.dispose);
  return runtime;
}

void main() {
  group('absent host data', () {
    testWidgets('a null input renders the widget default', (tester) async {
      await _mount(tester, <String, Object?>{
        'subtitle': null,
        'profile': <String, Object?>{'nickname': null},
      });

      expect(find.text(_defaultSubtitle), findsNWidgets(2));
    });

    testWidgets('a supplied input renders that value', (tester) async {
      await _mount(tester, <String, Object?>{
        'subtitle': 'supplied',
        'profile': <String, Object?>{'nickname': 'nick'},
      });

      expect(find.text('supplied'), findsOneWidget);
      expect(find.text('nick'), findsOneWidget);
      expect(find.text(_defaultSubtitle), findsNothing);
    });

    testWidgets('withdrawing an input returns to the default', (tester) async {
      final runtime = Runtime();
      final data = DynamicContent();
      final publisher = ContextPublisher(data)
        ..publish(<String, Object?>{
          'subtitle': 'supplied',
          'profile': <String, Object?>{'nickname': 'nick'},
        });
      runtime
        ..update(
          _localLibrary,
          LocalWidgetLibrary(<String, LocalWidgetBuilder>{
            'Label': _buildLabel,
            'Group': _buildGroup,
          }),
        )
        ..update(_remoteLibrary, parseLibraryFile(_source));
      await tester.pumpWidget(
        RemoteWidget(
          runtime: runtime,
          data: data,
          widget: _rootWidget,
          onEvent: (_, __) {},
        ),
      );
      await tester.pump();
      addTearDown(runtime.dispose);
      expect(find.text('supplied'), findsOneWidget);

      publisher.publish(<String, Object?>{
        'subtitle': null,
        'profile': <String, Object?>{'nickname': null},
      });
      await tester.pump();

      expect(find.text(_defaultSubtitle), findsNWidgets(2));
    });
  });
}

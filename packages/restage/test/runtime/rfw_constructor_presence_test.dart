import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const _localLibrary = LibraryName(<String>['acme', 'widgets']);
const _remoteLibrary = LibraryName(<String>['acme', 'surface']);

final class _Probe extends StatelessWidget {
  const _Probe({this.label = 'constructor default'});

  final String? label;

  @override
  Widget build(BuildContext context) => Text(
        label ?? '<explicit null>',
        textDirection: TextDirection.ltr,
      );
}

Widget _buildProbe(BuildContext context, DataSource source) {
  final presence = RestageRfwConstructorPresence.read(
    source,
    const <Object>['label'],
  );
  final probe = Function.apply(
    _Probe.new,
    const <Object?>[],
    <Symbol, Object?>{
      if (presence.supplied) #label: source.v<String>(presence.valuePath),
    },
  ) as Widget;
  return Column(
    children: [
      Text(
        'supplied:${presence.supplied};hasValue:${presence.hasValue}',
        textDirection: TextDirection.ltr,
      ),
      probe,
    ],
  );
}

String _envelope([String? value]) {
  final valueEntry = value == null
      ? ''
      : ", '${RfwConstructorPresenceProtocol.valueKey}': $value";
  return "{ '${RfwConstructorPresenceProtocol.markerKey}': "
      '${RfwConstructorPresenceProtocol.version}$valueEntry }';
}

Future<void> _pump(
  WidgetTester tester,
  String arguments, {
  required bool binary,
}) async {
  final source = '''
import acme.widgets;
widget Root = Probe($arguments);
''';
  final parsed = parseLibraryFile(source);
  final library = binary
      ? decodeLibraryBlob(Uint8List.fromList(encodeLibraryBlob(parsed)))
      : parsed;
  final runtime = Runtime()
    ..update(
      _localLibrary,
      LocalWidgetLibrary(<String, LocalWidgetBuilder>{'Probe': _buildProbe}),
    )
    ..update(_remoteLibrary, library);

  await tester.pumpWidget(
    RemoteWidget(
      runtime: runtime,
      data: DynamicContent(),
      widget: const FullyQualifiedWidgetName(_remoteLibrary, 'Root'),
      onEvent: (_, __) {},
    ),
  );
  await tester.pump();
}

Future<void> _expectInTextAndBinary(
  WidgetTester tester,
  String arguments,
  Finder finder,
) async {
  for (final binary in [false, true]) {
    await _pump(tester, arguments, binary: binary);
    expect(finder, findsOneWidget);
  }
}

Future<void> _expectArgumentErrorInTextAndBinary(
  WidgetTester tester,
  String arguments,
) async {
  for (final binary in [false, true]) {
    await _pump(tester, arguments, binary: binary);
    expect(tester.takeException(), isArgumentError);
  }
}

void main() {
  testWidgets('outer omission applies the ordinary Dart constructor default',
      (tester) async {
    await _expectInTextAndBinary(tester, '', find.text('constructor default'));
    await _expectInTextAndBinary(
      tester,
      '',
      find.text('supplied:false;hasValue:false'),
    );
  });

  testWidgets('present envelope without a nested value supplies null',
      (tester) async {
    await _expectInTextAndBinary(
        tester, 'label: ${_envelope()}', find.text('<explicit null>'));
    await _expectInTextAndBinary(
      tester,
      'label: ${_envelope()}',
      find.text('supplied:true;hasValue:false'),
    );
  });

  testWidgets('present envelope carries a supplied non-null value',
      (tester) async {
    await _expectInTextAndBinary(
      tester,
      'label: ${_envelope('"authored"')}',
      find.text('authored'),
    );
    await _expectInTextAndBinary(
      tester,
      'label: ${_envelope('"authored"')}',
      find.text('supplied:true;hasValue:true'),
    );
  });

  testWidgets('list and map nested values exist in the envelope',
      (tester) async {
    for (final value in ['["authored"]', '{ value: "authored" }']) {
      await _expectInTextAndBinary(
        tester,
        'label: ${_envelope(value)}',
        find.text('supplied:true;hasValue:true'),
      );
    }
  });

  testWidgets(
      'present envelope whose supplied reference is missing still supplies null',
      (tester) async {
    await _expectInTextAndBinary(
      tester,
      'label: ${_envelope('data.missing')}',
      find.text('<explicit null>'),
    );
    await _expectInTextAndBinary(
      tester,
      'label: ${_envelope('data.missing')}',
      find.text('supplied:true;hasValue:false'),
    );
  });

  testWidgets(
      'a map without the reserved marker cannot impersonate an envelope',
      (tester) async {
    await _expectArgumentErrorInTextAndBinary(
      tester,
      'label: { value: "authored" }',
    );
  });

  testWidgets('a scalar outer value cannot impersonate an envelope',
      (tester) async {
    await _expectArgumentErrorInTextAndBinary(tester, 'label: "authored"');
  });

  testWidgets('a list outer value cannot impersonate an envelope',
      (tester) async {
    await _expectArgumentErrorInTextAndBinary(tester, 'label: ["authored"]');
  });

  testWidgets('an envelope with the wrong version is rejected', (tester) async {
    await _expectArgumentErrorInTextAndBinary(
      tester,
      "label: { '${RfwConstructorPresenceProtocol.markerKey}': 2 }",
    );
  });

  testWidgets('an envelope with the wrong marker is rejected', (tester) async {
    await _expectArgumentErrorInTextAndBinary(
      tester,
      "label: { '${RfwConstructorPresenceProtocol.markerKey}.wrong': 1 }",
    );
  });
}

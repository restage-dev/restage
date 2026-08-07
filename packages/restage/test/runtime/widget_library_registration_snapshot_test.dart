import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  test('registration snapshot is immutable, defensive, and replace-on-conflict',
      () {
    final mutable = <RestageWidgetFactory>[
      RestageWidgetFactory(name: 'First', builder: (_, __) => const SizedBox()),
    ];
    Restage.registerWidgetLibrary(
      const WidgetLibrary.custom('acme.widgets'),
      widgets: mutable,
      capabilityVersion: 2,
    );
    mutable.add(
      RestageWidgetFactory(
          name: 'Leaked', builder: (_, __) => const SizedBox()),
    );

    final first = Restage.widgetLibraryRegistrations;
    expect(
        first.single.widgets.map((widget) => widget.name), <String>['First']);
    expect(first.single.capabilityVersion, 2);
    expect(() => first.add(first.single), throwsUnsupportedError);
    expect(
        () => first.single.widgets.add(mutable.last), throwsUnsupportedError);

    Restage.registerWidgetLibrary(
      const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
            name: 'Second', builder: (_, __) => const SizedBox()),
      ],
      capabilityVersion: 3,
    );
    expect(
      Restage.widgetLibraryRegistrations.single.widgets
          .map((widget) => widget.name),
      <String>['Second'],
    );
    expect(Restage.widgetLibraryRegistrations.single.capabilityVersion, 3);
  });
}

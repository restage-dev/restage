import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

RenderEnv _environment({
  Map<String, Object?> theme = const <String, Object?>{},
  String brightness = 'dark',
  String locale = 'sv-SE',
  double textScale = 1.25,
  Size frame = const Size(390, 844),
}) =>
    RenderEnv(
      theme: theme,
      brightness: brightness,
      locale: locale,
      textScale: textScale,
      zoom: 1,
      frame: frame,
    );

void main() {
  testWidgets('raw core decodes a blob, applies environment, and settles',
      (tester) async {
    final events = <RenderEvent>[];
    final blob = encodeLibraryBlob(
      parseLibraryFile('''
import restage.core;
widget Preview = Text(text: data.title);
'''),
    );
    final surface = RawRfwRenderSurface(
      epoch: 7,
      blob: blob,
      data: const <String, Object?>{'title': 'Hello'},
      environment: _environment(),
      registrations: const <RestageWidgetLibraryRegistration>[],
      entryWidgetName: 'Preview',
      onRemoteEvent: (_, __) {},
      onRenderEvent: events.add,
    );
    expect(() => surface.blob![0] = 0, throwsUnsupportedError);
    await tester.pumpWidget(
      MaterialApp(
        home: surface,
      ),
    );
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('Hello'))).brightness,
        Brightness.dark);
    expect(
        Localizations.localeOf(tester.element(find.text('Hello')))
            .toLanguageTag(),
        'sv-SE');
    await tester.pump();

    expect(events.whereType<Settled>().single.epoch, 7);
    expect(events.whereType<RenderError>(), isEmpty);
  });

  testWidgets('raw core applies caller-supplied customer registrations',
      (tester) async {
    final registration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Badge',
          builder: (_, __) => const Text('Customer badge'),
        ),
      ],
      capabilityVersion: 1,
    );
    final library = parseLibraryFile('''
import acme.widgets;
widget Preview = Badge();
''');
    final surface = RawRfwRenderSurface.library(
      epoch: 1,
      library: library,
      data: const <String, Object?>{},
      environment: _environment(),
      registrations: <RestageWidgetLibraryRegistration>[registration],
      entryWidgetName: 'Preview',
      onRemoteEvent: (_, __) {},
    );
    expect(surface.library, same(library));
    await tester.pumpWidget(
      MaterialApp(
        home: surface,
      ),
    );
    await tester.pump();

    expect(find.text('Customer badge'), findsOneWidget);
  });

  testWidgets('unchanged parent rebuild preserves customer widget state',
      (tester) async {
    var initializations = 0;
    final events = <RenderEvent>[];
    final registration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Counter',
          builder: (_, __) => _CustomerCounter(
            onInitialize: () => initializations += 1,
          ),
        ),
      ],
      capabilityVersion: 1,
    );
    final registrations = <RestageWidgetLibraryRegistration>[registration];
    final library = parseLibraryFile('''
import acme.widgets;
widget Preview = Counter();
''');
    final environment = _environment();
    const data = <String, Object?>{};

    Widget buildSurface(int epoch) => MaterialApp(
          home: RawRfwRenderSurface.library(
            epoch: epoch,
            library: library,
            data: data,
            environment: environment,
            registrations: registrations,
            entryWidgetName: 'Preview',
            onRemoteEvent: (_, __) {},
            onRenderEvent: events.add,
          ),
        );

    await tester.pumpWidget(buildSurface(1));
    await tester.pump();
    expect(find.text('Count 0'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);

    await tester.pumpWidget(buildSurface(1));
    await tester.pump();

    expect(find.text('Count 1'), findsOneWidget);
    expect(initializations, 1);
    expect(events.whereType<Settled>().map((event) => event.epoch), <int>[1]);
  });

  testWidgets(
      'library mode preserves customer state across data, environment, and '
      'document updates', (tester) async {
    var initializations = 0;
    final registration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Counter',
          builder: (_, source) => _CustomerDataCounter(
            label: source.v<String>(<Object>['label']) ?? '<missing>',
            onInitialize: () => initializations += 1,
          ),
        ),
      ],
      capabilityVersion: 1,
    );
    final initialLibrary = parseLibraryFile('''
import restage.core;
import acme.widgets;
widget Preview = Column(children: [
  Counter(label: data.title),
]);
''');
    final editedLibrary = parseLibraryFile('''
import restage.core;
import acme.widgets;
widget Preview = Column(children: [
  Counter(label: data.title),
  Text(text: "Edited"),
]);
''');

    Widget host({
      required RemoteWidgetLibrary library,
      required Map<String, Object?> data,
      required RenderEnv environment,
    }) =>
        MaterialApp(
          home: RawRfwRenderSurface.library(
            epoch: 1,
            library: library,
            data: data,
            environment: environment,
            registrations: <RestageWidgetLibraryRegistration>[registration],
            entryWidgetName: 'Preview',
            onRemoteEvent: (_, __) {},
          ),
        );

    await tester.pumpWidget(host(
      library: initialLibrary,
      data: const <String, Object?>{'title': 'Before'},
      environment: _environment(),
    ));
    await tester.pump();
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    final counterValues = <String>[
      tester.widget<Text>(find.textContaining('Count ')).data!,
    ];

    await tester.pumpWidget(host(
      library: initialLibrary,
      data: const <String, Object?>{'title': 'After'},
      environment: _environment(),
    ));
    await tester.pump();
    counterValues.add(
      tester.widget<Text>(find.textContaining('Count ')).data!,
    );

    await tester.pumpWidget(host(
      library: initialLibrary,
      data: const <String, Object?>{},
      environment: _environment(),
    ));
    await tester.pump();
    counterValues.add(
      tester.widget<Text>(find.textContaining('Count ')).data!,
    );

    await tester.pumpWidget(host(
      library: initialLibrary,
      data: const <String, Object?>{},
      environment: _environment(
        brightness: 'light',
        locale: 'fr-FR',
        textScale: 1.5,
        frame: const Size(430, 932),
      ),
    ));
    await tester.pump();
    final counterContext = tester.element(find.byType(TextButton));
    final brightness = Theme.of(counterContext).brightness;
    final locale = Localizations.localeOf(counterContext).toLanguageTag();
    final frame = MediaQuery.sizeOf(counterContext);
    final textScale = MediaQuery.textScalerOf(counterContext).scale(10);
    counterValues.add(
      tester.widget<Text>(find.textContaining('Count ')).data!,
    );

    await tester.pumpWidget(host(
      library: editedLibrary,
      data: const <String, Object?>{},
      environment: _environment(
        brightness: 'light',
        locale: 'fr-FR',
        textScale: 1.5,
        frame: const Size(430, 932),
      ),
    ));
    await tester.pump();
    final libraryUpdated = find.text('Edited').evaluate().length;
    counterValues.add(
      tester.widget<Text>(find.textContaining('Count ')).data!,
    );

    // Unmount before assertions so a regression that reinstalls the reporting
    // boundary cannot mistake a failing expectation for an owned build error.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(brightness, Brightness.light);
    expect(locale, 'fr-FR');
    expect(frame, const Size(430, 932));
    expect(textScale, 15);
    expect(libraryUpdated, 1);
    expect(counterValues, const <String>[
      'Before · Count 1',
      'After · Count 1',
      '<missing> · Count 1',
      '<missing> · Count 1',
      '<missing> · Count 1',
    ]);
    expect(initializations, 1);
  });

  testWidgets(
      'library mode removes stale registration namespaces without resetting '
      'surviving state', (tester) async {
    var initializations = 0;
    final counterRegistration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Counter',
          builder: (_, __) => _CustomerCounter(
            onInitialize: () => initializations += 1,
          ),
        ),
      ],
      capabilityVersion: 1,
    );
    final removableRegistration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.temporary'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'TemporaryLabel',
          builder: (_, __) => const Text('Temporary registration'),
        ),
      ],
      capabilityVersion: 1,
    );
    final counterLibrary = parseLibraryFile('''
import restage.core;
import acme.widgets;
widget Preview = Counter();
''');
    final removedLibrary = parseLibraryFile('''
import acme.temporary;
widget Preview = TemporaryLabel();
''');

    Widget host({
      required RemoteWidgetLibrary library,
      required List<RestageWidgetLibraryRegistration> registrations,
    }) =>
        MaterialApp(
          home: RawRfwRenderSurface.library(
            epoch: 1,
            library: library,
            data: const <String, Object?>{},
            environment: _environment(),
            registrations: registrations,
            entryWidgetName: 'Preview',
            onRemoteEvent: (_, __) {},
          ),
        );

    await tester.pumpWidget(host(
      library: counterLibrary,
      registrations: <RestageWidgetLibraryRegistration>[
        counterRegistration,
        removableRegistration,
      ],
    ));
    await tester.pump();
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);

    await tester.pumpWidget(host(
      library: counterLibrary,
      registrations: <RestageWidgetLibraryRegistration>[
        counterRegistration,
      ],
    ));
    await tester.pump();
    final counterCount = find.text('Count 1').evaluate().length;
    final initializationCount = initializations;

    await tester.pumpWidget(host(
      library: removedLibrary,
      registrations: <RestageWidgetLibraryRegistration>[
        counterRegistration,
      ],
    ));
    final exception = tester.takeException();
    final errorWidgetCount = find.byType(ErrorWidget).evaluate().length;
    final staleCount = find.text('Temporary registration').evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());

    expect(
      exception.toString(),
      contains('Could not find remote widget named TemporaryLabel'),
    );
    expect(errorWidgetCount, 1);
    expect(counterCount, 1);
    expect(staleCount, 0);
    expect(initializationCount, 1);
  });

  testWidgets('library mode delegates unresolved widgets without reporting',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RawRfwRenderSurface.library(
          epoch: 1,
          library: parseLibraryFile('''
import acme.widgets;
widget Preview = Missing();
'''),
          data: const <String, Object?>{},
          environment: _environment(),
          registrations: const <RestageWidgetLibraryRegistration>[],
          entryWidgetName: 'Preview',
          onRemoteEvent: (_, __) {},
        ),
      ),
    );

    final exception = tester.takeException();
    final errorMessages = find
        .byType(ErrorWidget)
        .evaluate()
        .map((element) => (element.widget as ErrorWidget).message)
        .toList();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      exception.toString(),
      contains('Could not find remote widget named Missing'),
    );
    expect(errorMessages, hasLength(1));
    expect(
      errorMessages.single,
      contains('Could not find remote widget named Missing'),
    );
  });

  testWidgets('an actual in-place data change rebuilds the runtime snapshot',
      (tester) async {
    final data = <String, Object?>{'title': 'Before'};
    final library = parseLibraryFile('''
import restage.core;
widget Preview = Text(text: data.title);
''');
    final environment = _environment();

    Widget buildSurface() => MaterialApp(
          home: RawRfwRenderSurface.library(
            epoch: 1,
            library: library,
            data: data,
            environment: environment,
            registrations: const <RestageWidgetLibraryRegistration>[],
            entryWidgetName: 'Preview',
            onRemoteEvent: (_, __) {},
          ),
        );

    await tester.pumpWidget(buildSurface());
    await tester.pump();
    expect(find.text('Before'), findsOneWidget);

    data['title'] = 'After';
    await tester.pumpWidget(buildSurface());
    await tester.pump();

    expect(find.text('After'), findsOneWidget);
  });

  testWidgets('a throwing customer widget errors once and never settles',
      (tester) async {
    final events = <RenderEvent>[];
    final registration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Broken',
          builder: (_, __) => const _ThrowingCustomerWidget(),
        ),
      ],
      capabilityVersion: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RawRfwRenderSurface.library(
          epoch: 4,
          library: parseLibraryFile('''
import acme.widgets;
widget Preview = Broken();
'''),
          data: const <String, Object?>{},
          environment: _environment(),
          registrations: <RestageWidgetLibraryRegistration>[registration],
          entryWidgetName: 'Preview',
          onRemoteEvent: (_, __) {},
          onRenderEvent: events.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events.whereType<Settled>(), isEmpty);
    expect(events.whereType<RenderError>().single.epoch, 4);

    await tester.pump();
    expect(events.whereType<RenderError>(), hasLength(1));
  });

  testWidgets('a missing remote widget errors once and never settles',
      (tester) async {
    final events = <RenderEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RawRfwRenderSurface.library(
          epoch: 5,
          library: parseLibraryFile('''
import acme.widgets;
widget Preview = Missing();
'''),
          data: const <String, Object?>{},
          environment: _environment(),
          registrations: const <RestageWidgetLibraryRegistration>[],
          entryWidgetName: 'Preview',
          onRemoteEvent: (_, __) {},
          onRenderEvent: events.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(events.whereType<Settled>(), isEmpty);
    expect(events.whereType<RenderError>().single.epoch, 5);

    await tester.pump();
    expect(events.whereType<RenderError>(), hasLength(1));
  });

  testWidgets('settles once after first paint while animation frames continue',
      (tester) async {
    final events = <RenderEvent>[];
    AnimationController? controller;
    final registration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'Animating',
          builder: (_, __) => _AnimatingCustomerWidget(
            onController: (value) => controller = value,
          ),
        ),
      ],
      capabilityVersion: 1,
    );

    await tester.pumpWidget(MaterialApp(
      home: RawRfwRenderSurface.library(
        epoch: 6,
        library: parseLibraryFile('''
import acme.widgets;
widget Preview = Animating();
'''),
        data: const <String, Object?>{},
        environment: _environment(),
        registrations: <RestageWidgetLibraryRegistration>[registration],
        entryWidgetName: 'Preview',
        onRemoteEvent: (_, __) {},
        onRenderEvent: events.add,
      ),
    ));
    await tester.pump();

    expect(controller, isNotNull);
    expect(controller!.isAnimating, isTrue);
    expect(events.whereType<Settled>(), hasLength(1));
    expect(events.whereType<RenderError>(), isEmpty);

    await tester.pump(const Duration(milliseconds: 100));
    expect(controller!.isAnimating, isTrue);
    expect(events.whereType<Settled>(), hasLength(1));

    controller!.stop();
    await tester.pumpAndSettle();
    expect(events.whereType<Settled>(), hasLength(1));
  });

  testWidgets('late build failure follows settled and terminates once',
      (tester) async {
    final events = <RenderEvent>[];
    final shouldFail = ValueNotifier<bool>(false);
    addTearDown(shouldFail.dispose);
    final registration = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('acme.widgets'),
      widgets: <RestageWidgetFactory>[
        RestageWidgetFactory(
          name: 'LateFailure',
          builder: (_, __) => _LateFailingCustomerWidget(shouldFail),
        ),
      ],
      capabilityVersion: 1,
    );

    await tester.pumpWidget(MaterialApp(
      home: RawRfwRenderSurface.library(
        epoch: 8,
        library: parseLibraryFile('''
import acme.widgets;
widget Preview = LateFailure();
'''),
        data: const <String, Object?>{},
        environment: _environment(),
        registrations: <RestageWidgetLibraryRegistration>[registration],
        entryWidgetName: 'Preview',
        onRemoteEvent: (_, __) {},
        onRenderEvent: events.add,
      ),
    ));
    await tester.pump();
    expect(events.map((event) => event.runtimeType), <Type>[Settled]);

    shouldFail.value = true;
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      events.map((event) => event.runtimeType),
      <Type>[Settled, RenderError],
    );
    await tester.pump();
    expect(events.whereType<RenderError>(), hasLength(1));
  });

  for (final phase in _StructuralReportPhase.values) {
    testWidgets(
        'late independent ${phase.name} report follows settled and terminates '
        'once', (tester) async {
      final events = <RenderEvent>[];
      final controller = _StructuralReportController();
      addTearDown(controller.dispose);
      final registration = RestageWidgetLibraryRegistration(
        library: const WidgetLibrary.custom('acme.structural'),
        widgets: <RestageWidgetFactory>[
          RestageWidgetFactory(
            name: 'StructuralReporter',
            builder: (_, __) => _StructuralReportProbe(
              controller: controller,
              phase: phase,
            ),
          ),
        ],
        capabilityVersion: 1,
      );

      await tester.pumpWidget(MaterialApp(
        home: RawRfwRenderSurface.library(
          epoch: 9,
          library: parseLibraryFile('''
import acme.structural;
widget Preview = StructuralReporter();
'''),
          data: const <String, Object?>{},
          environment: _environment(),
          registrations: <RestageWidgetLibraryRegistration>[registration],
          entryWidgetName: 'Preview',
          onRemoteEvent: (_, __) {},
          onRenderEvent: events.add,
        ),
      ));
      await tester.pump();
      expect(events.map((event) => event.runtimeType), <Type>[Settled]);

      controller.trigger();
      await tester.pump();
      await tester.pump();

      expect(
        events.map((event) => event.runtimeType),
        <Type>[Settled, RenderError],
      );
      controller.trigger();
      await tester.pump();
      await tester.pump();
      expect(events.whereType<Settled>(), hasLength(1));
      expect(events.whereType<RenderError>(), hasLength(1));
    });
  }
}

enum _StructuralReportPhase { layout, paint }

final class _StructuralReportController extends ChangeNotifier {
  int revision = 0;

  void trigger() {
    revision += 1;
    notifyListeners();
  }
}

final class _StructuralReportProbe extends LeafRenderObjectWidget {
  const _StructuralReportProbe({
    required this.controller,
    required this.phase,
  });

  final _StructuralReportController controller;
  final _StructuralReportPhase phase;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStructuralReportProbe(controller, phase);
}

final class _RenderStructuralReportProbe extends RenderBox {
  _RenderStructuralReportProbe(this.controller, this.phase);

  final _StructuralReportController controller;
  final _StructuralReportPhase phase;
  int _reportedRevision = 0;

  @override
  bool get isRepaintBoundary => phase == _StructuralReportPhase.paint;

  @override
  bool get sizedByParent => phase == _StructuralReportPhase.layout;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.addListener(_markDirty);
  }

  @override
  void detach() {
    controller.removeListener(_markDirty);
    super.detach();
  }

  void _markDirty() {
    switch (phase) {
      case _StructuralReportPhase.layout:
        markNeedsLayout();
        return;
      case _StructuralReportPhase.paint:
        markNeedsPaint();
        return;
    }
  }

  @override
  void performResize() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void performLayout() {
    if (!sizedByParent) {
      size = constraints.constrain(const Size.square(20));
    }
    if (phase == _StructuralReportPhase.layout) _reportIfTriggered();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (phase == _StructuralReportPhase.paint) _reportIfTriggered();
  }

  void _reportIfTriggered() {
    if (_reportedRevision == controller.revision) return;
    _reportedRevision = controller.revision;
    FlutterError.reportError(FlutterErrorDetails(
      exception: StateError('late independent ${phase.name} report'),
      stack: StackTrace.current,
      library: 'restage_preview_host_test',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<RenderObject>('renderObject', this),
      ],
    ));
  }
}

class _AnimatingCustomerWidget extends StatefulWidget {
  const _AnimatingCustomerWidget({required this.onController});

  final ValueChanged<AnimationController> onController;

  @override
  State<_AnimatingCustomerWidget> createState() =>
      _AnimatingCustomerWidgetState();
}

class _AnimatingCustomerWidgetState extends State<_AnimatingCustomerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    widget.onController(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Transform.translate(
          offset: Offset(_controller.value, 0),
          child: child,
        ),
        child: const SizedBox.square(dimension: 20),
      );
}

class _LateFailingCustomerWidget extends StatelessWidget {
  const _LateFailingCustomerWidget(this.shouldFail);

  final ValueNotifier<bool> shouldFail;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: shouldFail,
        builder: (_, fail, __) {
          if (fail) throw StateError('late customer widget build failed');
          return const SizedBox.square(dimension: 20);
        },
      );
}

class _ThrowingCustomerWidget extends StatelessWidget {
  const _ThrowingCustomerWidget();

  @override
  Widget build(BuildContext context) =>
      throw StateError('customer widget build failed');
}

class _CustomerCounter extends StatefulWidget {
  const _CustomerCounter({required this.onInitialize});

  final VoidCallback onInitialize;

  @override
  State<_CustomerCounter> createState() => _CustomerCounterState();
}

class _CustomerCounterState extends State<_CustomerCounter> {
  var _count = 0;

  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => _count += 1),
        child: Text('Count $_count'),
      );
}

class _CustomerDataCounter extends StatefulWidget {
  const _CustomerDataCounter({
    required this.label,
    required this.onInitialize,
  });

  final String label;
  final VoidCallback onInitialize;

  @override
  State<_CustomerDataCounter> createState() => _CustomerDataCounterState();
}

class _CustomerDataCounterState extends State<_CustomerDataCounter> {
  var _count = 0;

  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => _count += 1),
        child: Text('${widget.label} · Count $_count'),
      );
}

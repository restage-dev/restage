import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_widgetbook_example/onboarding/screens/get_started_screen.dart';

const _missing = SurfaceScreenUnavailableError(
  reason: SurfaceScreenUnavailableReason.missing,
  message: 'The screen is unavailable.',
);

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  for (final atPlacement in [false, true]) {
    final constructor = atPlacement ? 'placement' : 'default';

    testWidgets('$constructor mount keeps the compiled fallback by default', (
      tester,
    ) async {
      final resolver = _UnavailableResolver();
      final errors = <SurfaceScreenUnavailableError>[];
      final events = <GetStartedScreenSurfaceEvent>[];
      final mount = _mount(
        atPlacement: atPlacement,
        resolver: resolver,
        onUnavailable: errors.add,
        onEvent: events.add,
      );

      await tester.pumpWidget(MaterialApp(home: mount));
      await tester.pumpAndSettle();

      // The fallback is the screen's build as the app wrote it.
      expect(find.text('Get started'), findsOneWidget);
      expect(find.byKey(const ValueKey('get-started-action')), findsOneWidget);
      expect(resolver.calls, 1);
      expect(errors, [_missing]);

      final host = tester.widget<RestageScreen<GetStartedScreenSurfaceEvent>>(
        find.byType(RestageScreen<GetStartedScreenSurfaceEvent>),
      );
      expect(host.context, <String, Object?>{
        'title': 'Welcome',
        'enabled': false,
        'data': 'Host data',
        'context': 'Host context',
        'itemContext': 'Host item context',
        'description': 'Host description',
        'usage': 'Host usage',
        // The button's key reaches the design as the app's own instance.
        '_hb227fda92b': <String, Object?>{
          'kind': 'nativeBinding',
          'key': '_hb227fda92b',
          'type': 'flutter.Key',
          'nullable': false,
        },
      });
      expect(host.placementBinding!.name, atPlacement ? 'welcome_card' : null);
      expect(host.resolver, same(resolver));
      expect(host.loadingBuilder, same(_loading));

      await tester.tap(find.byKey(const ValueKey('get-started-action')));
      await tester.pump();
      expect(events.single, isA<GetStartedScreenSurfaceContinueEventEvent>());
      expect(
        (events.single as GetStartedScreenSurfaceContinueEventEvent).value,
        'preview',
      );
    });

    testWidgets(
      '$constructor mount can show nothing for an unavailable screen',
      (tester) async {
        final resolver = _UnavailableResolver();
        final errors = <SurfaceScreenUnavailableError>[];
        Widget nothing(BuildContext context) => const SizedBox.shrink();

        await tester.pumpWidget(
          MaterialApp(
            home: _mount(
              atPlacement: atPlacement,
              resolver: resolver,
              fallbackBuilder: nothing,
              onUnavailable: errors.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GetStartedScreen), findsNothing);
        expect(find.text('Get started'), findsNothing);
        expect(resolver.calls, 1);
        expect(errors, [_missing]);
        final host = tester.widget<RestageScreen<GetStartedScreenSurfaceEvent>>(
          find.byType(RestageScreen<GetStartedScreenSurfaceEvent>),
        );
        expect(host.fallbackBuilder, same(nothing));
        expect(host.context!['title'], 'Welcome');
      },
    );

    testWidgets('$constructor mount can replace the unavailable fallback', (
      tester,
    ) async {
      final errors = <SurfaceScreenUnavailableError>[];

      await tester.pumpWidget(
        MaterialApp(
          home: _mount(
            atPlacement: atPlacement,
            resolver: _UnavailableResolver(),
            fallbackBuilder: (_) => const Text('Unavailable'),
            onUnavailable: errors.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GetStartedScreen), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(errors, [_missing]);
    });
  }
}

GetStartedScreenSurface _mount({
  required bool atPlacement,
  required SurfaceScreenResolver resolver,
  WidgetBuilder? fallbackBuilder,
  ValueChanged<SurfaceScreenUnavailableError>? onUnavailable,
  ValueChanged<GetStartedScreenSurfaceEvent>? onEvent,
}) => atPlacement
    ? GetStartedScreenSurface.atPlacement(
        'welcome_card',
        key: const ValueKey('mount'),
        title: 'Welcome',
        enabled: false,
        tone: GetStartedScreenTone.urgent,
        data: 'Host data',
        context: 'Host context',
        itemContext: 'Host item context',
        restageA2uiStatus: GetStartedScreenTone.urgent,
        description: 'Host description',
        usage: 'Host usage',
        resolver: resolver,
        fallbackBuilder: fallbackBuilder,
        onUnavailable: onUnavailable,
        onEvent: onEvent,
        loadingBuilder: _loading,
      )
    : GetStartedScreenSurface(
        key: const ValueKey('mount'),
        title: 'Welcome',
        enabled: false,
        tone: GetStartedScreenTone.urgent,
        data: 'Host data',
        context: 'Host context',
        itemContext: 'Host item context',
        restageA2uiStatus: GetStartedScreenTone.urgent,
        description: 'Host description',
        usage: 'Host usage',
        resolver: resolver,
        fallbackBuilder: fallbackBuilder,
        onUnavailable: onUnavailable,
        onEvent: onEvent,
        loadingBuilder: _loading,
      );

Widget _loading(BuildContext context) => const Text('Loading');

final class _UnavailableResolver implements SurfaceScreenResolver {
  int calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    calls++;
    throw _missing;
  }
}

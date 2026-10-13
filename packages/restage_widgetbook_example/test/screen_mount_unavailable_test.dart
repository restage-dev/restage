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
      final events = <GetStartedScreenEvent>[];
      final mount = _mount(
        atPlacement: atPlacement,
        resolver: resolver,
        onUnavailable: errors.add,
        onEvent: events.add,
      );

      await tester.pumpWidget(MaterialApp(home: mount));
      await tester.pumpAndSettle();

      final fallback = tester.widget<GetStartedScreen>(
        find.byType(GetStartedScreen),
      );
      expect(fallback.title, 'Welcome');
      expect(fallback.enabled, isFalse);
      expect(fallback.tone, GetStartedScreenTone.urgent);
      expect(fallback.data, 'Host data');
      expect(fallback.context, 'Host context');
      expect(fallback.itemContext, 'Host item context');
      expect(fallback.restageA2uiStatus, GetStartedScreenTone.urgent);
      expect(fallback.description, 'Host description');
      expect(fallback.usage, 'Host usage');
      expect(fallback.key, isNull);
      expect(resolver.calls, 1);
      expect(errors, [_missing]);

      final host = tester.widget<RestageScreen<GetStartedScreenEvent>>(
        find.byType(RestageScreen<GetStartedScreenEvent>),
      );
      expect(host.context, <String, Object?>{
        'title': 'Welcome',
        'enabled': false,
        'data': 'Host data',
        'context': 'Host context',
        'itemContext': 'Host item context',
        'description': 'Host description',
        'usage': 'Host usage',
      });
      expect(host.placementBinding!.name, atPlacement ? 'welcome_card' : null);
      expect(host.resolver, same(resolver));
      expect(host.loadingBuilder, same(_loading));

      await tester.tap(find.byKey(const ValueKey('get-started-action')));
      await tester.pump();
      expect(events.single, isA<GetStartedScreenContinueEventEvent>());
      expect(
        (events.single as GetStartedScreenContinueEventEvent).value,
        'preview',
      );
    });

    testWidgets('$constructor mount can hide an unavailable screen', (
      tester,
    ) async {
      final resolver = _UnavailableResolver();
      final errors = <SurfaceScreenUnavailableError>[];
      const policy = SurfaceScreenUnavailablePolicy.hide();

      await tester.pumpWidget(
        MaterialApp(
          home: _mount(
            atPlacement: atPlacement,
            resolver: resolver,
            unavailable: policy,
            onUnavailable: errors.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GetStartedScreen), findsNothing);
      expect(find.text('Get started'), findsNothing);
      expect(resolver.calls, 1);
      expect(errors, [_missing]);
      final host = tester.widget<RestageScreen<GetStartedScreenEvent>>(
        find.byType(RestageScreen<GetStartedScreenEvent>),
      );
      expect(host.unavailable, same(policy));
      expect(host.context!['title'], 'Welcome');
    });

    testWidgets('$constructor mount can replace the unavailable fallback', (
      tester,
    ) async {
      SurfaceScreenUnavailableError? received;
      final errors = <SurfaceScreenUnavailableError>[];
      final policy = SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) {
          received = error;
          return Text('Unavailable: ${error.reason.name}');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: _mount(
            atPlacement: atPlacement,
            resolver: _UnavailableResolver(),
            unavailable: policy,
            onUnavailable: errors.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GetStartedScreen), findsNothing);
      expect(find.text('Unavailable: missing'), findsOneWidget);
      expect(received, same(_missing));
      expect(errors, [_missing]);
    });
  }
}

GetStartedScreenSurface _mount({
  required bool atPlacement,
  required SurfaceScreenResolver resolver,
  SurfaceScreenUnavailablePolicy? unavailable,
  ValueChanged<SurfaceScreenUnavailableError>? onUnavailable,
  ValueChanged<GetStartedScreenEvent>? onEvent,
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
        unavailable: unavailable,
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
        unavailable: unavailable,
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

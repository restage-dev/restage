import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/analytics_event_mapper.dart';
import 'package:restage/src/analytics/render_event_privacy.dart';
import 'package:restage/src/authoring/onboarding_event_dispatcher.dart'
    show currentSurfaceEventDispatcherOwner, RestageFlowEventHandlerAssociation;
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:restage_shared/legacy_analytics.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart';
import '../surface_screen/surface_screen_test_support.dart';

const _appContext = AnalyticsAppContext(
  platform: 'ios',
  locale: 'en_US',
  sdkVersion: '2.0.0',
);

const _privateGraphFlow = OnboardingFlowRef<FirstRunResult>(
  id: 'private_graph',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: FirstRunResult.decode,
);

const _emptyGraphFlow = OnboardingFlowRef<FirstRunResult>(
  id: 'empty_graph',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: FirstRunResult.decode,
);

final class _BlobResolver implements VariantResolver {
  _BlobResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    return ResolvedVariant(
      bytes: bytes,
      paywallId: id,
      surfaceVersion: '1',
    );
  }
}

final class _HeldScreenResolver implements SurfaceScreenResolver {
  _HeldScreenResolver(this.initial);

  final ResolvedSurfaceScreen initial;
  final Completer<ResolvedSurfaceScreen> next =
      Completer<ResolvedSurfaceScreen>();
  var calls = 0;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) {
    calls += 1;
    return calls == 1
        ? Future<ResolvedSurfaceScreen>.value(initial)
        : next.future;
  }
}

final class _BlobPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _BlobPayloadResolver(this.bytes);

  final Uint8List bytes;

  ResolvedVariant _variant(String id) => ResolvedVariant(
        bytes: bytes,
        paywallId: id,
        surfaceVersion: '7',
        paywallPublishedVersion: 7,
      );

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      _variant(id);

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      BlobPaywallPayload(_variant(id));
}

final class _MutableBlobResolver implements VariantResolver {
  _MutableBlobResolver(this.bytes);

  Uint8List bytes;
  bool fails = false;
  int version = 1;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (fails) {
      throw const RestagePaywallError(
        code: 'delivery_unavailable',
        message: 'No blob is available.',
      );
    }
    return ResolvedVariant(
      bytes: bytes,
      paywallId: id,
      surfaceVersion: '$version',
      paywallPublishedVersion: version,
    );
  }
}

VariantResolver _deliveryResolver(
  String route,
  Uint8List bytes,
) {
  if (route == 'asset') {
    return _BlobResolver(bytes);
  }
  return _BlobPayloadResolver(bytes);
}

final class _FlowPayloadResolver
    implements VariantResolver, FlowCapableVariantResolver {
  _FlowPayloadResolver(this.flow);

  final ResolvedFlow flow;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      throw UnimplementedError();

  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    return FlowPaywallPayload(flow: flow, paywallId: id);
  }
}

Uint8List _paywallBlob() {
  const source = '''
import restage.core;

widget Paywall = Column(children: [
  GestureDetector(
    onTap: event "selected_plan" {
      selection: data.context.secret,
      control: "retained"
    },
    child: Text(text: "Select paywall plan")
  ),
  GestureDetector(
    onTap: event "control_only" { control: "retained" },
    child: Text(text: "Select without host data")
  )
]);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _flowBlob() {
  const source = '''
import restage.core;

widget OnboardingScreen = GestureDetector(
  onTap: event "selected_plan" {
    selection: data.context.secret,
    control: "retained"
  },
  child: Text(text: "Select flow plan")
);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

Uint8List _flowControlBlob() {
  const source = '''
import restage.core;

widget OnboardingScreen = GestureDetector(
  onTap: event "selected_plan" { control: "retained" },
  child: Text(text: "Select flow control")
);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

enum _NativeCallbackCatalog { core, material, cupertino, custom }

enum _NativePrivacyTransition { capturedPrivate, invokedPrivate }

const _nativeCallbackLibrary = WidgetLibrary.custom('acme.native_callbacks');

final class _NativeCallbackProbe extends StatelessWidget {
  const _NativeCallbackProbe({required this.onChanged});

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void _registerNativeCallbackWidget() {
  Restage.registerWidgetLibrary(
    _nativeCallbackLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'NativeCallbackProbe',
        builder: (_, source) => _NativeCallbackProbe(
          onChanged: source.handler<ValueChanged<String>>(
            const <Object>['onChanged'],
            (trigger) => (value) => trigger(<String, Object?>{'value': value}),
          ),
        ),
      ),
    ],
    capabilityVersion: 1,
  );
}

Uint8List _nativeCallbackBlob(_NativeCallbackCatalog catalog) {
  final constructor = switch (catalog) {
    _NativeCallbackCatalog.core => '''
import restage.core;

widget Paywall = GestureDetector(
  onTap: event "selected_plan" {
    selection: data.context.secret,
    control: "retained"
  },
  child: Text(text: "Select native plan")
);
''',
    _NativeCallbackCatalog.material => '''
import restage.core;
import restage.material;

widget Paywall = TextButton(
  onPressed: event "selected_plan" {
    selection: data.context.secret,
    control: "retained"
  },
  child: Text(text: "Select material plan")
);
''',
    _NativeCallbackCatalog.cupertino => '''
import restage.core;
import restage.cupertino;

widget Paywall = CupertinoButton(
  onPressed: event "selected_plan" {
    selection: data.context.secret,
    control: "retained"
  },
  child: Text(text: "Select cupertino plan")
);
''',
    _NativeCallbackCatalog.custom => '''
import acme.native_callbacks;

widget Paywall = NativeCallbackProbe(
  onChanged: event "selected_plan" {
    selection: data.context.secret,
    control: "retained"
  }
);
''',
  };
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(constructor)));
}

VoidCallback _nativeCatalogCallback(
  WidgetTester tester,
  _NativeCallbackCatalog catalog,
) {
  return switch (catalog) {
    _NativeCallbackCatalog.core => tester
        .widget<GestureDetector>(
          find.ancestor(
            of: find.text('Select native plan'),
            matching: find.byType(GestureDetector),
          ),
        )
        .onTap!,
    _NativeCallbackCatalog.material =>
      tester.widget<TextButton>(find.byType(TextButton)).onPressed!,
    _NativeCallbackCatalog.cupertino =>
      tester.widget<CupertinoButton>(find.byType(CupertinoButton)).onPressed!,
    _NativeCallbackCatalog.custom => () {
        final onChanged = tester
            .widget<_NativeCallbackProbe>(find.byType(_NativeCallbackProbe))
            .onChanged!;
        return () => onChanged('typed');
      }(),
  };
}

VoidCallback _gestureCallback(WidgetTester tester, String label) {
  return tester
      .widget<GestureDetector>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(GestureDetector),
        ),
      )
      .onTap!;
}

const _localPaywallLibrary = WidgetLibrary.custom('acme.paywall');

Uint8List _localPaywallBlob({
  required String label,
  String control = 'retained',
  bool stateful = false,
}) {
  final source = '''
import acme.paywall;

widget Paywall = AuthoredPaywallProbe(
  selection: data.context.secret,
  label: "$label",
  control: "$control",
  stateful: $stateful
);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void _registerLocalPaywallWidget({
  required void Function(String label, VoidCallback callback) onCallbackBuilt,
}) {
  Restage.registerWidgetLibrary(
    _localPaywallLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'AuthoredPaywallProbe',
        builder: (_, source) {
          final selection = source.v<String>(const <Object>['selection']);
          final label = source.v<String>(const <Object>['label'])!;
          final control = source.v<String>(const <Object>['control'])!;
          if (source.v<bool>(const <Object>['stateful']) ?? false) {
            return _StatefulPaywallAuthoredProbe(
              selection: selection,
              label: label,
              control: control,
              onCallbackBuilt: onCallbackBuilt,
            );
          }
          return _PaywallAuthoredProbe(
            selection: selection,
            label: label,
            control: control,
            onCallbackBuilt: onCallbackBuilt,
          );
        },
      ),
    ],
    capabilityVersion: 1,
  );
}

final class _PaywallAuthoredProbe extends StatelessWidget {
  const _PaywallAuthoredProbe({
    required this.selection,
    required this.label,
    required this.control,
    required this.onCallbackBuilt,
  });

  final String? selection;
  final String label;
  final String control;
  final void Function(String label, VoidCallback callback) onCallbackBuilt;

  @override
  Widget build(BuildContext context) {
    final callback = paywallEvent(
      'selected_plan',
      args: <String, Object?>{
        if (selection != null) 'selection': selection,
        'control': control,
      },
    );
    onCallbackBuilt(label, callback);
    return GestureDetector(onTap: callback, child: Text(label));
  }
}

final class _StatefulPaywallAuthoredProbe extends StatefulWidget {
  const _StatefulPaywallAuthoredProbe({
    required this.selection,
    required this.label,
    required this.control,
    required this.onCallbackBuilt,
  });

  final String? selection;
  final String label;
  final String control;
  final void Function(String label, VoidCallback callback) onCallbackBuilt;

  @override
  State<_StatefulPaywallAuthoredProbe> createState() =>
      _StatefulPaywallAuthoredProbeState();
}

final class _StatefulPaywallAuthoredProbeState
    extends State<_StatefulPaywallAuthoredProbe> {
  var _rebuilds = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: () => setState(() => _rebuilds += 1),
          child: Text('Rebuild ${widget.label}: $_rebuilds'),
        ),
        _PaywallAuthoredProbe(
          selection: widget.selection,
          label: widget.label,
          control: widget.control,
          onCallbackBuilt: widget.onCallbackBuilt,
        ),
      ],
    );
  }
}

const _localPrivacyLibrary = WidgetLibrary.custom('acme.privacy');

Uint8List _localPrivacyFlowBlob({
  String label = 'Select local plan',
  String control = 'retained',
  bool stateful = false,
}) {
  final source = '''
import acme.privacy;
import restage.core;

widget OnboardingScreen = Column(children: [
  GestureDetector(
    onTap: event "selected_plan" {
      selection: data.context.secret,
      control: "retained"
    },
    child: Text(text: "Select direct plan")
  ),
  AuthoredProbe(
    selection: data.context.secret,
    label: "$label",
    control: "$control",
    stateful: $stateful
  )
]);
''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void _registerLocalPrivacyWidget({
  void Function(String label, VoidCallback callback)? onCallbackBuilt,
  bool contextFree = false,
  ValueListenable<SurfaceEventHandler?>? nestedDispatcherHandler,
}) {
  Restage.registerWidgetLibrary(
    _localPrivacyLibrary,
    widgets: <RestageWidgetFactory>[
      RestageWidgetFactory(
        name: 'AuthoredProbe',
        builder: (_, source) {
          final selection = source.v<String>(const <Object>['selection']);
          final label =
              source.v<String>(const <Object>['label']) ?? 'Select local plan';
          final control =
              source.v<String>(const <Object>['control']) ?? 'retained';
          final Widget probe;
          if (source.v<bool>(const <Object>['stateful']) ?? false) {
            probe = _StatefulAuthoredPrivacyProbe(
              selection: selection,
              label: label,
              control: control,
              onCallbackBuilt: onCallbackBuilt,
              contextFree: contextFree,
            );
          } else {
            probe = _AuthoredPrivacyProbe(
              selection: selection,
              label: label,
              control: control,
              onCallbackBuilt: onCallbackBuilt,
              contextFree: contextFree,
            );
          }
          final handlerListenable = nestedDispatcherHandler;
          if (handlerListenable == null) return probe;
          return ValueListenableBuilder<SurfaceEventHandler?>(
            valueListenable: handlerListenable,
            child: probe,
            builder: (context, handler, child) => handler == null
                ? child!
                : RestageEventDispatcher(
                    onEvent: handler,
                    child: child!,
                  ),
          );
        },
      ),
    ],
  );
}

final class _AuthoredPrivacyProbe extends StatelessWidget {
  const _AuthoredPrivacyProbe({
    required this.selection,
    this.label = 'Select local plan',
    this.control = 'retained',
    this.onCallbackBuilt,
    this.contextFree = false,
  });

  final String? selection;
  final String label;
  final String control;
  final void Function(String label, VoidCallback callback)? onCallbackBuilt;
  final bool contextFree;

  @override
  Widget build(BuildContext context) {
    const event = SurfaceEvent<Map<String, Object?>>('selected_plan');
    final value = <String, Object?>{
      if (selection != null) 'selection': selection,
      'control': control,
    };
    final callback = contextFree
        ? surfaceEvent<Map<String, Object?>, Map<String, Object?>>(event, value)
        : surfaceEventWithContext<Map<String, Object?>, Map<String, Object?>>(
            context,
            event,
            value,
          );
    onCallbackBuilt?.call(label, callback);
    return GestureDetector(
      onTap: callback,
      child: Text(label),
    );
  }
}

final class _StatefulAuthoredPrivacyProbe extends StatefulWidget {
  const _StatefulAuthoredPrivacyProbe({
    required this.selection,
    required this.label,
    required this.control,
    this.onCallbackBuilt,
    this.contextFree = false,
  });

  final String? selection;
  final String label;
  final String control;
  final void Function(String label, VoidCallback callback)? onCallbackBuilt;
  final bool contextFree;

  @override
  State<_StatefulAuthoredPrivacyProbe> createState() =>
      _StatefulAuthoredPrivacyProbeState();
}

final class _StatefulAuthoredPrivacyProbeState
    extends State<_StatefulAuthoredPrivacyProbe> {
  var _rebuilds = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: () => setState(() => _rebuilds += 1),
          child: Text('Rebuild ${widget.label}: $_rebuilds'),
        ),
        _AuthoredPrivacyProbe(
          selection: widget.selection,
          label: widget.label,
          control: widget.control,
          onCallbackBuilt: widget.onCallbackBuilt,
          contextFree: widget.contextFree,
        ),
      ],
    );
  }
}

final class _EqualRegistryKey {
  @override
  bool operator ==(Object other) => other is _EqualRegistryKey;

  @override
  int get hashCode => 0;
}

enum _ControllerBackedView { flow, screen }

enum _AuthoredHelperBinding { contextBound, contextFree }

enum _OwnerHandlerShape { wrongController, forwarding }

String _controllerBackedViewLabel(_ControllerBackedView view) => switch (view) {
      _ControllerBackedView.flow => 'flow view',
      _ControllerBackedView.screen => 'screen view',
    };

String _controllerBackedViewToken(_ControllerBackedView view) => switch (view) {
      _ControllerBackedView.flow => 'flow-view',
      _ControllerBackedView.screen => 'screen-view',
    };

String _authoredHelperBindingLabel(_AuthoredHelperBinding binding) =>
    switch (binding) {
      _AuthoredHelperBinding.contextBound => 'context-bound',
      _AuthoredHelperBinding.contextFree => 'context-free',
    };

String _ownerHandlerShapeLabel(_OwnerHandlerShape shape) => switch (shape) {
      _OwnerHandlerShape.wrongController => 'wrong-controller',
      _OwnerHandlerShape.forwarding => 'forwarding',
    };

Widget _controllerBackedView(
  _ControllerBackedView view, {
  Key? key,
  required RestageFlowController<FirstRunResult> controller,
  required Map<String, Object?>? context,
}) =>
    switch (view) {
      // The flow's screens are routes, so the view needs bounded constraints
      // wherever this helper is mounted.
      _ControllerBackedView.flow => SizedBox(
          key: key,
          height: 200,
          child: RestageFlowView<FirstRunResult>(
            controller: controller,
            context: context,
          ),
        ),
      _ControllerBackedView.screen => RestageScreenView<FirstRunResult>(
          key: key,
          controller: controller,
          context: context,
        ),
    };

final class _MutablePrivacyFlowResolver implements FlowResolver {
  _MutablePrivacyFlowResolver(this.current);

  ResolvedFlow current;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async => current;
}

ResolvedFlow _resolvedPrivacyFlow(
  Uint8List blob, {
  OnboardingFlowRef<FirstRunResult> flow = firstRunFlowRef,
}) {
  final hash = FlowContentHash.compute(blob);
  return ResolvedFlow(
    document: FlowDocument(
      flow: flow.id,
      version: flow.version,
      schemaVersion: 1,
      minClient: flow.minClient,
      initial: 'welcome',
      outbound: const FlowOutboundDeclarations(
        customEvents: <String, FlowOutboundPayloadDeclaration>{
          'selected_plan': FlowOutboundPayloadDeclaration(
            fields: <String, FlowOutboundField>{
              'selection': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'selection'),
              ),
              'control': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'control'),
              ),
            },
          ),
        },
      ),
      screenArtifacts: <String, ScreenArtifact>{
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: flow.minClient,
          contentHash: hash,
        ),
      },
      states: const <String, FlowState>{
        'welcome': ScreenFlowState(screen: 'welcome', on: {}),
      },
    ),
    screenBlobs: <String, Uint8List>{'welcome': blob},
    cacheHit: false,
  );
}

ResolvedFlow _privacyFlow() => _resolvedPrivacyFlow(_flowBlob());

ResolvedFlow _paywallPrivacyFlow() {
  final blob = _flowBlob();
  return ResolvedFlow(
    document: FlowDocument(
      flow: 'privacy-paywall',
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: 'entry',
      outbound: const FlowOutboundDeclarations(
        customEvents: <String, FlowOutboundPayloadDeclaration>{
          'selected_plan': FlowOutboundPayloadDeclaration(
            fields: <String, FlowOutboundField>{
              'selection': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'selection'),
              ),
              'control': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'control'),
              ),
            },
          ),
        },
      ),
      screenArtifacts: <String, ScreenArtifact>{
        'entry': ScreenArtifact(
          path: 'entry.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(blob),
        ),
      },
      states: const <String, FlowState>{
        'entry': ScreenFlowState(screen: 'entry', on: {}),
      },
    ),
    screenBlobs: <String, Uint8List>{'entry': blob},
    cacheHit: false,
  );
}

ResolvedFlow _localPrivacyFlow() =>
    _resolvedPrivacyFlow(_localPrivacyFlowBlob());

ResolvedFlow _twoScreenLocalPrivacyFlow() {
  final first = _localPrivacyFlowBlob(label: 'Select first screen');
  final second = _localPrivacyFlowBlob(label: 'Select second screen');
  return ResolvedFlow(
    document: FlowDocument(
      flow: firstRunFlowRef.id,
      version: firstRunFlowRef.version,
      schemaVersion: 1,
      minClient: firstRunFlowRef.minClient,
      initial: 'welcome',
      outbound: const FlowOutboundDeclarations(
        customEvents: <String, FlowOutboundPayloadDeclaration>{
          'selected_plan': FlowOutboundPayloadDeclaration(
            fields: <String, FlowOutboundField>{
              'selection': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'selection'),
              ),
              'control': FlowOutboundField(
                type: FlowDataType.string,
                ref: EventFlowOutboundRef(key: 'control'),
              ),
            },
          ),
        },
      ),
      screenArtifacts: <String, ScreenArtifact>{
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: firstRunFlowRef.minClient,
          contentHash: FlowContentHash.compute(first),
        ),
        'profile': ScreenArtifact(
          path: 'profile.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: firstRunFlowRef.minClient,
          contentHash: FlowContentHash.compute(second),
        ),
      },
      states: const <String, FlowState>{
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: <String, FlowTransition>{
            'next': GotoFlowTransition('profile'),
          },
        ),
        'profile': ScreenFlowState(screen: 'profile', on: {}),
      },
    ),
    screenBlobs: <String, Uint8List>{
      'welcome': first,
      'profile': second,
    },
    cacheHit: false,
  );
}

RestageFlowController<FirstRunResult> _privacyController() {
  return RestageFlowController<FirstRunResult>(
    flow: firstRunFlowRef,
    resolver: StaticFlowResolver(_privacyFlow()),
    actions: null,
    onEvent: (_) {},
    onComplete: (_) {},
    onUnavailable: (_) {},
  );
}

RestageFlowController<FirstRunResult> _analyticsPrivacyController(
  ResolvedFlow flow,
) {
  return RestageFlowController<FirstRunResult>(
    flow: firstRunFlowRef,
    resolver: StaticFlowResolver(flow),
    actions: null,
    onEvent: Restage.fireEvent,
    onComplete: (_) {},
    onUnavailable: (_) {},
  );
}

AnalyticsEvent _mapCurrentRenderEvent(RestageEvent event) {
  return mapRestageEventToEnvelope(
    event,
    eventId: 'event-1',
    anonymousId: 'install-1',
    sessionId: 'session-1',
    appContext: _appContext,
    now: DateTime.utc(2026, 8, 27),
    omitAuthoredArguments: RestageRenderEventPrivacy.omitsAuthoredArguments,
  );
}

Map<String, Object?> _analyticsProjection(Map<String, Object?> event) {
  return <String, Object?>{
    'name': event['name'],
    'surface': event['surface'],
    'surfaceId': event['surfaceId'],
    'properties': event['properties'],
  };
}

Map<String, Object?> _presentationAttribution(Map<String, Object?> event) {
  const fields = <String>{
    'surface',
    'surfaceId',
    'surfaceVersion',
    'surfaceSessionId',
    'experimentId',
    'variantId',
    'experimentEpoch',
  };
  return <String, Object?>{
    for (final entry in event.entries)
      if (fields.contains(entry.key)) entry.key: entry.value,
  };
}

File _hostContextAnalyticsFixture() {
  return <File>[
    File('test/fixtures/host_context_analytics_events.json'),
    File('packages/restage/test/fixtures/host_context_analytics_events.json'),
  ].firstWhere((file) => file.existsSync());
}

Map<String, Object?> _fixtureProjection(String eventName) {
  final events = (jsonDecode(
    _hostContextAnalyticsFixture().readAsStringSync(),
  ) as List<Object?>)
      .cast<Map<String, Object?>>();
  return _analyticsProjection(
    events.singleWhere((event) => event['name'] == eventName),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> analyticsRequests;

  test('render event privacy remains restrictive in nested scopes', () {
    final observed = <bool>[];

    RestageRenderEventPrivacy.run<void>(
      mayExposeNonEmptyHostContext: true,
      body: () {
        observed.add(RestageRenderEventPrivacy.omitsAuthoredArguments);
        RestageRenderEventPrivacy.run<void>(
          mayExposeNonEmptyHostContext: false,
          body: () {
            observed.add(RestageRenderEventPrivacy.omitsAuthoredArguments);
          },
        );
        observed.add(RestageRenderEventPrivacy.omitsAuthoredArguments);
      },
    );

    expect(observed, <bool>[true, true, true]);
  });

  testWidgets('mounted callback uses its graph render privacy', (tester) async {
    final mapped = <({String flowId, Map<String, Object?> properties})>[];
    late StateSetter rebuildPrivateGraph;
    late StateSetter updateHost;
    late VoidCallback privateCallback;
    var includeEmptyGraph = false;

    void recordEvent({
      required String flowId,
      required bool mayExposeHostContext,
      required String eventId,
      required Object? value,
    }) {
      final fields = (value! as Map).cast<String, Object?>();
      final envelope = RestageRenderEventPrivacy.run(
        mayExposeNonEmptyHostContext: mayExposeHostContext,
        body: () => _mapCurrentRenderEvent(
          FlowCustomEvent(
            flowId: flowId,
            flowVersion: 1,
            eventName: eventId,
            fields: fields,
          ),
        ),
      );
      mapped.add((flowId: flowId, properties: envelope.properties));
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Row(
              children: <Widget>[
                RestageEventDispatcher(
                  onEvent: (eventId, value) => recordEvent(
                    flowId: _privateGraphFlow.id,
                    mayExposeHostContext: true,
                    eventId: eventId,
                    value: value,
                  ),
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuildPrivateGraph = setState;
                      privateCallback = surfaceEventWithContext(
                        context,
                        const SurfaceEvent<Map<String, Object?>>(
                          'selected_plan',
                        ),
                        const <String, Object?>{
                          'selection': 'private-selection',
                          'control': 'retained',
                        },
                      );
                      return const SizedBox();
                    },
                  ),
                ),
                if (includeEmptyGraph)
                  RestageEventDispatcher(
                    onEvent: (eventId, value) => recordEvent(
                      flowId: _emptyGraphFlow.id,
                      mayExposeHostContext: false,
                      eventId: eventId,
                      value: value,
                    ),
                    child: const SizedBox(),
                  ),
              ],
            );
          },
        ),
      ),
    );
    updateHost(() => includeEmptyGraph = true);
    await tester.pump();
    rebuildPrivateGraph(() {});
    await tester.pump();

    privateCallback();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(mapped, hasLength(1));
    expect(mapped.single.properties, <String, Object?>{
      'eventName': 'selected_plan',
    });
    expect(mapped.single.flowId, 'private_graph');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    FirstPaintLeaseTransaction.debugBeforeDescendantPaint = null;
    analyticsRequests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      analyticsRequests.add(request);
      return http.Response('', 200);
    });
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'http://127.0.0.1:1',
    );
  });

  tearDown(() {
    FirstPaintLeaseTransaction.debugBeforeDescendantPaint = null;
    Restage.debugReset();
  });

  Future<List<Map<String, Object?>>> flushAnalytics(
    WidgetTester tester,
  ) async {
    await tester.runAsync(pumpEventQueue);
    await tester.runAsync(Restage.debugFlushAnalytics);
    final requests = List<http.Request>.of(analyticsRequests);
    analyticsRequests.clear();
    return <Map<String, Object?>>[
      for (final request in requests)
        for (final event in (jsonDecode(request.body)
            as Map<String, Object?>)['events']! as List<Object?>)
          (event! as Map).cast<String, Object?>(),
    ];
  }

  Map<String, Object?> customEvent(
    List<Map<String, Object?>> events,
    String name,
  ) {
    return events.lastWhere((event) => event['name'] == name);
  }

  testWidgets(
      'a controller-fired event carries the render privacy of the '
      'presented content', (tester) async {
    final controller = RestagePaywallController();
    final localEvents = <PaywallCustomEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'controller-privacy-paywall',
          controller: controller,
          resolver: _BlobResolver(_paywallBlob()),
          context: const <String, Object?>{
            'secret': 'controller-private-value',
          },
          onEvent: (event) {
            if (event is PaywallCustomEvent) localEvents.add(event);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await flushAnalytics(tester);

    controller.fireEvent(
      'skipped',
      args: const <String, Object?>{'plan': 'controller-private-value'},
    );
    await tester.pump();
    final analyticsEvents = await flushAnalytics(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final envelope = customEvent(analyticsEvents, 'paywall_custom_event');
    // The host-facing callback keeps its arguments; only automatic analytics
    // redacts them.
    expect(localEvents.single.args, <String, Object?>{
      'plan': 'controller-private-value',
    });
    expect(envelope['properties'], <String, Object?>{'eventName': 'skipped'});
    expect(jsonEncode(envelope), isNot(contains('controller-private-value')));
  });

  testWidgets(
      'a controller-fired event keeps its arguments with no host '
      'render data', (tester) async {
    final controller = RestagePaywallController();

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'controller-open-paywall',
          controller: controller,
          resolver: _BlobResolver(_paywallBlob()),
          onEvent: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await flushAnalytics(tester);

    controller.fireEvent(
      'skipped',
      args: const <String, Object?>{'plan': 'annual'},
    );
    await tester.pump();
    final analyticsEvents = await flushAnalytics(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      customEvent(analyticsEvents, 'paywall_custom_event')['properties'],
      <String, Object?>{'eventName': 'skipped', 'plan': 'annual'},
    );
  });

  for (final catalog in _NativeCallbackCatalog.values) {
    testWidgets(
      '${catalog.name} callbacks retain capture privacy after withdrawal',
      (tester) async {
        if (catalog == _NativeCallbackCatalog.custom) {
          _registerNativeCallbackWidget();
        }
        final localEvents = <PaywallCustomEvent>[];
        final mapped = <AnalyticsEvent>[];
        Map<String, Object?>? hostContext = <String, Object?>{
          'secret': '${catalog.name}-private-value',
        };
        late StateSetter updateHost;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return RestagePaywall(
                  id: '${catalog.name}-callback',
                  resolver: _BlobResolver(_nativeCallbackBlob(catalog)),
                  context: hostContext,
                  onEvent: (event) {
                    if (event is! PaywallCustomEvent) return;
                    localEvents.add(event);
                    mapped.add(_mapCurrentRenderEvent(event));
                  },
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retained = _nativeCatalogCallback(tester, catalog);

        updateHost(() => hostContext = null);
        await tester.pump();
        retained();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(localEvents.single.args, <String, Object?>{
          'selection': '${catalog.name}-private-value',
          'control': 'retained',
          if (catalog == _NativeCallbackCatalog.custom) 'value': 'typed',
        });
        expect(mapped.single.properties, <String, Object?>{
          'eventName': 'selected_plan',
        });
      },
    );
  }

  for (final transition in _NativePrivacyTransition.values) {
    testWidgets(
      'paywall native callbacks combine ${transition.name} exposure',
      (tester) async {
        final localEvents = <PaywallCustomEvent>[];
        final mapped = <AnalyticsEvent>[];
        Map<String, Object?>? hostContext =
            transition == _NativePrivacyTransition.capturedPrivate
                ? <String, Object?>{'secret': 'paywall-private-value'}
                : null;
        late StateSetter updateHost;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return RestagePaywall(
                  id: 'native-paywall',
                  resolver: _BlobResolver(_paywallBlob()),
                  context: hostContext,
                  onEvent: (event) {
                    if (event is! PaywallCustomEvent) return;
                    localEvents.add(event);
                    mapped.add(_mapCurrentRenderEvent(event));
                  },
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = transition == _NativePrivacyTransition.capturedPrivate
            ? 'Select paywall plan'
            : 'Select without host data';
        final retained = _gestureCallback(tester, label);

        updateHost(() {
          hostContext = transition == _NativePrivacyTransition.capturedPrivate
              ? null
              : <String, Object?>{'secret': 'paywall-private-value'};
        });
        await tester.pump();
        retained();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(localEvents.single.args, <String, Object?>{
          if (transition == _NativePrivacyTransition.capturedPrivate)
            'selection': 'paywall-private-value',
          'control': 'retained',
        });
        expect(mapped.single.properties, <String, Object?>{
          'eventName': transition == _NativePrivacyTransition.capturedPrivate
              ? 'selected_plan'
              : 'control_only',
        });
      },
    );

    for (final view in _ControllerBackedView.values) {
      testWidgets(
        '${_controllerBackedViewToken(view)} native callbacks combine '
        '${transition.name} exposure',
        (tester) async {
          final localEvents = <FlowCustomEvent>[];
          final mapped = <AnalyticsEvent>[];
          final controller = RestageFlowController<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: StaticFlowResolver(
              _resolvedPrivacyFlow(
                transition == _NativePrivacyTransition.capturedPrivate
                    ? _flowBlob()
                    : _flowControlBlob(),
              ),
            ),
            actions: null,
            onEvent: (event) {
              if (event is! FlowCustomEvent) return;
              localEvents.add(event);
              mapped.add(_mapCurrentRenderEvent(event));
            },
            onComplete: (_) {},
            onUnavailable: (_) {},
          );
          addTearDown(controller.dispose);
          Map<String, Object?>? hostContext =
              transition == _NativePrivacyTransition.capturedPrivate
                  ? <String, Object?>{'secret': 'flow-private-value'}
                  : null;
          late StateSetter updateHost;

          await tester.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (context, setState) {
                  updateHost = setState;
                  return _controllerBackedView(
                    view,
                    controller: controller,
                    context: hostContext,
                  );
                },
              ),
            ),
          );
          unawaited(controller.load());
          await tester.pumpAndSettle();
          final retained = _gestureCallback(
            tester,
            transition == _NativePrivacyTransition.capturedPrivate
                ? 'Select flow plan'
                : 'Select flow control',
          );

          updateHost(() {
            hostContext = transition == _NativePrivacyTransition.capturedPrivate
                ? null
                : <String, Object?>{'secret': 'flow-private-value'};
          });
          await tester.pump();
          retained();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          expect(localEvents.single.fields, <String, Object?>{
            if (transition == _NativePrivacyTransition.capturedPrivate)
              'selection': 'flow-private-value',
            'control': 'retained',
          });
          expect(mapped.single.properties, <String, Object?>{
            'eventName': 'selected_plan',
          });
        },
      );
    }

    testWidgets(
      'standalone native callbacks combine ${transition.name} exposure',
      (tester) async {
        final schema = SurfaceScreenEventSchema(
          events: <SurfaceScreenEvent>[
            SurfaceScreenEvent(
              id: 'selected_plan',
              arguments: SurfaceScreenEventObjectArguments(
                const SurfaceScreenEventMapShapeV1(
                  SurfaceScreenEventScalarShapeV1(
                    SurfaceScreenEventScalarKind.jsonValue,
                  ),
                ),
              ),
            ),
          ],
        );
        final source = transition == _NativePrivacyTransition.capturedPrivate
            ? '''
import restage.core;

widget OnboardingScreen = GestureDetector(
  onTap: event "selected_plan" {
    selection: data.context.secret,
    control: "retained"
  },
  child: Text(text: "Select standalone native plan")
);
'''
            : '''
import restage.core;

widget OnboardingScreen = GestureDetector(
  onTap: event "selected_plan" { control: "retained" },
  child: Text(text: "Select standalone native plan")
);
''';
        final fixture = stringScreenFixture(
          surface: Surface.paywall,
          schema: schema,
          decoder: (_, arguments) => jsonEncode(arguments),
          blob: rfwSourceBlob(source),
        );
        final localValues = <Map<String, Object?>>[];
        final mapped = <AnalyticsEvent>[];
        final resolver = _HeldScreenResolver(fixture.bundled());
        Map<String, Object?>? hostContext =
            transition == _NativePrivacyTransition.capturedPrivate
                ? <String, Object?>{'secret': 'standalone-private-value'}
                : null;
        late StateSetter updateHost;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return RestageScreen<String>(
                  screen: fixture.ref,
                  resolver: resolver,
                  context: hostContext,
                  unavailable: const SurfaceScreenUnavailablePolicy.hide(),
                  onEvent: (value) {
                    final decoded =
                        (jsonDecode(value) as Map).cast<String, Object?>();
                    localValues.add(decoded);
                    mapped.add(
                      _mapCurrentRenderEvent(
                        PaywallCustomEvent(
                          paywallId: 'standalone-native',
                          eventName: 'selected_plan',
                          args: decoded,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retained =
            _gestureCallback(tester, 'Select standalone native plan');

        updateHost(() {
          hostContext = transition == _NativePrivacyTransition.capturedPrivate
              ? null
              : <String, Object?>{'secret': 'standalone-private-value'};
        });
        await tester.pump();
        retained();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        resolver.next.complete(fixture.bundled());

        expect(localValues.single, <String, Object?>{
          if (transition == _NativePrivacyTransition.capturedPrivate)
            'selection': 'standalone-private-value',
          'control': 'retained',
        });
        expect(mapped.single.properties, <String, Object?>{
          'eventName': 'selected_plan',
        });
      },
    );
  }

  testWidgets(
    'paywall events keep local arguments and isolate automatic analytics',
    (tester) async {
      final localEvents = <PaywallCustomEvent>[];
      Map<String, Object?>? hostContext = <String, Object?>{
        'secret': 'first-private-value',
      };
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestagePaywall(
                id: 'privacy-paywall',
                resolver: _BlobResolver(_paywallBlob()),
                context: hostContext,
                onEvent: (event) {
                  if (event is PaywallCustomEvent) localEvents.add(event);
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      final analyticsBatches = <List<Map<String, Object?>>>[];
      Future<void> tapAndCapture(String label) async {
        await tester.tap(find.text(label));
        await tester.pump();
        analyticsBatches.add(await flushAnalytics(tester));
      }

      await tapAndCapture('Select paywall plan');

      updateHost(() {
        hostContext = <String, Object?>{'secret': 'second-private-value'};
      });
      await tester.pump();
      await tapAndCapture('Select paywall plan');

      updateHost(() {
        hostContext = null;
      });
      await tester.pump();
      await tapAndCapture('Select without host data');

      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      await tapAndCapture('Select without host data');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final localArguments = <Map<String, Object?>>[
        for (final event in localEvents) Map<String, Object?>.of(event.args),
      ];
      final envelopes = <Map<String, Object?>>[
        for (final batch in analyticsBatches)
          customEvent(batch, 'paywall_custom_event'),
      ];
      final analyticsProperties = <Map<String, Object?>>[
        for (final envelope in envelopes)
          (envelope['properties']! as Map).cast<String, Object?>(),
      ];
      expect(localArguments.first, <String, Object?>{
        'selection': 'first-private-value',
        'control': 'retained',
      });
      expect(analyticsProperties.first, <String, Object?>{
        'eventName': 'selected_plan',
      });
      expect(
        _analyticsProjection(envelopes.first),
        _fixtureProjection('paywall_custom_event'),
      );
      expect(localArguments[1]['selection'], 'second-private-value');
      expect(analyticsProperties[1].containsKey('control'), isFalse);
      expect(localArguments[2]['control'], 'retained');
      expect(analyticsProperties[2], <String, Object?>{
        'eventName': 'control_only',
        'control': 'retained',
      });
      expect(
        analyticsProperties[3],
        <String, Object?>{
          'eventName': 'control_only',
          'control': 'retained',
        },
      );
    },
  );

  testWidgets(
    'flow-shaped paywall keeps local context out of automatic analytics',
    (tester) async {
      final localEvents = <PaywallCustomEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RestagePaywall(
            id: 'privacy-paywall',
            resolver: _FlowPayloadResolver(_paywallPrivacyFlow()),
            context: const <String, Object?>{
              'secret': 'hosted-paywall-private-value',
            },
            onEvent: (event) {
              if (event is PaywallCustomEvent) localEvents.add(event);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      await tester.tap(find.text('Select flow plan'));
      await tester.pump();
      final analyticsEvents = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final envelope = customEvent(analyticsEvents, 'paywall_custom_event');
      expect(localEvents.single.args, <String, Object?>{
        'selection': 'hosted-paywall-private-value',
        'control': 'retained',
      });
      expect(
        envelope['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
      expect(
        jsonEncode(envelope),
        isNot(contains('hosted-paywall-private-value')),
      );
    },
  );

  testWidgets(
      'a never-published paywall preserves authored analytics arguments',
      (tester) async {
    final localEvents = <PaywallCustomEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'privacy-paywall',
          resolver: _BlobResolver(_paywallBlob()),
          onEvent: (event) {
            if (event is PaywallCustomEvent) localEvents.add(event);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await flushAnalytics(tester);

    await tester.tap(find.text('Select without host data'));
    await tester.pump();
    final analyticsEvents = await flushAnalytics(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final envelope = customEvent(analyticsEvents, 'paywall_custom_event');
    final properties = (envelope['properties']! as Map).cast<String, Object?>();
    expect(localEvents.single.args['control'], 'retained');
    expect(
      properties,
      <String, Object?>{
        'eventName': 'control_only',
        'control': 'retained',
      },
    );
  });

  testWidgets(
    'blob-authored retained callbacks combine captured and live privacy',
    (tester) async {
      const label = 'Select retained blob';
      final callbacks = <String, VoidCallback>{};
      _registerLocalPaywallWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final localEvents = <PaywallCustomEvent>[];
      Map<String, Object?>? hostContext;
      final resolver = _BlobResolver(_localPaywallBlob(label: label));
      late StateSetter updateHost;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestagePaywall(
                id: 'retained-blob',
                resolver: resolver,
                context: hostContext,
                onEvent: (event) {
                  if (event is PaywallCustomEvent) localEvents.add(event);
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final emptyCapture = callbacks[label]!;
      final properties = <Map<String, Object?>>[];

      Future<void> invoke(VoidCallback callback) async {
        callback();
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'paywall_custom_event',
        );
        properties.add(
          (envelope['properties']! as Map).cast<String, Object?>(),
        );
      }

      await invoke(emptyCapture);
      updateHost(() {
        hostContext = <String, Object?>{'secret': 'retained-private-value'};
      });
      await tester.pump();
      final privateCapture = callbacks[label]!;
      await invoke(emptyCapture);
      updateHost(() => hostContext = null);
      await tester.pump();
      await invoke(privateCapture);
      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      await invoke(privateCapture);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        localEvents.map((event) => event.args).toList(),
        <Map<String, Object?>>[
          <String, Object?>{'control': 'retained'},
          <String, Object?>{'control': 'retained'},
          <String, Object?>{
            'selection': 'retained-private-value',
            'control': 'retained',
          },
          <String, Object?>{
            'selection': 'retained-private-value',
            'control': 'retained',
          },
        ],
      );
      expect(properties, <Map<String, Object?>>[
        <String, Object?>{
          'eventName': 'selected_plan',
          'control': 'retained',
        },
        <String, Object?>{'eventName': 'selected_plan'},
        <String, Object?>{'eventName': 'selected_plan'},
        <String, Object?>{'eventName': 'selected_plan'},
      ]);
    },
  );

  for (final route in <String>['asset', 'hosted']) {
    testWidgets('$route blobs keep authored callback attribution',
        (tester) async {
      final id = '$route-blob';
      final label = 'Select $route blob';
      final callbacks = <String, VoidCallback>{};
      _registerLocalPaywallWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final localEvents = <PaywallCustomEvent>[];
      final bytes = _localPaywallBlob(
        label: label,
        control: '$route-control',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RestagePaywall(
            id: id,
            resolver: _deliveryResolver(route, bytes),
            onEvent: (event) {
              if (event is PaywallCustomEvent) localEvents.add(event);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final presented = customEvent(
        await flushAnalytics(tester),
        'surface_presented',
      );

      callbacks[label]!();
      await tester.pump();

      final custom = localEvents.single;
      expect(custom.paywallId, id);
      expect(custom.args, <String, Object?>{
        'control': '$route-control',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final envelope = customEvent(
        await flushAnalytics(tester),
        'paywall_custom_event',
      );
      expect(
        _presentationAttribution(presented),
        <String, Object?>{
          'surface': 'paywall',
          'surfaceId': id,
          'surfaceVersion': route == 'asset' ? '1' : '7',
          'surfaceSessionId': isNotEmpty,
        },
      );
      expect(
        _presentationAttribution(envelope),
        _presentationAttribution(presented),
      );
      expect(envelope['properties'], <String, Object?>{
        'eventName': 'selected_plan',
        'control': '$route-control',
      });
    });
  }

  testWidgets('cached blobs bind callbacks to the restored presentation',
      (tester) async {
    const label = 'Select cached blob';
    final callbacks = <String, VoidCallback>{};
    _registerLocalPaywallWidget(
      onCallbackBuilt: (label, callback) => callbacks[label] = callback,
    );
    final resolver = _MutableBlobResolver(
      _localPaywallBlob(label: label, control: 'cached-control'),
    );
    final localEvents = <PaywallCustomEvent>[];

    Widget paywall(Key key) => MaterialApp(
          home: RestagePaywall(
            key: key,
            id: 'cached-blob',
            resolver: resolver,
            cacheLastRender: true,
            onEvent: (event) {
              if (event is PaywallCustomEvent) localEvents.add(event);
            },
          ),
        );

    await tester.pumpWidget(paywall(const ValueKey<String>('first')));
    await tester.pumpAndSettle();
    await flushAnalytics(tester);
    final replaced = callbacks[label]!;

    resolver.fails = true;
    await tester.pumpWidget(paywall(const ValueKey<String>('second')));
    await tester.pumpAndSettle();
    await flushAnalytics(tester);
    final restored = callbacks[label]!;
    expect(replaced, throwsAssertionError);
    restored();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final customEvents = (await flushAnalytics(tester))
        .where((event) => event['name'] == 'paywall_custom_event')
        .toList();

    expect(localEvents, hasLength(1));
    expect(localEvents.single.paywallId, 'cached-blob');
    expect(localEvents.single.args, <String, Object?>{
      'control': 'cached-control',
    });
    expect(customEvents, hasLength(1));
    expect(customEvents.single['surfaceId'], 'cached-blob');
  });

  testWidgets(
    'live refresh keeps current and pending blob callbacks exact',
    (tester) async {
      const currentLabel = 'Select current blob';
      const pendingLabel = 'Select pending blob';
      final callbacks = <String, VoidCallback>{};
      var checkPendingBuild = false;
      var pendingBuildChecked = false;
      Object? pendingBuildFailure;
      _registerLocalPaywallWidget(
        onCallbackBuilt: (label, callback) {
          callbacks[label] = callback;
          if (checkPendingBuild &&
              label == pendingLabel &&
              !pendingBuildChecked) {
            pendingBuildChecked = true;
            try {
              callback();
            } on Object catch (error) {
              pendingBuildFailure = error;
            }
          }
        },
      );
      final resolver = _MutableBlobResolver(
        _localPaywallBlob(
          label: currentLabel,
          control: 'current-control',
        ),
      );
      final localEvents = <PaywallCustomEvent>[];

      await tester.pumpWidget(
        MaterialApp(
          home: RestagePaywall(
            id: 'refresh-blob',
            resolver: resolver,
            onEvent: (event) {
              if (event is PaywallCustomEvent) localEvents.add(event);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final retained = callbacks[currentLabel]!;

      resolver
        ..bytes = _localPaywallBlob(
          label: pendingLabel,
          control: 'pending-control',
        )
        ..version = 2;
      checkPendingBuild = true;

      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      final promoted = callbacks[pendingLabel]!;

      expect(retained, throwsAssertionError);
      promoted();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(promoted, throwsAssertionError);
      await tester.pump();
      final customEvents = (await flushAnalytics(tester))
          .where((event) => event['name'] == 'paywall_custom_event')
          .toList();

      expect(pendingBuildChecked, isTrue);
      expect(pendingBuildFailure, isA<AssertionError>());
      expect(
        localEvents.map((event) => event.args['control']).toList(),
        <Object?>['pending-control'],
      );
      expect(customEvents, hasLength(1));
      expect(
        customEvents.map((event) => event['surfaceId']).toSet(),
        <Object?>{'refresh-blob'},
      );
    },
  );

  testWidgets(
    'simultaneous blob paywalls keep routing and privacy separate',
    (tester) async {
      const firstLabel = 'Select first blob';
      const secondLabel = 'Select second blob';
      final callbacks = <String, VoidCallback>{};
      _registerLocalPaywallWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final firstEvents = <PaywallCustomEvent>[];
      final secondEvents = <PaywallCustomEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              RestagePaywall(
                id: 'first-blob',
                resolver: _BlobResolver(
                  _localPaywallBlob(
                    label: firstLabel,
                    control: 'first-control',
                    stateful: true,
                  ),
                ),
                context: const <String, Object?>{
                  'secret': 'first-private-value',
                },
                onEvent: (event) {
                  if (event is PaywallCustomEvent) firstEvents.add(event);
                },
              ),
              RestagePaywall(
                id: 'second-blob',
                resolver: _BlobResolver(
                  _localPaywallBlob(
                    label: secondLabel,
                    control: 'second-control',
                    stateful: true,
                  ),
                ),
                onEvent: (event) {
                  if (event is PaywallCustomEvent) secondEvents.add(event);
                },
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final first = callbacks[firstLabel]!;
      final second = callbacks[secondLabel]!;

      first();
      second();
      await tester.pump();

      expect(firstEvents.single.paywallId, 'first-blob');
      expect(firstEvents.single.args, <String, Object?>{
        'selection': 'first-private-value',
        'control': 'first-control',
      });
      expect(secondEvents.single.paywallId, 'second-blob');
      expect(secondEvents.single.args, <String, Object?>{
        'control': 'second-control',
      });

      firstEvents.clear();
      secondEvents.clear();
      await tester.tap(find.text('Rebuild $firstLabel: 0'));
      await tester.pump();
      callbacks[firstLabel]!();
      second();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final analyticsEvents = (await flushAnalytics(tester))
          .where((event) => event['name'] == 'paywall_custom_event')
          .toList();

      expect(firstEvents, hasLength(1));
      expect(firstEvents.single.paywallId, 'first-blob');
      expect(firstEvents.single.args, <String, Object?>{
        'selection': 'first-private-value',
        'control': 'first-control',
      });
      expect(secondEvents, hasLength(1));
      expect(secondEvents.single.paywallId, 'second-blob');
      expect(secondEvents.single.args, <String, Object?>{
        'control': 'second-control',
      });
      expect(analyticsEvents, hasLength(4));
      final firstEnvelopes = analyticsEvents
          .where((event) => event['surfaceId'] == 'first-blob')
          .toList();
      final secondEnvelopes = analyticsEvents
          .where((event) => event['surfaceId'] == 'second-blob')
          .toList();
      expect(firstEnvelopes, hasLength(2));
      for (final envelope in firstEnvelopes) {
        expect(envelope['properties'], <String, Object?>{
          'eventName': 'selected_plan',
        });
      }
      expect(secondEnvelopes, hasLength(2));
      for (final envelope in secondEnvelopes) {
        expect(envelope['properties'], <String, Object?>{
          'eventName': 'selected_plan',
          'control': 'second-control',
        });
      }
    },
  );

  testWidgets('flow events keep local fields and isolate automatic analytics',
      (tester) async {
    final localEvents = <FlowCustomEvent>[];
    final subscription = Restage.events.listen((event) {
      if (event is FlowCustomEvent) localEvents.add(event);
    });
    addTearDown(subscription.cancel);

    await tester.pumpWidget(
      MaterialApp(
        home: RestageFlowGraph<FirstRunResult>(
          flow: firstRunFlowRef,
          resolver: StaticFlowResolver(_privacyFlow()),
          context: const <String, Object?>{
            'secret': 'flow-private-value',
          },
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await flushAnalytics(tester);

    await tester.tap(find.text('Select flow plan'));
    await tester.pump();
    final analyticsEvents = await flushAnalytics(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final envelope = customEvent(analyticsEvents, 'flow_custom_event');
    final localFields = Map<String, Object?>.of(localEvents.single.fields);
    final properties = (envelope['properties']! as Map).cast<String, Object?>();
    final projection = _analyticsProjection(envelope);
    expect(localFields, <String, Object?>{
      'selection': 'flow-private-value',
      'control': 'retained',
    });
    expect(properties, <String, Object?>{
      'eventName': 'selected_plan',
    });
    expect(
      projection,
      _fixtureProjection('flow_custom_event'),
    );
  });

  testWidgets(
    'registered and direct flow events share live context privacy',
    (tester) async {
      _registerLocalPrivacyWidget();
      final resolver = StaticFlowResolver(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      Map<String, Object?>? hostContext;
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageFlowGraph<FirstRunResult>(
                flow: firstRunFlowRef,
                resolver: resolver,
                context: hostContext,
                unavailable: const FlowUnavailablePolicy.hide(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      Future<List<Map<String, Object?>>> tapBoth() async {
        final properties = <Map<String, Object?>>[];
        for (final label in <String>[
          'Select direct plan',
          'Select local plan',
        ]) {
          await tester.tap(find.text(label));
          await tester.pump();
          final events = await flushAnalytics(tester);
          final envelope = customEvent(events, 'flow_custom_event');
          properties.add(
            (envelope['properties']! as Map).cast<String, Object?>(),
          );
        }
        return properties;
      }

      final neverPublished = await tapBoth();
      updateHost(() {
        hostContext = <String, Object?>{'secret': 'private-selection'};
      });
      await tester.pump();
      final nonEmpty = await tapBoth();
      updateHost(() => hostContext = null);
      await tester.pump();
      final withdrawn = await tapBoth();
      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      final knownEmpty = await tapBoth();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(localEvents, hasLength(8));
      for (final index in <int>[0, 1, 4, 5, 6, 7]) {
        expect(localEvents[index].fields, <String, Object?>{
          'control': 'retained',
        });
      }
      for (final index in <int>[2, 3]) {
        expect(localEvents[index].fields, <String, Object?>{
          'selection': 'private-selection',
          'control': 'retained',
        });
      }
      for (final properties in <List<Map<String, Object?>>>[
        neverPublished,
        withdrawn,
        knownEmpty,
      ]) {
        expect(properties, <Map<String, Object?>>[
          <String, Object?>{
            'eventName': 'selected_plan',
            'fields': <String, Object?>{'control': 'retained'},
          },
          <String, Object?>{
            'eventName': 'selected_plan',
            'fields': <String, Object?>{'control': 'retained'},
          },
        ]);
      }
      expect(nonEmpty, <Map<String, Object?>>[
        <String, Object?>{'eventName': 'selected_plan'},
        <String, Object?>{'eventName': 'selected_plan'},
      ]);
    },
  );

  testWidgets(
    'context-free graph callbacks use current content privacy',
    (tester) async {
      _registerLocalPrivacyWidget(contextFree: true);
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      Map<String, Object?> hostContext = <String, Object?>{
        'secret': 'graph-private-value',
      };
      final resolver = StaticFlowResolver(_localPrivacyFlow());
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageFlowGraph<FirstRunResult>(
                flow: firstRunFlowRef,
                resolver: resolver,
                context: hostContext,
                unavailable: const FlowUnavailablePolicy.hide(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      await tester.tap(find.text('Select local plan'));
      await tester.pump();
      final privateEnvelope = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );

      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      await tester.tap(find.text('Select local plan'));
      await tester.pump();
      final emptyEnvelope = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'graph-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
      ]);
      expect(
        privateEnvelope['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
      expect(emptyEnvelope['properties'], <String, Object?>{
        'eventName': 'selected_plan',
        'fields': <String, Object?>{'control': 'retained'},
      });
    },
  );

  testWidgets(
    'graph retained callbacks cannot weaken captured context privacy',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      final resolver = StaticFlowResolver(_localPrivacyFlow());
      Map<String, Object?>? hostContext = <String, Object?>{
        'secret': 'graph-retained-private-value',
      };
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageFlowGraph<FirstRunResult>(
                flow: firstRunFlowRef,
                resolver: resolver,
                context: hostContext,
                unavailable: const FlowUnavailablePolicy.hide(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final retained = callbacks['Select local plan']!;

      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      retained();
      await tester.pump();
      final envelope = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );

      expect(localEvents.single.fields, <String, Object?>{
        'selection': 'graph-retained-private-value',
        'control': 'retained',
      });
      expect(
        envelope['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
    },
  );

  testWidgets(
    'controller view composition applies live privacy to authored events',
    (tester) async {
      _registerLocalPrivacyWidget();
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);
      Map<String, Object?>? hostContext = <String, Object?>{
        'secret': 'lower-level-private-value',
      };
      late StateSetter updateHost;

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageFlowView<FirstRunResult>(
                  controller: controller,
                  context: hostContext,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      Future<Map<String, Object?>> tap() async {
        await tester.tap(find.text('Select local plan'));
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'flow_custom_event',
        );
        return (envelope['properties']! as Map).cast<String, Object?>();
      }

      final nonEmpty = await tap();
      updateHost(() => hostContext = null);
      await tester.pump();
      final withdrawn = await tap();
      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      final knownEmpty = await tap();

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'lower-level-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
        <String, Object?>{'control': 'retained'},
      ]);
      expect(nonEmpty, <String, Object?>{'eventName': 'selected_plan'});
      for (final properties in <Map<String, Object?>>[
        withdrawn,
        knownEmpty,
      ]) {
        expect(properties, <String, Object?>{
          'eventName': 'selected_plan',
          'fields': <String, Object?>{'control': 'retained'},
        });
      }
    },
  );

  for (final view in _ControllerBackedView.values) {
    for (final binding in _AuthoredHelperBinding.values) {
      for (final handlerShape in _OwnerHandlerShape.values) {
        final viewToken = _controllerBackedViewToken(view);
        final bindingLabel = _authoredHelperBindingLabel(binding);
        final handlerShapeLabel = _ownerHandlerShapeLabel(handlerShape);
        final privateValue =
            'owner-local-$viewToken-$bindingLabel-$handlerShapeLabel-private-value';

        testWidgets(
          '$viewToken $bindingLabel refuses an unassociated '
          '$handlerShapeLabel handler',
          (tester) async {
            final callbacks = <String, VoidCallback>{};
            final routed = <({String controller, Object? value})>[];
            _registerLocalPrivacyWidget(
              contextFree: binding == _AuthoredHelperBinding.contextFree,
              onCallbackBuilt: (label, callback) {
                callbacks[label] = callback;
              },
            );

            RestageFlowController<FirstRunResult> createController(
              String name,
            ) {
              return RestageFlowController<FirstRunResult>(
                flow: firstRunFlowRef,
                resolver: StaticFlowResolver(_localPrivacyFlow()),
                actions: null,
                onEvent: (event) {
                  if (event is FlowCustomEvent) {
                    routed.add((controller: name, value: event.fields));
                  }
                },
                onComplete: (_) {},
                onUnavailable: (_) {},
              );
            }

            final mounted = createController('mounted');
            final other = createController('other');
            addTearDown(mounted.dispose);
            addTearDown(other.dispose);
            unawaited(mounted.load());
            unawaited(other.load());

            final SurfaceEventHandler ownerHandler = switch (handlerShape) {
              _OwnerHandlerShape.wrongController => other.handleEvent,
              _OwnerHandlerShape.forwarding => (eventId, value) =>
                  mounted.handleEvent(eventId, value),
            };

            await tester.pumpWidget(
              MaterialApp(
                home: RestageEventDispatcher(
                  onEvent: ownerHandler,
                  child: _controllerBackedView(
                    view,
                    controller: mounted,
                    context: <String, Object?>{'secret': privateValue},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            Object? failure;
            try {
              callbacks['Select local plan']!();
            } on Object catch (error) {
              failure = error;
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();

            expect(routed, isEmpty);
            expect(jsonEncode(routed), isNot(contains(privateValue)));
            expect(failure, isA<AssertionError>());
          },
        );
      }
    }
  }

  for (final view in _ControllerBackedView.values) {
    testWidgets(
      '${_controllerBackedViewLabel(view)} admits a matching nested dispatcher',
      (tester) async {
        final controller = _analyticsPrivacyController(_localPrivacyFlow());
        final nestedHandler = ValueNotifier<SurfaceEventHandler?>(
          controller.handleEvent,
        );
        _registerLocalPrivacyWidget(
          nestedDispatcherHandler: nestedHandler,
        );
        final localEvents = <FlowCustomEvent>[];
        final subscription = Restage.events.listen((event) {
          if (event is FlowCustomEvent) localEvents.add(event);
        });
        addTearDown(subscription.cancel);
        addTearDown(nestedHandler.dispose);
        addTearDown(controller.dispose);

        unawaited(controller.load());
        await tester.pumpWidget(
          MaterialApp(
            home: RestageEventDispatcher(
              onEvent: controller.handleEvent,
              child: _controllerBackedView(
                view,
                controller: controller,
                context: const <String, Object?>{
                  'secret': 'nested-private-value',
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await flushAnalytics(tester);

        await tester.tap(find.text('Select local plan'));
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'flow_custom_event',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(localEvents.single.fields, <String, Object?>{
          'selection': 'nested-private-value',
          'control': 'retained',
        });
        expect(
          envelope['properties'],
          <String, Object?>{'eventName': 'selected_plan'},
        );
      },
    );
  }

  testWidgets(
    'nested dispatch refuses a different controller handler',
    (tester) async {
      final routed = <({String controller, Map<String, Object?> fields})>[];
      RestageFlowController<FirstRunResult> createController(String name) =>
          RestageFlowController<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: StaticFlowResolver(_localPrivacyFlow()),
            actions: null,
            onEvent: (event) {
              if (event is FlowCustomEvent) {
                routed.add((controller: name, fields: event.fields));
              }
            },
            onComplete: (_) {},
            onUnavailable: (_) {},
          );

      final first = createController('first');
      final second = createController('second');
      final nestedHandler = ValueNotifier<SurfaceEventHandler?>(
        second.handleEvent,
      );
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        nestedDispatcherHandler: nestedHandler,
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      addTearDown(nestedHandler.dispose);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      unawaited(first.load());
      unawaited(second.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: first.handleEvent,
            child: RestageFlowView<FirstRunResult>(
              controller: first,
              context: const <String, Object?>{
                'secret': 'wrong-handler-private-value',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Object? failure;
      try {
        callbacks['Select local plan']!();
      } on Object catch (error) {
        failure = error;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(failure, isA<AssertionError>());
      expect(routed, isEmpty);
      expect(
          jsonEncode(routed), isNot(contains('wrong-handler-private-value')));
    },
  );

  testWidgets(
    'nested dispatch refuses an unassociated forwarding handler',
    (tester) async {
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final callbacks = <String, VoidCallback>{};
      final nestedHandler = ValueNotifier<SurfaceEventHandler?>(
        (eventId, value) => controller.handleEvent(eventId, value),
      );
      _registerLocalPrivacyWidget(
        nestedDispatcherHandler: nestedHandler,
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(nestedHandler.dispose);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: controller.handleEvent,
            child: RestageFlowView<FirstRunResult>(
              controller: controller,
              context: const <String, Object?>{
                'secret': 'unassociated-nested-private-value',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Object? failure;
      try {
        callbacks['Select local plan']!();
      } on Object catch (error) {
        failure = error;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(failure, isA<AssertionError>());
      expect(localEvents, isEmpty);
      expect(
        jsonEncode(<Object?>[localEvents]),
        isNot(contains('unassociated-nested-private-value')),
      );
    },
  );

  testWidgets(
    'retained nested callback refuses a replacement handler',
    (tester) async {
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final callbacks = <VoidCallback>[];
      final nestedHandler = ValueNotifier<SurfaceEventHandler?>(
        controller.handleEvent,
      );
      _registerLocalPrivacyWidget(
        nestedDispatcherHandler: nestedHandler,
        onCallbackBuilt: (_, callback) => callbacks.add(callback),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(nestedHandler.dispose);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: controller.handleEvent,
            child: RestageScreenView<FirstRunResult>(
              controller: controller,
              context: const <String, Object?>{
                'secret': 'stale-nested-private-value',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final retained = callbacks.last;

      nestedHandler.value =
          (eventId, value) => controller.handleEvent(eventId, value);
      await tester.pump();
      expect(retained, throwsAssertionError);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        jsonEncode(localEvents.map((event) => event.fields).toList()),
        isNot(contains('stale-nested-private-value')),
      );
      expect(localEvents, isEmpty);
    },
  );

  testWidgets(
    'flow graph admits its controller handler under a nested dispatcher',
    (tester) async {
      final nestedHandler = ValueNotifier<SurfaceEventHandler?>(null);
      _registerLocalPrivacyWidget(
        nestedDispatcherHandler: nestedHandler,
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(nestedHandler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: RestageFlowGraph<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: StaticFlowResolver(_localPrivacyFlow()),
            context: const <String, Object?>{
              'secret': 'nested-graph-private-value',
            },
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final controller = tester
          .widget<RestageFlowView<FirstRunResult>>(
            find.byType(RestageFlowView<FirstRunResult>),
          )
          .controller;
      nestedHandler.value = controller.handleEvent;
      await tester.pump();

      await tester.tap(find.text('Select local plan'));
      await tester.pump();
      final envelope = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(localEvents.single.fields, <String, Object?>{
        'selection': 'nested-graph-private-value',
        'control': 'retained',
      });
      expect(
        envelope['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
    },
  );

  test('explicit handler association admits its exact registered owner', () {
    final controller = Object();
    final owner = Object();
    final registration = Object();
    final association = Object();
    final routed = <Object?>[];
    void directHandler(String eventId, Object? value) {}
    void wrapperHandler(String eventId, Object? value) => routed.add(value);

    RestageFlowRenderEventPrivacyRegistry.register(
      controller: controller,
      owner: owner,
      registration: registration,
      contentToken: 'graph-content',
      associatedHandler: directHandler,
      isCurrent: () => true,
      mayExposeNonEmptyHostContext: () => true,
    );
    RestageFlowRenderEventPrivacyRegistry.registerHandlerAssociation(
      controller: controller,
      owner: owner,
      association: association,
      handler: wrapperHandler,
      isCurrent: () => true,
    );
    addTearDown(() {
      RestageFlowRenderEventPrivacyRegistry.unregisterHandlerAssociation(
        owner: owner,
        association: association,
      );
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: controller,
        owner: owner,
        registration: registration,
      );
    });

    final dispatcher =
        RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: owner,
      binding: RestageFlowRenderEventPrivacyBinding(
        controller: controller,
        registration: registration,
      ),
      handler: wrapperHandler,
      dispatcherIsActive: () => true,
      handlerIsCurrent: () => true,
      invokeWithOwner: (body) => body(),
    );
    dispatcher?.call('selected_plan', 'graph-association-private-value');

    expect(dispatcher, isNotNull);
    expect(routed, <Object?>['graph-association-private-value']);
  });

  test('explicit handler association cannot cross registered owners', () {
    final controller = Object();
    final firstOwner = Object();
    final secondOwner = Object();
    final firstRegistration = Object();
    final secondRegistration = Object();
    final association = Object();
    final routed = <Object?>[];
    void directHandler(String eventId, Object? value) {}
    void wrapperHandler(String eventId, Object? value) => routed.add(value);

    for (final entry in <({Object owner, Object registration})>[
      (owner: firstOwner, registration: firstRegistration),
      (owner: secondOwner, registration: secondRegistration),
    ]) {
      RestageFlowRenderEventPrivacyRegistry.register(
        controller: controller,
        owner: entry.owner,
        registration: entry.registration,
        contentToken: 'shared-content',
        associatedHandler: directHandler,
        isCurrent: () => true,
        mayExposeNonEmptyHostContext: () => true,
      );
      addTearDown(
        () => RestageFlowRenderEventPrivacyRegistry.unregister(
          controller: controller,
          owner: entry.owner,
          registration: entry.registration,
        ),
      );
    }
    RestageFlowRenderEventPrivacyRegistry.registerHandlerAssociation(
      controller: controller,
      owner: firstOwner,
      association: association,
      handler: wrapperHandler,
      isCurrent: () => true,
    );
    addTearDown(
      () => RestageFlowRenderEventPrivacyRegistry.unregisterHandlerAssociation(
        owner: firstOwner,
        association: association,
      ),
    );

    final exact = RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: firstOwner,
      binding: RestageFlowRenderEventPrivacyBinding(
        controller: controller,
        registration: firstRegistration,
      ),
      handler: wrapperHandler,
      dispatcherIsActive: () => true,
      handlerIsCurrent: () => true,
      invokeWithOwner: (body) => body(),
    );
    final crossOwner =
        RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: secondOwner,
      binding: RestageFlowRenderEventPrivacyBinding(
        controller: controller,
        registration: secondRegistration,
      ),
      handler: wrapperHandler,
      dispatcherIsActive: () => true,
      handlerIsCurrent: () => true,
      invokeWithOwner: (body) => body(),
    );
    exact?.call('selected_plan', 'exact-owner-graph-private-value');
    crossOwner?.call('selected_plan', 'cross-owner-graph-private-value');

    expect(exact, isNotNull);
    expect(routed, <Object?>['exact-owner-graph-private-value']);
    expect(crossOwner, isNull);
    expect(
      jsonEncode(routed),
      isNot(contains('cross-owner-graph-private-value')),
    );
  });

  test('retained callbacks pin the exact handler association', () {
    final controller = Object();
    final owner = Object();
    final registration = Object();
    final firstAssociation = Object();
    final secondAssociation = Object();
    final routed = <Object?>[];
    void directHandler(String eventId, Object? value) {}
    void wrapperHandler(String eventId, Object? value) => routed.add(value);

    RestageFlowRenderEventPrivacyRegistry.register(
      controller: controller,
      owner: owner,
      registration: registration,
      contentToken: 'graph-content',
      associatedHandler: directHandler,
      isCurrent: () => true,
      mayExposeNonEmptyHostContext: () => true,
    );
    RestageFlowRenderEventPrivacyRegistry.registerHandlerAssociation(
      controller: controller,
      owner: owner,
      association: firstAssociation,
      handler: wrapperHandler,
      isCurrent: () => true,
    );
    addTearDown(() {
      RestageFlowRenderEventPrivacyRegistry.unregisterHandlerAssociation(
        owner: owner,
        association: firstAssociation,
      );
      RestageFlowRenderEventPrivacyRegistry.unregisterHandlerAssociation(
        owner: owner,
        association: secondAssociation,
      );
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: controller,
        owner: owner,
        registration: registration,
      );
    });

    SurfaceEventHandler? bind() =>
        RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
          owner: owner,
          binding: RestageFlowRenderEventPrivacyBinding(
            controller: controller,
            registration: registration,
          ),
          handler: wrapperHandler,
          dispatcherIsActive: () => true,
          handlerIsCurrent: () => true,
          invokeWithOwner: (body) => body(),
        );

    final retained = bind();
    RestageFlowRenderEventPrivacyRegistry.unregisterHandlerAssociation(
      owner: owner,
      association: firstAssociation,
    );
    RestageFlowRenderEventPrivacyRegistry.registerHandlerAssociation(
      controller: controller,
      owner: owner,
      association: secondAssociation,
      handler: wrapperHandler,
      isCurrent: () => true,
    );
    final refreshed = bind();

    retained?.call('selected_plan', 'stale-graph-association-private-value');
    refreshed?.call(
      'selected_plan',
      'refreshed-graph-association-private-value',
    );

    expect(retained, isNotNull);
    expect(refreshed, isNotNull);
    expect(routed, <Object?>['refreshed-graph-association-private-value']);
    expect(
      jsonEncode(routed),
      isNot(contains('stale-graph-association-private-value')),
    );
  });

  test('exact registration ambiguity refuses nested dispatch', () {
    final controller = Object();
    final registration = Object();
    final firstOwner = Object();
    final secondOwner = Object();
    final nestedOwner = Object();
    final routed = <Object?>[];
    void handler(String eventId, Object? value) => routed.add(value);

    for (final owner in <Object>[firstOwner, secondOwner]) {
      RestageFlowRenderEventPrivacyRegistry.register(
        controller: controller,
        owner: owner,
        registration: registration,
        contentToken: 'current-content',
        associatedHandler: handler,
        isCurrent: () => true,
        mayExposeNonEmptyHostContext: () => true,
      );
      addTearDown(
        () => RestageFlowRenderEventPrivacyRegistry.unregister(
          controller: controller,
          owner: owner,
          registration: registration,
        ),
      );
    }

    final dispatcher =
        RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: nestedOwner,
      binding: RestageFlowRenderEventPrivacyBinding(
        controller: controller,
        registration: registration,
      ),
      handler: handler,
      dispatcherIsActive: () => true,
      handlerIsCurrent: () => true,
      invokeWithOwner: (body) => body(),
    );
    dispatcher?.call(
      'selected_plan',
      const <String, Object?>{
        'selection': 'ambiguous-nested-private-value',
      },
    );

    expect(
      jsonEncode(routed),
      isNot(contains('ambiguous-nested-private-value')),
    );
    expect(dispatcher, isNull);
    expect(routed, isEmpty);
  });

  test('registered nested owner cannot borrow an exact registration', () {
    final controller = Object();
    final nestedController = Object();
    final registration = Object();
    final nestedRegistration = Object();
    final exactOwner = Object();
    final nestedOwner = Object();
    final routed = <Object?>[];
    void handler(String eventId, Object? value) => routed.add(value);

    RestageFlowRenderEventPrivacyRegistry.register(
      controller: controller,
      owner: exactOwner,
      registration: registration,
      contentToken: 'exact-content',
      associatedHandler: handler,
      isCurrent: () => true,
      mayExposeNonEmptyHostContext: () => true,
    );
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: nestedController,
      owner: nestedOwner,
      registration: nestedRegistration,
      contentToken: 'nested-content',
      associatedHandler: handler,
      isCurrent: () => true,
      mayExposeNonEmptyHostContext: () => false,
    );
    addTearDown(() {
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: controller,
        owner: exactOwner,
        registration: registration,
      );
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: nestedController,
        owner: nestedOwner,
        registration: nestedRegistration,
      );
    });

    final dispatcher =
        RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: nestedOwner,
      binding: RestageFlowRenderEventPrivacyBinding(
        controller: controller,
        registration: registration,
      ),
      handler: handler,
      dispatcherIsActive: () => true,
      handlerIsCurrent: () => true,
      invokeWithOwner: (body) => body(),
    );
    dispatcher?.call(
      'selected_plan',
      const <String, Object?>{
        'selection': 'cross-owner-nesting-private-value',
      },
    );

    expect(dispatcher, isNull);
    expect(routed, isEmpty);
  });

  test('stale exact registration cannot borrow a different owner', () {
    final controller = Object();
    final staleRegistration = Object();
    final currentRegistration = Object();
    final staleOwner = Object();
    final currentOwner = Object();
    final nestedOwner = Object();
    final routed = <Object?>[];
    void handler(String eventId, Object? value) => routed.add(value);

    RestageFlowRenderEventPrivacyRegistry.register(
      controller: controller,
      owner: currentOwner,
      registration: currentRegistration,
      contentToken: 'current-content',
      associatedHandler: handler,
      isCurrent: () => true,
      mayExposeNonEmptyHostContext: () => false,
    );
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: controller,
      owner: staleOwner,
      registration: staleRegistration,
      contentToken: 'current-content',
      associatedHandler: handler,
      isCurrent: () => false,
      mayExposeNonEmptyHostContext: () => true,
    );
    addTearDown(() {
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: controller,
        owner: staleOwner,
        registration: staleRegistration,
      );
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: controller,
        owner: currentOwner,
        registration: currentRegistration,
      );
    });

    final dispatcher =
        RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: nestedOwner,
      binding: RestageFlowRenderEventPrivacyBinding(
        controller: controller,
        registration: staleRegistration,
      ),
      handler: handler,
      dispatcherIsActive: () => true,
      handlerIsCurrent: () => true,
      invokeWithOwner: (body) => body(),
    );
    dispatcher?.call(
      'selected_plan',
      const <String, Object?>{
        'selection': 'cross-owner-private-value',
      },
    );

    expect(
      jsonEncode(routed),
      isNot(contains('cross-owner-private-value')),
    );
    expect(dispatcher, isNull);
    expect(routed, isEmpty);
  });

  testWidgets(
    'a sibling dispatcher with the exact controller handler is admitted',
    (tester) async {
      _registerLocalPrivacyWidget(contextFree: true);
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);
      Map<String, Object?> hostContext = <String, Object?>{
        'secret': 'sibling-private-value',
      };
      late StateSetter updateHost;

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Column(
                children: <Widget>[
                  RestageEventDispatcher(
                    onEvent: controller.handleEvent,
                    child: const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: RestageFlowView<FirstRunResult>(
                      controller: controller,
                      context: hostContext,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      await tester.tap(find.text('Select local plan'));
      await tester.pump();
      final privateEnvelope = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );

      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      await tester.tap(find.text('Select local plan'));
      await tester.pump();
      final emptyEnvelope = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'sibling-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
      ]);
      expect(
        jsonEncode(privateEnvelope),
        isNot(contains('sibling-private-value')),
      );
      expect(
        privateEnvelope['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
      expect(emptyEnvelope['properties'], <String, Object?>{
        'eventName': 'selected_plan',
        'fields': <String, Object?>{'control': 'retained'},
      });
    },
  );

  testWidgets(
    'a sibling dispatcher with an unprovable handler refuses flow content',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
        contextFree: true,
      );
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              RestageEventDispatcher(
                onEvent: (eventId, value) {
                  controller.handleEvent(eventId, value);
                },
                child: const SizedBox.shrink(),
              ),
              Expanded(
                child: RestageFlowView<FirstRunResult>(
                  controller: controller,
                  context: const <String, Object?>{
                    'secret': 'unprovable-sibling-private-value',
                  },
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      Object? failure;
      try {
        callbacks['Select local plan']!();
      } on Object catch (error) {
        failure = error;
      }
      await tester.pump();
      final analytics = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        jsonEncode(<Map<String, Object?>>[
          for (final event in localEvents) event.fields,
        ]),
        isNot(contains('unprovable-sibling-private-value')),
      );
      expect(
        jsonEncode(analytics),
        isNot(contains('unprovable-sibling-private-value')),
      );
      expect(failure, isA<AssertionError>());
      expect(localEvents, isEmpty);
      expect(
        analytics.where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'callbacks captured before a view mounts cannot gain authority',
    (tester) async {
      _registerLocalPrivacyWidget();
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);
      VoidCallback? retained;
      VoidCallback? afterUnmount;
      late StateSetter updateHost;
      var showView = false;
      var captureAfterUnmount = false;

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: controller.handleEvent,
            child: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return Column(
                  children: <Widget>[
                    Builder(
                      builder: (context) {
                        final callback = surfaceEventWithContext(
                          context,
                          const SurfaceEvent<Map<String, Object?>>(
                            'selected_plan',
                          ),
                          const <String, Object?>{
                            'selection': 'pre-registration-private-value',
                            'control': 'retained',
                          },
                        );
                        retained ??= callback;
                        if (captureAfterUnmount) afterUnmount = callback;
                        return const SizedBox.shrink();
                      },
                    ),
                    if (showView)
                      Expanded(
                        child: RestageFlowView<FirstRunResult>(
                          controller: controller,
                          context: const <String, Object?>{
                            'secret': 'mounted-private-value',
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      updateHost(() => showView = true);
      await tester.pumpAndSettle();
      expect(retained!, throwsAssertionError);
      await tester.pump();
      final mountedAnalytics = await flushAnalytics(tester);

      updateHost(() => showView = false);
      await tester.pumpAndSettle();
      expect(retained!, throwsAssertionError);
      updateHost(() => captureAfterUnmount = true);
      await tester.pump();
      final failures = <Object>[];
      try {
        afterUnmount!();
      } on Object catch (error) {
        failures.add(error);
      }
      await tester.pump();
      final unmountedAnalytics = await flushAnalytics(tester);

      updateHost(() => showView = true);
      await tester.pumpAndSettle();
      expect(retained!, throwsAssertionError);
      await tester.pump();
      final remountedAnalytics = await flushAnalytics(tester);

      expect(localEvents.map((event) => event.fields), isEmpty);
      expect(
        <Map<String, Object?>>[
          ...mountedAnalytics,
          ...unmountedAnalytics,
          ...remountedAnalytics,
        ].where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
      expect(failures, hasLength(1));
      expect(failures.single, isA<AssertionError>());
    },
  );

  testWidgets(
    'controller view callbacks refuse after a controller swap or disposal',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final first = _analyticsPrivacyController(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select first controller',
            control: 'first-control',
          ),
        ),
      );
      final second = _analyticsPrivacyController(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select second controller',
            control: 'second-control',
          ),
        ),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      late StateSetter updateHost;
      var active = first;

      unawaited(first.load());
      unawaited(second.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              final controller = active;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageFlowView<FirstRunResult>(
                  key: const ValueKey<String>('swappable-view'),
                  controller: controller,
                  context: const <String, Object?>{
                    'secret': 'private-value',
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final staleFirst = callbacks['Select first controller']!;

      updateHost(() => active = second);
      await tester.pump();
      expect(staleFirst, throwsAssertionError);
      callbacks['Select second controller']!();
      await tester.pump();
      final routed = await flushAnalytics(tester);
      final staleSecond = callbacks['Select second controller']!;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(staleSecond, throwsAssertionError);
      await tester.pump();
      final disposed = await flushAnalytics(tester);

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'private-value',
          'control': 'second-control',
        },
      ]);
      expect(
        routed.where((event) => event['name'] == 'flow_custom_event'),
        hasLength(1),
      );
      expect(
        disposed.where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'context-free callbacks refuse after controller swap and disposal',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
        contextFree: true,
      );
      final first = _analyticsPrivacyController(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select first global controller',
            control: 'first-global-control',
          ),
        ),
      );
      final second = _analyticsPrivacyController(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select second global controller',
            control: 'second-global-control',
          ),
        ),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      late StateSetter updateHost;
      var active = first;

      unawaited(first.load());
      unawaited(second.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              final controller = active;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageFlowView<FirstRunResult>(
                  key: const ValueKey<String>('global-swappable-view'),
                  controller: controller,
                  context: const <String, Object?>{
                    'secret': 'global-swap-private-value',
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final removedControllerCallback =
          callbacks['Select first global controller']!;

      updateHost(() => active = second);
      await tester.pump();
      expect(removedControllerCallback, throwsAssertionError);
      callbacks['Select second global controller']!();
      await tester.pump();
      final routed = await flushAnalytics(tester);
      final disposedCallback = callbacks['Select second global controller']!;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(disposedCallback, throwsAssertionError);
      await tester.pump();
      final disposed = await flushAnalytics(tester);

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'global-swap-private-value',
          'control': 'second-global-control',
        },
      ]);
      expect(
        routed.where((event) => event['name'] == 'flow_custom_event'),
        hasLength(1),
      );
      expect(
        jsonEncode(routed),
        isNot(contains('global-swap-private-value')),
      );
      expect(
        disposed.where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'retained callbacks preserve capture privacy and refuse after screen exit',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final controller = _analyticsPrivacyController(
        _twoScreenLocalPrivacyFlow(),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);
      Map<String, Object?>? hostContext = <String, Object?>{
        'secret': 'retained-private-value',
      };
      late StateSetter updateHost;

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageFlowView<FirstRunResult>(
                  controller: controller,
                  context: hostContext,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      controller.handleEvent('next', null);
      await tester.pumpAndSettle();
      final retained = callbacks['Select second screen']!;
      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();

      retained();
      await tester.pump();
      final retainedAnalytics = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );

      controller.back();
      await tester.pumpAndSettle();
      expect(retained, throwsAssertionError);
      callbacks['Select first screen']!();
      await tester.pump();
      final currentAnalytics = customEvent(
        await flushAnalytics(tester),
        'flow_custom_event',
      );

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'retained-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
      ]);
      expect(
        retainedAnalytics['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
      expect(currentAnalytics['properties'], <String, Object?>{
        'eventName': 'selected_plan',
        'fields': <String, Object?>{'control': 'retained'},
      });
    },
  );

  testWidgets(
    'context-free callbacks expire when their screen leaves current content',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
        contextFree: true,
      );
      final controller = _analyticsPrivacyController(
        _twoScreenLocalPrivacyFlow(),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);
      Map<String, Object?> hostContext = <String, Object?>{
        'secret': 'removed-screen-private-value',
      };
      late StateSetter updateHost;

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageFlowView<FirstRunResult>(
                  controller: controller,
                  context: hostContext,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final replacedScreenCallback = callbacks['Select first screen']!;

      controller.handleEvent('next', null);
      await tester.pumpAndSettle();
      final removedScreenCallback = callbacks['Select second screen']!;
      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      controller.back();
      await tester.pumpAndSettle();

      expect(removedScreenCallback, throwsAssertionError);
      expect(replacedScreenCallback, throwsAssertionError);
      final analytics = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
          jsonEncode(<Map<String, Object?>>[
            for (final event in localEvents) event.fields,
          ]),
          isNot(contains('removed-screen-private-value')));
      expect(localEvents, isEmpty);
      expect(
        analytics.where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
      expect(
        jsonEncode(analytics),
        isNot(contains('removed-screen-private-value')),
      );
    },
  );

  testWidgets(
    'multiple views for one controller retain conservative privacy',
    (tester) async {
      _registerLocalPrivacyWidget();
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: controller.handleEvent,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{
                      'secret': 'shared-private-value',
                    },
                  ),
                ),
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{'secret': null},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      final properties = <Map<String, Object?>>[];
      for (final target in <Finder>[
        find.text('Select local plan').first,
        find.text('Select local plan').last,
      ]) {
        await tester.tap(target);
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'flow_custom_event',
        );
        properties.add(
          (envelope['properties']! as Map<Object?, Object?>)
              .cast<String, Object?>(),
        );
      }

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'shared-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
      ]);
      expect(properties, <Object?>[
        <String, Object?>{'eventName': 'selected_plan'},
        <String, Object?>{'eventName': 'selected_plan'},
      ]);
    },
  );

  testWidgets(
    'context-free callbacks aggregate matching current controller views',
    (tester) async {
      _registerLocalPrivacyWidget(contextFree: true);
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: controller.handleEvent,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{
                      'secret': 'multi-view-private-value',
                    },
                  ),
                ),
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{'secret': null},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      final properties = <Map<String, Object?>>[];
      for (final target in <Finder>[
        find.text('Select local plan').first,
        find.text('Select local plan').last,
      ]) {
        await tester.tap(target);
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'flow_custom_event',
        );
        properties.add(
          envelope['properties']! as Map<String, Object?>,
        );
      }

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'multi-view-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
      ]);
      expect(properties, <Object?>[
        <String, Object?>{'eventName': 'selected_plan'},
        <String, Object?>{'eventName': 'selected_plan'},
      ]);
    },
  );

  testWidgets(
    'registered callbacks refuse a replaced dispatcher handler',
    (tester) async {
      VoidCallback? currentCallback;
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (_, callback) => currentCallback = callback,
        contextFree: true,
      );
      final controller = _analyticsPrivacyController(
        _resolvedPrivacyFlow(_localPrivacyFlowBlob(stateful: true)),
      );
      addTearDown(controller.dispose);
      late StateSetter updateHost;
      var destination = 'first';
      final routed = <({String destination, String eventId, Object? value})>[];

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              final currentDestination = destination;
              void handler(String eventId, Object? value) {
                routed.add((
                  destination: currentDestination,
                  eventId: eventId,
                  value: value,
                ));
              }

              return RestageEventDispatcher(
                onEvent: handler,
                child: RestageFlowEventHandlerAssociation(
                  controller: controller,
                  handler: handler,
                  isCurrent: () => destination == currentDestination,
                  child: RestageFlowView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{
                      'secret': 'retained-private-value',
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final retained = currentCallback!;

      updateHost(() => destination = 'second');
      await tester.pump();
      expect(retained, throwsAssertionError);
      await tester.tap(find.text('Rebuild Select local plan: 0'));
      await tester.pump();
      currentCallback!();
      await tester.pump();
      await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(routed, hasLength(1));
      expect(routed.single.destination, 'second');
      expect(routed.single.eventId, 'selected_plan');
      expect(routed.single.value, <String, Object?>{
        'selection': 'retained-private-value',
        'control': 'retained',
      });
    },
  );

  testWidgets(
    'context-bound callbacks select the matching controller registration',
    (tester) async {
      _registerLocalPrivacyWidget();
      final routed = <({String controller, Map<String, Object?> fields})>[];
      final first = RestageFlowController<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: StaticFlowResolver(
          _resolvedPrivacyFlow(
            _localPrivacyFlowBlob(label: 'Select first controller'),
          ),
        ),
        actions: null,
        onEvent: (event) {
          if (event is FlowCustomEvent) {
            routed.add((controller: 'first', fields: event.fields));
          }
        },
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      final second = RestageFlowController<FirstRunResult>(
        flow: firstRunFlowRef,
        resolver: StaticFlowResolver(
          _resolvedPrivacyFlow(
            _localPrivacyFlowBlob(label: 'Select second controller'),
          ),
        ),
        actions: null,
        onEvent: (event) {
          if (event is FlowCustomEvent) {
            routed.add((controller: 'second', fields: event.fields));
          }
        },
        onComplete: (_) {},
        onUnavailable: (_) {},
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      late BuildContext outsideViewContext;

      unawaited(first.load());
      unawaited(second.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: first.handleEvent,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: first,
                    context: const <String, Object?>{
                      'secret': 'first-private-value',
                    },
                  ),
                ),
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: second,
                    context: const <String, Object?>{
                      'secret': 'second-private-value',
                    },
                  ),
                ),
                Builder(
                  builder: (context) {
                    outsideViewContext = context;
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final attempts = <VoidCallback>[
        surfaceEventWithContext(
          tester.element(find.text('Select first controller')),
          const SurfaceEvent<Map<String, Object?>>('selected_plan'),
          const <String, Object?>{
            'selection': 'first-private-value',
            'control': 'first-control',
          },
        ),
        surfaceEventWithContext(
          tester.element(find.text('Select second controller')),
          const SurfaceEvent<Map<String, Object?>>('selected_plan'),
          const <String, Object?>{
            'selection': 'second-private-value',
            'control': 'second-control',
          },
        ),
        surfaceEventWithContext(
          outsideViewContext,
          const SurfaceEvent<Map<String, Object?>>('selected_plan'),
          const <String, Object?>{
            'selection': 'outside-private-value',
            'control': 'outside-control',
          },
        ),
      ];
      final failures = <Object>[];
      for (final attempt in attempts) {
        try {
          attempt();
        } on Object catch (error) {
          failures.add(error);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        routed,
        hasLength(1),
        reason: 'Expected first-private-value only; routed=$routed',
      );
      expect(routed.single.controller, 'first');
      expect(routed.single.fields, <String, Object?>{
        'selection': 'first-private-value',
        'control': 'first-control',
      });
      expect(failures, everyElement(isA<AssertionError>()));
      expect(failures, hasLength(2));
    },
  );

  testWidgets(
    'context-free callbacks refuse multiple registered controllers',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
        contextFree: true,
      );
      final routed = <({String controller, Map<String, Object?> fields})>[];
      RestageFlowController<FirstRunResult> createController(
        String name,
        String label,
      ) {
        return RestageFlowController<FirstRunResult>(
          flow: firstRunFlowRef,
          resolver: StaticFlowResolver(
            _resolvedPrivacyFlow(_localPrivacyFlowBlob(label: label)),
          ),
          actions: null,
          onEvent: (event) {
            if (event is FlowCustomEvent) {
              routed.add((controller: name, fields: event.fields));
            }
          },
          onComplete: (_) {},
          onUnavailable: (_) {},
        );
      }

      final first = createController('first', 'Select first global');
      final second = createController('second', 'Select second global');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      unawaited(first.load());
      unawaited(second.load());

      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: first.handleEvent,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: first,
                    context: const <String, Object?>{
                      'secret': 'first-global-private-value',
                    },
                  ),
                ),
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: second,
                    context: const <String, Object?>{
                      'secret': 'second-global-private-value',
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final failures = <Object>[];
      for (final label in <String>[
        'Select first global',
        'Select second global',
      ]) {
        try {
          callbacks[label]!();
        } on Object catch (error) {
          failures.add(error);
        }
      }

      expect(failures, hasLength(2));
      expect(failures, everyElement(isA<AssertionError>()));
      expect(routed, isEmpty);
      expect(jsonEncode(routed), isNot(contains('global-private-value')));
    },
  );

  testWidgets(
    'registered callbacks retain independent graph ownership across order changes',
    (tester) async {
      _registerLocalPrivacyWidget();
      final resolverA = StaticFlowResolver(
        _resolvedPrivacyFlow(_localPrivacyFlowBlob(label: 'Select graph A')),
      );
      final resolverB = StaticFlowResolver(
        _resolvedPrivacyFlow(_localPrivacyFlowBlob(label: 'Select graph B')),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      Map<String, Object?>? contextA;
      Map<String, Object?>? contextB = <String, Object?>{'secret': null};
      var reverse = false;
      late StateSetter updateHost;

      Widget graph({
        required String keyName,
        required StaticFlowResolver resolver,
        required Map<String, Object?>? hostContext,
      }) {
        // The flow's screens are routes, so each graph needs bounded
        // constraints; the key rides the sized wrapper so a reorder moves the
        // element rather than rebuilding both graphs.
        return Expanded(
          key: ValueKey<String>(keyName),
          child: RestageFlowGraph<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: resolver,
            context: hostContext,
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              final a = graph(
                keyName: 'graph-a',
                resolver: resolverA,
                hostContext: contextA,
              );
              final b = graph(
                keyName: 'graph-b',
                resolver: resolverB,
                hostContext: contextB,
              );
              return Column(
                children: reverse ? <Widget>[b, a] : <Widget>[a, b],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      Future<Map<String, Object?>> tap(String label) async {
        await tester.tap(find.text(label));
        await tester.pump();
        final events = await flushAnalytics(tester);
        final envelope = customEvent(events, 'flow_custom_event');
        return (envelope['properties']! as Map).cast<String, Object?>();
      }

      updateHost(() {
        contextA = <String, Object?>{'secret': 'private-selection'};
      });
      await tester.pump();
      final privateA = await tap('Select graph A');
      final emptyB = await tap('Select graph B');

      updateHost(() {
        reverse = true;
        contextA = <String, Object?>{'secret': null};
        contextB = <String, Object?>{'secret': 'private-from-b'};
      });
      await tester.pump();
      final privateB = await tap('Select graph B');
      final emptyA = await tap('Select graph A');

      updateHost(() {
        contextA = <String, Object?>{'secret': 'private-from-a'};
      });
      await tester.pump();
      final bothPrivateA = await tap('Select graph A');
      final bothPrivateB = await tap('Select graph B');

      expect(privateA, <String, Object?>{'eventName': 'selected_plan'});
      expect(emptyB, <String, Object?>{
        'eventName': 'selected_plan',
        'fields': <String, Object?>{'control': 'retained'},
      });
      expect(privateB, <String, Object?>{'eventName': 'selected_plan'});
      expect(emptyA, <String, Object?>{
        'eventName': 'selected_plan',
        'fields': <String, Object?>{'control': 'retained'},
      });
      expect(bothPrivateA, <String, Object?>{'eventName': 'selected_plan'});
      expect(bothPrivateB, <String, Object?>{'eventName': 'selected_plan'});
      expect(
        localEvents.map((event) => event.fields).toList(),
        <Map<String, Object?>>[
          <String, Object?>{
            'selection': 'private-selection',
            'control': 'retained',
          },
          <String, Object?>{'control': 'retained'},
          <String, Object?>{
            'selection': 'private-from-b',
            'control': 'retained',
          },
          <String, Object?>{'control': 'retained'},
          <String, Object?>{
            'selection': 'private-from-a',
            'control': 'retained',
          },
          <String, Object?>{
            'selection': 'private-from-b',
            'control': 'retained',
          },
        ],
      );
    },
  );

  testWidgets(
    'stateful registered descendants keep their graph owner on local rebuild',
    (tester) async {
      _registerLocalPrivacyWidget();
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) {
          localEvents.add(event);
        }
      });
      addTearDown(subscription.cancel);
      var includeEmptyGraph = false;
      late StateSetter updateHost;
      final privateResolver = StaticFlowResolver(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select stateful A',
            stateful: true,
          ),
          flow: _privateGraphFlow,
        ),
      );
      final emptyResolver = StaticFlowResolver(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(label: 'Select empty B'),
          flow: _emptyGraphFlow,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Column(
                children: <Widget>[
                  Expanded(
                    child: RestageFlowGraph<FirstRunResult>(
                      flow: _privateGraphFlow,
                      resolver: privateResolver,
                      context: const <String, Object?>{
                        'secret': 'descendant-private-value',
                      },
                      unavailable: const FlowUnavailablePolicy.hide(),
                    ),
                  ),
                  if (includeEmptyGraph)
                    Expanded(
                      child: RestageFlowGraph<FirstRunResult>(
                        flow: _emptyGraphFlow,
                        resolver: emptyResolver,
                        context: const <String, Object?>{'secret': null},
                        unavailable: const FlowUnavailablePolicy.hide(),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      updateHost(() => includeEmptyGraph = true);
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      await tester.tap(find.text('Rebuild Select stateful A: 0'));
      await tester.pump();
      expect(find.text('Rebuild Select stateful A: 1'), findsOneWidget);
      await tester.tap(find.text('Select stateful A'));
      await tester.pump();
      final events = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(localEvents.single.flowId, _privateGraphFlow.id);
      final envelope = customEvent(events, 'flow_custom_event');
      final properties =
          (envelope['properties']! as Map).cast<String, Object?>();
      expect(localEvents.single.fields, <String, Object?>{
        'selection': 'descendant-private-value',
        'control': 'retained',
      });
      expect(properties, <String, Object?>{'eventName': 'selected_plan'});
    },
  );

  testWidgets(
    'live refresh keeps current and staged callback ownership distinct',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final resolver = _MutablePrivacyFlowResolver(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select retained layer',
            control: 'retained-layer',
          ),
        ),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      FirstPaintLeaseTransaction? retainedTransaction;
      FirstPaintLeaseTransaction.debugBeforeDescendantPaint = (transaction) {
        retainedTransaction ??= transaction;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: RestageFlowGraph<FirstRunResult>(
            flow: firstRunFlowRef,
            resolver: resolver,
            context: const <String, Object?>{
              'secret': 'refresh-private-value',
            },
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final retainedCallback = callbacks['Select retained layer']!;
      var overlapViewCount = 0;
      var overlapCallbackScheduled = false;
      var stagedCallbackFired = false;
      var stagedCallbackWasAvailable = false;
      final overlapFailures = <Object>[];

      resolver.current = _resolvedPrivacyFlow(
        _localPrivacyFlowBlob(
          label: 'Select staged layer',
          control: 'staged-layer',
        ),
      );
      FirstPaintLeaseTransaction.debugBeforeDescendantPaint = (transaction) {
        if (identical(transaction, retainedTransaction) ||
            overlapCallbackScheduled) {
          return;
        }
        overlapCallbackScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          overlapViewCount = tester
              .widgetList<RestageFlowView<FirstRunResult>>(
                find.byType(RestageFlowView<FirstRunResult>),
              )
              .length;
          try {
            retainedCallback();
          } on Object catch (error) {
            overlapFailures.add(error);
          }
          final stagedCallback = callbacks['Select staged layer'];
          stagedCallbackWasAvailable = stagedCallback != null;
          try {
            stagedCallback?.call();
          } on Object catch (error) {
            overlapFailures.add(error);
          }
          stagedCallbackFired = true;
        });
      };

      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      FirstPaintLeaseTransaction.debugBeforeDescendantPaint = null;
      final overlapAnalytics = await flushAnalytics(tester);

      expect(retainedCallback, throwsAssertionError);
      callbacks['Select staged layer']?.call();
      await tester.pump();
      final promotedAnalytics = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(overlapViewCount, 2);
      expect(stagedCallbackFired, isTrue);
      expect(stagedCallbackWasAvailable, isTrue);
      expect(overlapFailures, hasLength(1));
      expect(overlapFailures, everyElement(isA<AssertionError>()));
      expect(
        overlapAnalytics.where(
          (event) => event['name'] == 'flow_custom_event',
        ),
        isEmpty,
      );
      expect(
        promotedAnalytics.where(
          (event) => event['name'] == 'flow_custom_event',
        ),
        hasLength(1),
      );
      final promotedEnvelope = customEvent(
        promotedAnalytics,
        'flow_custom_event',
      );
      expect(
        localEvents.map((event) => event.fields).toList(),
        <Map<String, Object?>>[
          <String, Object?>{
            'selection': 'refresh-private-value',
            'control': 'staged-layer',
          },
        ],
      );
      expect(
        promotedEnvelope['properties'],
        <String, Object?>{'eventName': 'selected_plan'},
      );
    },
  );

  testWidgets('flow privacy aggregates owners and unregisters exact identity',
      (tester) async {
    final controller = _privacyController();
    final observed = <bool>[];
    addTearDown(controller.dispose);
    unawaited(controller.load());

    Widget buildViews({
      required bool includePrivate,
      required Map<String, Object?> emptyOwnerContext,
    }) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            if (includePrivate)
              RestageFlowView<FirstRunResult>(
                key: const ValueKey<String>('private-owner'),
                controller: controller,
                context: const <String, Object?>{'secret': 'private'},
              ),
            RestageFlowView<FirstRunResult>(
              key: const ValueKey<String>('empty-owner'),
              controller: controller,
              context: emptyOwnerContext,
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(
      buildViews(
        includePrivate: true,
        emptyOwnerContext: const <String, Object?>{'secret': null},
      ),
    );
    await tester.pumpAndSettle();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          controller),
    );

    await tester.pumpWidget(
      buildViews(
        includePrivate: false,
        emptyOwnerContext: const <String, Object?>{'secret': null},
      ),
    );
    await tester.pump();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          controller),
    );

    await tester.pumpWidget(
      buildViews(
        includePrivate: false,
        emptyOwnerContext: const <String, Object?>{'secret': 'now-private'},
      ),
    );
    await tester.pump();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          controller),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          controller),
    );
    expect(observed, <bool>[true, false, true, false]);
  });

  testWidgets('flow view registers its dispatcher owner', (tester) async {
    final controller = _privacyController();
    bool? exactPrivacy;
    addTearDown(controller.dispose);
    void handler(String eventId, Object? value) {
      exactPrivacy = RestageFlowRenderEventPrivacyRegistry
          .mayExposeNonEmptyHostContextForOwner(
        controller: controller,
        owner: currentSurfaceEventDispatcherOwner!,
      );
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageEventDispatcher(
          onEvent: handler,
          child: RestageFlowEventHandlerAssociation(
            controller: controller,
            handler: handler,
            isCurrent: () => true,
            child: RestageFlowView<FirstRunResult>(
              controller: controller,
              context: const <String, Object?>{'secret': 'private'},
            ),
          ),
        ),
      ),
    );
    unawaited(controller.load());
    await tester.pumpAndSettle();

    final callback = surfaceEvent(const SurfaceEvent<void>('probe'));
    callback();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(exactPrivacy, isTrue);
  });

  testWidgets('flow privacy registration follows controller swaps',
      (tester) async {
    final first = _privacyController();
    final second = _privacyController();
    final observed = <bool>[];
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    unawaited(first.load());
    unawaited(second.load());

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageFlowView<FirstRunResult>(
          key: const ValueKey<String>('swapped-owner'),
          controller: first,
          context: const <String, Object?>{'secret': 'private'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(first),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageFlowView<FirstRunResult>(
          key: const ValueKey<String>('swapped-owner'),
          controller: second,
          context: const <String, Object?>{'secret': 'second-private'},
        ),
      ),
    );
    // The replaced screens leave with their routes, so the old registration
    // clears once that removal settles.
    await tester.pumpAndSettle();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(first),
    );
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          second),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    observed.add(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          second),
    );
    expect(observed, <bool>[true, false, true, false]);
  });

  test('flow privacy registry preserves controller and owner identity', () {
    final firstController = _EqualRegistryKey();
    final secondController = _EqualRegistryKey();
    final firstOwner = _EqualRegistryKey();
    final secondOwner = _EqualRegistryKey();
    final otherOwner = _EqualRegistryKey();
    var secondOwnerExposes = false;
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: firstController,
      owner: firstOwner,
      registration: firstOwner,
      mayExposeNonEmptyHostContext: () => true,
    );
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: firstController,
      owner: secondOwner,
      registration: secondOwner,
      mayExposeNonEmptyHostContext: () => secondOwnerExposes,
    );
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: secondController,
      owner: otherOwner,
      registration: otherOwner,
      mayExposeNonEmptyHostContext: () => false,
    );
    addTearDown(() {
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: firstController,
        owner: firstOwner,
        registration: firstOwner,
      );
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: firstController,
        owner: secondOwner,
        registration: secondOwner,
      );
      RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: secondController,
        owner: otherOwner,
        registration: otherOwner,
      );
    });

    expect(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          firstController),
      isTrue,
    );
    expect(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          secondController),
      isFalse,
    );
    expect(
      RestageFlowRenderEventPrivacyRegistry
          .mayExposeNonEmptyHostContextForOwner(
        controller: firstController,
        owner: secondOwner,
      ),
      isTrue,
    );
    expect(
      RestageFlowRenderEventPrivacyRegistry
          .mayExposeNonEmptyHostContextForOwner(
        controller: secondController,
        owner: firstOwner,
      ),
      isNull,
    );
    RestageFlowRenderEventPrivacyRegistry.unregister(
      controller: firstController,
      owner: firstOwner,
      registration: firstOwner,
    );
    expect(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          firstController),
      isFalse,
    );
    expect(
      RestageFlowRenderEventPrivacyRegistry
          .mayExposeNonEmptyHostContextForOwner(
        controller: firstController,
        owner: secondOwner,
      ),
      isFalse,
    );
    secondOwnerExposes = true;
    expect(
      RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
          firstController),
      isTrue,
    );
  });

  test('flow privacy treats a live callback failure as exposed', () {
    final controller = Object();
    final owner = Object();
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: controller,
      owner: owner,
      registration: owner,
      mayExposeNonEmptyHostContext: () => throw StateError('unreadable'),
    );
    addTearDown(
      () => RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: controller,
        owner: owner,
        registration: owner,
      ),
    );

    final omit =
        RestageFlowRenderEventPrivacyRegistry.mayExposeNonEmptyHostContext(
            controller);
    final mapped = RestageRenderEventPrivacy.run(
      mayExposeNonEmptyHostContext: omit,
      body: () => _mapCurrentRenderEvent(
        const FlowCustomEvent(
          flowId: 'first_run',
          flowVersion: 1,
          eventName: 'selected_plan',
          fields: <String, Object?>{'selection': 'private'},
        ),
      ),
    );

    expect(omit, isTrue);
    expect(mapped.properties, <String, Object?>{
      'eventName': 'selected_plan',
    });
  });

  testWidgets('single-screen flow events carry render privacy to the mapper',
      (tester) async {
    final mapped = <AnalyticsEvent>[];
    final localEvents = <FlowCustomEvent>[];
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(_privacyFlow()),
      actions: null,
      onEvent: (event) {
        if (event is FlowCustomEvent) {
          localEvents.add(event);
          mapped.add(_mapCurrentRenderEvent(event));
        }
      },
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageScreenView<FirstRunResult>(
          controller: controller,
          context: const <String, Object?>{
            'secret': 'screen-view-private-value',
          },
        ),
      ),
    );
    unawaited(controller.load());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select flow plan'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final localSelection = localEvents.single.fields['selection'];
    final properties = Map<String, Object?>.of(mapped.single.properties);
    expect(localSelection, 'screen-view-private-value');
    expect(properties, <String, Object?>{
      'eventName': 'selected_plan',
    });
  });

  for (final contextFree in <bool>[false, true]) {
    testWidgets(
      'single-screen registered ${contextFree ? 'context-free' : 'context-bound'} '
      'callbacks carry render privacy',
      (tester) async {
        _registerLocalPrivacyWidget(contextFree: contextFree);
        final controller = _analyticsPrivacyController(_localPrivacyFlow());
        final localEvents = <FlowCustomEvent>[];
        final subscription = Restage.events.listen((event) {
          if (event is FlowCustomEvent) localEvents.add(event);
        });
        addTearDown(subscription.cancel);
        addTearDown(controller.dispose);

        unawaited(controller.load());
        await tester.pumpWidget(
          MaterialApp(
            home: RestageEventDispatcher(
              onEvent: controller.handleEvent,
              child: RestageScreenView<FirstRunResult>(
                controller: controller,
                context: const <String, Object?>{
                  'secret': 'screen-view-callback-private-value',
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await flushAnalytics(tester);

        await tester.tap(find.text('Select local plan'));
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'flow_custom_event',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(localEvents.single.fields, <String, Object?>{
          'selection': 'screen-view-callback-private-value',
          'control': 'retained',
        });
        expect(
          envelope['properties'],
          <String, Object?>{'eventName': 'selected_plan'},
        );
      },
    );
  }

  testWidgets(
    'flow and single-screen mounts aggregate matching content privacy',
    (tester) async {
      _registerLocalPrivacyWidget(contextFree: true);
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: controller.handleEvent,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: RestageFlowView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{
                      'secret': 'mixed-mount-private-value',
                    },
                  ),
                ),
                RestageScreenView<FirstRunResult>(
                  controller: controller,
                  context: const <String, Object?>{'secret': null},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      final properties = <Map<String, Object?>>[];
      for (final target in <Finder>[
        find.text('Select local plan').first,
        find.text('Select local plan').last,
      ]) {
        await tester.tap(target);
        await tester.pump();
        final envelope = customEvent(
          await flushAnalytics(tester),
          'flow_custom_event',
        );
        properties.add(
          (envelope['properties']! as Map).cast<String, Object?>(),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'mixed-mount-private-value',
          'control': 'retained',
        },
        <String, Object?>{'control': 'retained'},
      ]);
      expect(properties, <Object?>[
        <String, Object?>{'eventName': 'selected_plan'},
        <String, Object?>{'eventName': 'selected_plan'},
      ]);
    },
  );

  testWidgets(
    'single-screen replacement and back invalidate prior callbacks',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
        contextFree: true,
      );
      final controller = _analyticsPrivacyController(
        _twoScreenLocalPrivacyFlow(),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);
      late StateSetter updateHost;
      Map<String, Object?> hostContext = <String, Object?>{
        'secret': 'single-replaced-private-value',
      };

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageScreenView<FirstRunResult>(
                  controller: controller,
                  context: hostContext,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final firstCallback = callbacks['Select first screen']!;

      controller.handleEvent('next', null);
      await tester.pumpAndSettle();
      final secondCallback = callbacks['Select second screen']!;
      updateHost(() {
        hostContext = <String, Object?>{'secret': null};
      });
      await tester.pump();
      controller.back();
      await tester.pumpAndSettle();
      final currentCallback = callbacks['Select first screen']!;

      expect(firstCallback, throwsAssertionError);
      expect(secondCallback, throwsAssertionError);
      currentCallback();
      await tester.pump();
      final analytics = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{'control': 'retained'},
      ]);
      expect(
        jsonEncode(<Object?>[
          <Map<String, Object?>>[
            for (final event in localEvents) event.fields,
          ],
          analytics,
        ]),
        isNot(contains('single-replaced-private-value')),
      );
      expect(
        customEvent(analytics, 'flow_custom_event')['properties'],
        <String, Object?>{
          'eventName': 'selected_plan',
          'fields': <String, Object?>{'control': 'retained'},
        },
      );
    },
  );

  testWidgets(
    'single-screen callbacks refuse controller swaps and disposal',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final first = _analyticsPrivacyController(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select first single controller',
            control: 'first-single-control',
          ),
        ),
      );
      final second = _analyticsPrivacyController(
        _resolvedPrivacyFlow(
          _localPrivacyFlowBlob(
            label: 'Select second single controller',
            control: 'second-single-control',
          ),
        ),
      );
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      late StateSetter updateHost;
      var active = first;

      unawaited(first.load());
      unawaited(second.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              final controller = active;
              return RestageEventDispatcher(
                onEvent: controller.handleEvent,
                child: RestageScreenView<FirstRunResult>(
                  key: const ValueKey<String>('swappable-single-screen'),
                  controller: controller,
                  context: const <String, Object?>{
                    'secret': 'single-swap-private-value',
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);
      final firstCallback = callbacks['Select first single controller']!;

      updateHost(() => active = second);
      await tester.pumpAndSettle();
      expect(firstCallback, throwsAssertionError);
      callbacks['Select second single controller']!();
      await tester.pump();
      final routed = await flushAnalytics(tester);
      final disposedCallback = callbacks['Select second single controller']!;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(disposedCallback, throwsAssertionError);
      await tester.pump();
      final disposed = await flushAnalytics(tester);

      expect(localEvents.map((event) => event.fields).toList(), <Object?>[
        <String, Object?>{
          'selection': 'single-swap-private-value',
          'control': 'second-single-control',
        },
      ]);
      expect(
        routed.where((event) => event['name'] == 'flow_custom_event'),
        hasLength(1),
      );
      expect(
        jsonEncode(routed),
        isNot(contains('single-swap-private-value')),
      );
      expect(
        disposed.where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'single-screen callbacks refuse a replaced dispatcher handler',
    (tester) async {
      VoidCallback? currentCallback;
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (_, callback) => currentCallback = callback,
        contextFree: true,
      );
      final controller = _analyticsPrivacyController(
        _resolvedPrivacyFlow(_localPrivacyFlowBlob(stateful: true)),
      );
      addTearDown(controller.dispose);
      late StateSetter updateHost;
      var destination = 'first';
      final routed = <({String destination, String eventId, Object? value})>[];

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              final currentDestination = destination;
              void handler(String eventId, Object? value) {
                routed.add((
                  destination: currentDestination,
                  eventId: eventId,
                  value: value,
                ));
              }

              return RestageEventDispatcher(
                onEvent: handler,
                child: RestageFlowEventHandlerAssociation(
                  controller: controller,
                  handler: handler,
                  isCurrent: () => destination == currentDestination,
                  child: RestageScreenView<FirstRunResult>(
                    controller: controller,
                    context: const <String, Object?>{
                      'secret': 'single-handler-private-value',
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final retained = currentCallback!;

      updateHost(() => destination = 'second');
      await tester.pump();
      expect(retained, throwsAssertionError);
      await tester.tap(find.text('Rebuild Select local plan: 0'));
      await tester.pump();
      currentCallback!();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(routed, hasLength(1));
      expect(routed.single.destination, 'second');
      expect(routed.single.eventId, 'selected_plan');
      expect(routed.single.value, <String, Object?>{
        'selection': 'single-handler-private-value',
        'control': 'retained',
      });
    },
  );

  testWidgets(
    'single-screen callbacks prove one controller among multiple mounts',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
      );
      final routed = <({String controller, Map<String, Object?> fields})>[];

      RestageFlowController<FirstRunResult> createController(
        String name,
        String label,
      ) {
        return RestageFlowController<FirstRunResult>(
          flow: firstRunFlowRef,
          resolver: StaticFlowResolver(
            _resolvedPrivacyFlow(_localPrivacyFlowBlob(label: label)),
          ),
          actions: null,
          onEvent: (event) {
            if (event is FlowCustomEvent) {
              routed.add((controller: name, fields: event.fields));
            }
          },
          onComplete: (_) {},
          onUnavailable: (_) {},
        );
      }

      final first = createController('first', 'Select first single');
      final second = createController('second', 'Select second single');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      unawaited(first.load());
      unawaited(second.load());

      await tester.pumpWidget(
        MaterialApp(
          home: RestageEventDispatcher(
            onEvent: first.handleEvent,
            child: Column(
              children: <Widget>[
                RestageScreenView<FirstRunResult>(
                  controller: first,
                  context: const <String, Object?>{
                    'secret': 'first-single-private-value',
                  },
                ),
                RestageScreenView<FirstRunResult>(
                  controller: second,
                  context: const <String, Object?>{
                    'secret': 'second-single-private-value',
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final failures = <Object>[];
      callbacks['Select first single']!();
      try {
        callbacks['Select second single']!();
      } on Object catch (error) {
        failures.add(error);
      }
      final contextFreeCallback = surfaceEvent(
        const SurfaceEvent<Map<String, Object?>>('selected_plan'),
        const <String, Object?>{
          'selection': 'ambiguous-single-private-value',
          'control': 'ambiguous-single-control',
        },
      );
      try {
        contextFreeCallback();
      } on Object catch (error) {
        failures.add(error);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(routed, hasLength(1));
      expect(routed.single.controller, 'first');
      expect(routed.single.fields, <String, Object?>{
        'selection': 'first-single-private-value',
        'control': 'retained',
      });
      expect(failures, hasLength(2));
      expect(failures, everyElement(isA<AssertionError>()));
      expect(
        jsonEncode(<Map<String, Object?>>[
          for (final event in routed)
            <String, Object?>{
              'controller': event.controller,
              'fields': event.fields,
            },
        ]),
        isNot(contains('ambiguous-single-private-value')),
      );
      expect(
        jsonEncode(<Map<String, Object?>>[
          for (final event in routed)
            <String, Object?>{
              'controller': event.controller,
              'fields': event.fields,
            },
        ]),
        isNot(contains('second-single-private-value')),
      );
    },
  );

  testWidgets(
    'single-screen sibling with an unprovable handler is refused',
    (tester) async {
      final callbacks = <String, VoidCallback>{};
      _registerLocalPrivacyWidget(
        onCallbackBuilt: (label, callback) => callbacks[label] = callback,
        contextFree: true,
      );
      final controller = _analyticsPrivacyController(_localPrivacyFlow());
      final localEvents = <FlowCustomEvent>[];
      final subscription = Restage.events.listen((event) {
        if (event is FlowCustomEvent) localEvents.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(controller.dispose);

      unawaited(controller.load());
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              RestageEventDispatcher(
                onEvent: (eventId, value) {
                  controller.handleEvent(eventId, value);
                },
                child: const SizedBox.shrink(),
              ),
              RestageScreenView<FirstRunResult>(
                controller: controller,
                context: const <String, Object?>{
                  'secret': 'single-unprovable-private-value',
                },
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await flushAnalytics(tester);

      Object? failure;
      try {
        callbacks['Select local plan']!();
      } on Object catch (error) {
        failure = error;
      }
      await tester.pump();
      final analytics = await flushAnalytics(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(failure, isA<AssertionError>());
      expect(localEvents, isEmpty);
      expect(
        analytics.where((event) => event['name'] == 'flow_custom_event'),
        isEmpty,
      );
      expect(
        jsonEncode(<Object?>[localEvents, analytics]),
        isNot(contains('single-unprovable-private-value')),
      );
    },
  );

  testWidgets('active unrelated registration preserves both helper lookups',
      (tester) async {
    final unrelatedController = Object();
    final unrelatedOwner = Object();
    final unrelatedRegistration = Object();
    void unrelatedHandler(String eventId, Object? value) {}
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: unrelatedController,
      owner: unrelatedOwner,
      registration: unrelatedRegistration,
      contentToken: 'unrelated-content',
      associatedHandler: unrelatedHandler,
      isCurrent: () => true,
      mayExposeNonEmptyHostContext: () => true,
    );
    addTearDown(
      () => RestageFlowRenderEventPrivacyRegistry.unregister(
        controller: unrelatedController,
        owner: unrelatedOwner,
        registration: unrelatedRegistration,
      ),
    );

    final routed = <Object?>[];
    late VoidCallback contextBoundCallback;
    await tester.pumpWidget(
      MaterialApp(
        home: RestageEventDispatcher(
          onEvent: (_, value) => routed.add(value),
          child: Builder(
            builder: (context) {
              contextBoundCallback = surfaceEventWithContext(
                context,
                const SurfaceEvent<String>('context_bound'),
                'active-unrelated-bound-private-value',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final contextFreeCallback = surfaceEvent(
      const SurfaceEvent<String>('context_free'),
      'active-unrelated-free-private-value',
    );

    final failures = <Object>[];
    for (final callback in <VoidCallback>[
      contextBoundCallback,
      contextFreeCallback,
    ]) {
      try {
        callback();
      } on Object catch (error) {
        failures.add(error);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(routed, <Object?>[
      'active-unrelated-bound-private-value',
      'active-unrelated-free-private-value',
    ]);
    expect(failures, isEmpty);
  });

  for (final view in _ControllerBackedView.values) {
    testWidgets(
      '${_controllerBackedViewLabel(view)} changes preserve unrelated callbacks',
      (tester) async {
        final first = _privacyController();
        final second = _privacyController();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        unawaited(first.load());
        unawaited(second.load());

        final token = _controllerBackedViewToken(view);
        final routed = <Object?>[];
        final failures = <Object>[];
        void standaloneHandler(String eventId, Object? value) =>
            routed.add(value);
        void invoke(VoidCallback callback) {
          try {
            callback();
          } on Object catch (error) {
            failures.add(error);
          }
        }

        final contextBoundCallbacks = <String, VoidCallback>{};
        final contextFreeCallbacks = <String, VoidCallback>{};
        late StateSetter updateHost;
        var capturePoint = 'before';
        var showView = false;
        var activeController = first;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                updateHost = setState;
                return Column(
                  children: <Widget>[
                    RestageEventDispatcher(
                      onEvent: standaloneHandler,
                      child: Builder(
                        builder: (context) {
                          contextBoundCallbacks.putIfAbsent(
                            capturePoint,
                            () => surfaceEventWithContext(
                              context,
                              const SurfaceEvent<String>('context_bound'),
                              '$token-$capturePoint-bound-private-value',
                            ),
                          );
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    if (showView)
                      _controllerBackedView(
                        view,
                        key: const ValueKey<String>('unrelated-view'),
                        controller: activeController,
                        context: <String, Object?>{
                          'secret': '$token-unrelated-private-value',
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        contextFreeCallbacks['before'] = surfaceEvent(
          const SurfaceEvent<String>('context_free'),
          '$token-before-free-private-value',
        );

        updateHost(() {
          capturePoint = 'during';
          showView = true;
        });
        await tester.pumpAndSettle();
        contextFreeCallbacks['during'] = surfaceEvent(
          const SurfaceEvent<String>('context_free'),
          '$token-during-free-private-value',
        );

        updateHost(() {
          capturePoint = 'swapped';
          activeController = second;
        });
        await tester.pumpAndSettle();
        contextFreeCallbacks['swapped'] = surfaceEvent(
          const SurfaceEvent<String>('context_free'),
          '$token-swapped-free-private-value',
        );

        for (final point in <String>['before', 'during', 'swapped']) {
          invoke(contextBoundCallbacks[point]!);
          invoke(contextFreeCallbacks[point]!);
        }

        updateHost(() {
          showView = false;
        });
        await tester.pumpAndSettle();
        updateHost(() => capturePoint = 'after');
        await tester.pumpAndSettle();
        contextFreeCallbacks['after'] = surfaceEvent(
          const SurfaceEvent<String>('context_free'),
          '$token-after-free-private-value',
        );
        invoke(contextBoundCallbacks['after']!);
        invoke(contextFreeCallbacks['after']!);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(routed, <Object?>[
          '$token-before-bound-private-value',
          '$token-before-free-private-value',
          '$token-during-bound-private-value',
          '$token-during-free-private-value',
          '$token-swapped-bound-private-value',
          '$token-swapped-free-private-value',
          '$token-after-bound-private-value',
          '$token-after-free-private-value',
        ]);
        expect(failures, isEmpty);
      },
    );
  }

  testWidgets('standalone callbacks require their current handler and owner',
      (tester) async {
    final routed = <Object?>[];
    final contextBoundCallbacks = <String, VoidCallback>{};
    late StateSetter updateHost;
    var destination = 'first';

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            final currentDestination = destination;
            return RestageEventDispatcher(
              onEvent: (_, value) => routed.add(
                <String, Object?>{
                  'destination': currentDestination,
                  'value': value,
                },
              ),
              child: Builder(
                builder: (context) {
                  contextBoundCallbacks[currentDestination] =
                      surfaceEventWithContext(
                    context,
                    const SurfaceEvent<String>('context_bound'),
                    '$currentDestination-bound-private-value',
                  );
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );
    final firstContextFree = surfaceEvent(
      const SurfaceEvent<String>('context_free'),
      'first-free-private-value',
    );

    updateHost(() => destination = 'second');
    await tester.pump();
    final secondContextFree = surfaceEvent(
      const SurfaceEvent<String>('context_free'),
      'second-free-private-value',
    );

    expect(contextBoundCallbacks['first']!, throwsAssertionError);
    expect(firstContextFree, throwsAssertionError);
    contextBoundCallbacks['second']!();
    secondContextFree();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(contextBoundCallbacks['second']!, throwsAssertionError);
    expect(secondContextFree, throwsAssertionError);

    expect(routed, <Object?>[
      <String, Object?>{
        'destination': 'second',
        'value': 'second-bound-private-value',
      },
      <String, Object?>{
        'destination': 'second',
        'value': 'second-free-private-value',
      },
    ]);
    expect(
      jsonEncode(routed),
      isNot(contains('first-bound-private-value')),
    );
    expect(
      jsonEncode(routed),
      isNot(contains('first-free-private-value')),
    );
  });

  testWidgets('direct controller events remain valid after view disposal',
      (tester) async {
    final events = <FlowCustomEvent>[];
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(_privacyFlow()),
      actions: null,
      onEvent: (event) {
        if (event is FlowCustomEvent) events.add(event);
      },
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    unawaited(controller.load());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageScreenView<FirstRunResult>(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    controller.handleEvent(
      'selected_plan',
      const <String, Object?>{
        'selection': 'direct-controller-private-value',
        'control': 'direct-controller-control',
      },
    );

    expect(events.single.fields, <String, Object?>{
      'selection': 'direct-controller-private-value',
      'control': 'direct-controller-control',
    });
  });

  testWidgets('never-registered dispatchers retain both helper lookups',
      (tester) async {
    final routed = <({String eventId, Object? value})>[];
    late VoidCallback contextBoundCallback;

    await tester.pumpWidget(
      MaterialApp(
        home: RestageEventDispatcher(
          onEvent: (eventId, value) {
            routed.add((eventId: eventId, value: value));
          },
          child: Builder(
            builder: (context) {
              contextBoundCallback = surfaceEventWithContext(
                context,
                const SurfaceEvent<String>('context_bound'),
                'never-registered-bound-value',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final contextFreeCallback = surfaceEvent(
      const SurfaceEvent<String>('context_free'),
      'never-registered-free-value',
    );

    contextBoundCallback();
    contextFreeCallback();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(routed, <Object?>[
      (
        eventId: 'context_bound',
        value: 'never-registered-bound-value',
      ),
      (
        eventId: 'context_free',
        value: 'never-registered-free-value',
      ),
    ]);
  });

  testWidgets('standalone screen events carry render privacy to the mapper',
      (tester) async {
    final schema = SurfaceScreenEventSchema(
      events: <SurfaceScreenEvent>[
        SurfaceScreenEvent(
          id: 'selected_plan',
          arguments: const SurfaceScreenEventValueArguments(
            SurfaceScreenEventScalarShapeV1(
              SurfaceScreenEventScalarKind.string,
            ),
          ),
        ),
      ],
    );
    final fixture = stringScreenFixture(
      surface: Surface.paywall,
      schema: schema,
      decoder: (_, arguments) => arguments['value']! as String,
      blob: rfwSourceBlob('''
import restage.core;

widget OnboardingScreen = GestureDetector(
  onTap: event "selected_plan" { value: data.context.secret },
  child: Text(text: "Select standalone plan")
);
'''),
    );
    final localValues = <String>[];
    final mapped = <AnalyticsEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RestageScreen<String>(
          screen: fixture.ref,
          resolver: FixedScreenResolver(fixture.bundled()),
          context: const <String, Object?>{
            'secret': 'standalone-private-value',
          },
          unavailable: const SurfaceScreenUnavailablePolicy.hide(),
          onEvent: (value) {
            localValues.add(value);
            mapped.add(
              _mapCurrentRenderEvent(
                PaywallCustomEvent(
                  paywallId: 'standalone-screen',
                  eventName: 'selected_plan',
                  args: <String, Object?>{
                    'selection': value,
                    'control': 'retained',
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select standalone plan'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final properties = Map<String, Object?>.of(mapped.single.properties);
    expect(localValues, <String>['standalone-private-value']);
    expect(properties, <String, Object?>{
      'eventName': 'selected_plan',
    });
  });
}

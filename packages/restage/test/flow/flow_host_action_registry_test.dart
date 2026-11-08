import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

const _flowRef = OnboardingFlowRef<_Result>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surface: Surface.onboarding,
  decodeResult: _Result.decode,
);

/// A rebuilt flow host reads a registry with the same contracts in place and
/// reloads for any other.
void main() {
  InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn());
  setUp(() {
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  final document = _flowDocument(
    actions: {'create_profile': _actionContract()},
    states: const {
      'welcome': ScreenFlowState(
        screen: 'welcome',
        on: {
          'next': ActionFlowTransition(
            action: 'create_profile',
            resultPredicate: BoolEqualsActionResultPredicate(value: true),
            target: 'done',
          ),
        },
      ),
      'done': EndFlowState(result: {'completed': true}),
    },
  );

  Widget host(
    FlowResolver resolver,
    FlowActionRegistry? actions, {
    List<FlowUnavailableError>? failures,
    List<_Result>? results,
  }) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageOnboarding<_Result>(
          flow: _flowRef,
          resolver: resolver,
          actions: actions,
          fallbackBuilder: (_) => const Text('fallback'),
          onFlowUnavailable: failures?.add,
          onComplete: results?.add,
        ),
      );

  testWidgets('a registry that drops the action reloads and fails closed',
      (tester) async {
    final resolver = _CountingResolver(_resolvedFlow(document));
    final calls = <String>[];
    final failures = <FlowUnavailableError>[];
    final results = <_Result>[];
    await tester.pumpWidget(host(resolver, _Actions(handler: (_, __) {
      calls.add('first');
      return true;
    }), failures: failures, results: results));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    // The host now installs no binding for create_profile.
    await tester.pumpWidget(host(resolver, const _NoActions(),
        failures: failures, results: results));
    await tester.pumpAndSettle();
    await _tapIfShown(tester, 'Welcome');
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(failures.map((f) => f.reason), ['action_contract_mismatch']);
    expect(results, isEmpty);
    expect(resolver.calls, 2);
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('a registry with a changed contract reloads and fails closed',
      (tester) async {
    final resolver = _CountingResolver(_resolvedFlow(document));
    final calls = <String>[];
    final failures = <FlowUnavailableError>[];
    final results = <_Result>[];
    await tester.pumpWidget(host(resolver, _Actions(handler: (_, __) {
      calls.add('first');
      return true;
    }), failures: failures, results: results));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(
        resolver,
        _Actions(
            contractVersion: 2,
            handler: (_, __) {
              calls.add('second');
              return true;
            }),
        failures: failures,
        results: results));
    await tester.pumpAndSettle();
    await _tapIfShown(tester, 'Welcome');
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(failures.map((f) => f.reason), ['action_contract_mismatch']);
    expect(results, isEmpty);
    expect(resolver.calls, 2);
  });

  testWidgets('a load failed for a missing binding recovers with a valid one',
      (tester) async {
    final resolver = _CountingResolver(_resolvedFlow(document));
    final failures = <FlowUnavailableError>[];
    await tester
        .pumpWidget(host(resolver, const _NoActions(), failures: failures));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
    await tester.pumpWidget(host(resolver, _Actions(), failures: failures));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsNothing);
    expect(find.text('Welcome'), findsOneWidget);
    expect(failures.map((f) => f.reason), ['action_contract_mismatch']);
    expect(resolver.calls, 2);
  });

  testWidgets('actions null to non-null starts a new load', (tester) async {
    final plain = _resolvedFlow(_flowDocument());
    final resolver = _CountingResolver(plain);
    final starts = <RestageEvent>[];
    final sub = Restage.events.listen((e) {
      if (e is SurfaceLoadStarted) starts.add(e);
    });
    addTearDown(sub.cancel);
    await tester.pumpWidget(host(resolver, null));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(resolver, _Actions()));
    await tester.pumpAndSettle();
    expect(starts, hasLength(2));
    expect(resolver.calls, 2);
  });

  testWidgets(
      'a registry with the same contracts swapped during an action runs the '
      'first handler once', (tester) async {
    final resolver = _CountingResolver(_resolvedFlow(document));
    final calls = <String>[];
    final results = <_Result>[];
    final first = Completer<bool>();
    await tester.pumpWidget(host(resolver, _Actions(handler: (_, __) {
      calls.add('first');
      return first.future;
    }), results: results));
    await tester.pumpAndSettle();
    await _tapIfShown(tester, 'Welcome');
    await tester.pump();
    await tester.pumpWidget(host(resolver, _Actions(handler: (_, __) {
      calls.add('second');
      return true;
    }), results: results));
    await tester.pump();
    // A second tap while the first action runs.
    await _tapIfShown(tester, 'Welcome');
    await tester.pump();
    first.complete(true);
    await tester.pumpAndSettle();
    expect(calls, ['first']);
    expect(results, hasLength(1));
    expect(resolver.calls, 1);
  });

  for (final change in ['drops the action', 'changes its contract']) {
    testWidgets(
        'a registry that $change after the load fails closed when the action '
        'runs', (tester) async {
      final calls = <String>[];
      final failures = <FlowUnavailableError>[];
      final registry = _MutableActions(_Actions(handler: (_, __) {
        calls.add('validated');
        return true;
      }).flowActionBindings);
      await tester.pumpWidget(host(
          _CountingResolver(_resolvedFlow(document)), registry,
          failures: failures));
      await tester.pumpAndSettle();
      // The same object, so the host has nothing to compare.
      registry.bindings = change == 'drops the action'
          ? const {}
          : _Actions(contractVersion: 2).flowActionBindings;
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(failures.map((f) => f.reason), ['action_contract_mismatch']);
    });
  }

  group('a sub-flow', () {
    final child = _flowDocument(
      flow: 'profile_child',
      actions: {'create_profile': _actionContract()},
      states: const {
        'welcome': ScreenFlowState(
          screen: 'welcome',
          on: {
            'next': ActionFlowTransition(
              action: 'create_profile',
              resultPredicate: BoolEqualsActionResultPredicate(value: true),
              target: 'done',
            ),
          },
        ),
        'done': EndFlowState(result: {}),
      },
    );
    final childHash = FlowContentHash.compute(
      utf8.encode(FlowDocumentCodec.encodePrettyJson(child)),
    );
    final parent = _flowDocument(
      states: {
        'welcome': const ScreenFlowState(
          screen: 'welcome',
          on: {'next': FlowTransition.goto('profile')},
        ),
        'profile': SubFlowState(
          flow: 'profile_child',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: childHash,
          input: const {},
          onComplete: const [],
          defaultBranch: const FlowBranchTarget(target: 'done'),
        ),
        'done': const EndFlowState(result: {'completed': true}),
      },
    );
    _MapResolver resolver() => _MapResolver({
          'first_run': _resolvedFlow(parent),
          'profile_child': _resolvedFlow(child, contentHash: childHash),
        });

    testWidgets(
        'runs the newest handler of its own action after a same-contract '
        'registry swap', (tester) async {
      final calls = <String>[];
      final results = <_Result>[];
      final flows = resolver();
      FlowActionRegistry actions(String name) => _Actions(handler: (_, __) {
            calls.add(name);
            return true;
          });
      await tester.pumpWidget(host(flows, actions('first'), results: results));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      // The child's own welcome screen, before its action runs.
      await tester.pumpWidget(host(flows, actions('second'), results: results));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      expect(calls, ['second']);
      expect(results, hasLength(1));
      expect(flows.calls['first_run'], 1);
    });

    testWidgets('fails closed when its own action is dropped', (tester) async {
      final calls = <String>[];
      final failures = <FlowUnavailableError>[];
      final results = <_Result>[];
      final registry = _MutableActions(_Actions(handler: (_, __) {
        calls.add('validated');
        return true;
      }).flowActionBindings);
      await tester.pumpWidget(
          host(resolver(), registry, failures: failures, results: results));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      // The same object, so the host has nothing to compare.
      registry.bindings = const {};
      await tester.tap(find.text('Welcome'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(results, isEmpty);
      // The child fails closed, and the parent reports its sub-flow failed.
      expect(failures.map((f) => f.reason), ['sub_flow_unavailable']);
    });
  });
}

/// Taps [text] when it is shown; a host that failed closed shows none.
Future<void> _tapIfShown(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) return;
  await tester.tap(find.text(text));
}

final class _Result {
  const _Result();

  static _Result decode(Map<String, Object?> result) => const _Result();
}

final class _CountingResolver implements FlowResolver {
  _CountingResolver(this._flow);

  final ResolvedFlow _flow;
  int calls = 0;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    calls++;
    return _flow;
  }
}

final class _NoActions implements FlowActionRegistry {
  const _NoActions();

  @override
  Map<String, FlowActionBinding<dynamic, dynamic>> get flowActionBindings =>
      const {};
}

final class _Actions implements FlowActionRegistry {
  _Actions({FlowActionHandler<void, bool>? handler, int contractVersion = 1})
      : flowActionBindings = {
          'create_profile': FlowActionBinding<void, bool>(
            actionName: 'create_profile',
            contractVersion: contractVersion,
            argsSchema: _emptyArgsSchema,
            resultSchema: _boolResultSchema,
            minClient: 3,
            idempotent: false,
            handler: handler ?? ((_, __) => true),
            decodeArgs: (_) {},
            encodeResult: (value) => value,
          ),
        };

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

const _emptyArgsSchema = FlowActionSchema.object({});
const _boolResultSchema = FlowActionSchema.bool();

FlowActionContract _actionContract() => FlowActionContract(
      actionName: 'create_profile',
      contractVersion: 1,
      argsSchema: _emptyArgsSchema,
      resultSchema: _boolResultSchema,
      minClient: 3,
      idempotent: false,
    );

ResolvedFlow _resolvedFlow(FlowDocument document,
        {FlowContentHash? contentHash}) =>
    ResolvedFlow(
      document: document,
      screenBlobs: {
        'welcome': _screenBlob('Welcome', 'next'),
        'profile': _screenBlob('Profile', 'finish'),
      },
      contentHash: contentHash,
      cacheHit: false,
    );

FlowDocument _flowDocument({
  String flow = 'first_run',
  Map<String, FlowActionContract>? actions,
  Map<String, FlowState>? states,
}) =>
    FlowDocument(
      flow: flow,
      version: 1,
      schemaVersion: 1,
      minClient: 3,
      initial: 'welcome',
      actions: actions ?? const {},
      flowState: const {},
      outbound: const FlowOutboundDeclarations(),
      legacyTerminalResultPassthrough: true,
      screenArtifacts: {
        'welcome': ScreenArtifact(
          path: 'welcome.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash: FlowContentHash.compute(_screenBlob('Welcome', 'next')),
        ),
        'profile': ScreenArtifact(
          path: 'profile.rfw',
          version: 1,
          schemaVersion: 1,
          minClient: 3,
          contentHash:
              FlowContentHash.compute(_screenBlob('Profile', 'finish')),
        ),
      },
      states: states ??
          const {
            'welcome': ScreenFlowState(
              screen: 'welcome',
              on: {'next': FlowTransition.goto('profile')},
            ),
            'profile': ScreenFlowState(
              screen: 'profile',
              on: {'finish': FlowTransition.goto('done')},
            ),
            'done': EndFlowState(result: {'completed': true}),
          },
    );

Uint8List _screenBlob(String text, String event) {
  final source = '''
    import restage.core;
    widget OnboardingScreen = GestureDetector(
      onTap: event "$event" { },
      child: Text(text: "$text")
    );
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

/// A registry whose bindings change without a new object.
final class _MutableActions implements FlowActionRegistry {
  _MutableActions(this.bindings);

  Map<String, FlowActionBinding<dynamic, dynamic>> bindings;

  @override
  Map<String, FlowActionBinding<dynamic, dynamic>> get flowActionBindings =>
      bindings;
}

/// Answers each flow by id and counts the requests per flow.
final class _MapResolver implements FlowResolver {
  _MapResolver(this._flows);

  final Map<String, ResolvedFlow> _flows;
  final calls = <String, int>{};

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    calls.update(flow.id, (count) => count + 1, ifAbsent: () => 1);
    return _flows[flow.id]!;
  }
}

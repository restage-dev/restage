import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';

final class _RecordingChannel implements SurfaceUpdateChannel {
  final controller = StreamController<SurfaceUpdate>.broadcast(sync: true);
  final watched = <SurfaceRef>[];
  var cancelled = 0;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    watched.add(surface);
    late final StreamController<SurfaceUpdate> out;
    StreamSubscription<SurfaceUpdate>? sub;
    out = StreamController<SurfaceUpdate>(
      onListen: () {
        sub = controller.stream
            .where((u) => u.surface == surface)
            .listen(out.add);
      },
      onCancel: () {
        cancelled++;
        return sub?.cancel();
      },
    );
    return out.stream;
  }
}

final class _ThrowingChannel implements SurfaceUpdateChannel {
  var watchCalls = 0;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    watchCalls++;
    throw StateError('broken channel');
  }
}

SurfaceRefreshHandle _handle(
  String slug, {
  Set<SurfaceRefreshTrigger> triggers = const {},
  bool Function()? canSwap,
  int? Function()? renderedVersion,
  bool stampable = false,
  required List<String> refreshed,
}) =>
    SurfaceRefreshHandle(
      surface: SurfaceRef(surfaceType: 'paywall', slug: slug),
      triggers: triggers,
      canSwap: canSwap ?? () => true,
      renderedVersion: renderedVersion,
      stampable: stampable,
      refresh: () async => refreshed.add(slug),
    );

void _configureStampRpc(
  Map<String, int?> versionBySlug, {
  void Function()? onStampRequest,
}) {
  Restage.debugRestageRpcClient = RestageRpcClient(
    baseUrl: 'https://example.com',
    apiKey: 'rs_pk_test',
    httpClient: MockClient((request) async {
      if (request.url.path == '/sdk/v1/surface-stamp') {
        onStampRequest?.call();
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final version = versionBySlug[body['surfaceSlug']];
        if (version == null) {
          return http.Response('{"error":"unavailable"}', 404);
        }
        return http.Response('{"version":$version}', 200);
      }
      return http.Response('{"entitlements":[]}', 200);
    }),
  );
}

void main() {
  tearDown(() {
    SurfaceRefreshRegistry.instance.debugReset();
    Restage.debugReset();
  });

  test('reload() hits all swappable handles regardless of triggers', () async {
    final refreshed = <String>[];
    final a = _handle('a', refreshed: refreshed);
    final b = _handle('b', canSwap: () => false, refreshed: refreshed);
    SurfaceRefreshRegistry.instance
      ..register(a)
      ..register(b);
    await SurfaceRefreshRegistry.instance.reload();
    expect(refreshed, ['a']); // b gated out by canSwap
    await SurfaceRefreshRegistry.instance.reload(slug: 'a');
    expect(refreshed, ['a', 'a']);
  });

  test(
      'onAppResumed() sweeps ambient-triggered handles but skips untriggered '
      'ones (appResume and updateChannel are both swept)', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance
      ..register(_handle('resume',
          triggers: {SurfaceRefreshTrigger.appResume}, refreshed: refreshed))
      ..register(_handle('static', refreshed: refreshed));
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(refreshed, ['resume']);
  });

  test(
      'register subscribes updateChannel-triggered handles; emissions gate '
      'through canSwap; unregister cancels', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    var swappable = true;
    final h = _handle('live',
        triggers: {SurfaceRefreshTrigger.updateChannel},
        canSwap: () => swappable,
        refreshed: refreshed);
    SurfaceRefreshRegistry.instance.register(h);
    expect(channel.watched,
        [const SurfaceRef(surfaceType: 'paywall', slug: 'live')]);

    channel.controller.add(
        const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')));
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']);

    swappable = false;
    channel.controller.add(
        const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')));
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']); // gated

    SurfaceRefreshRegistry.instance.unregister(h);
    expect(channel.cancelled, 1);
    swappable = true;
    channel.controller.add(
        const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')));
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']); // cancelled
  });

  test('onAppBackgrounded cancels update-channel subscriptions', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(_handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      refreshed: refreshed,
    ));
    expect(channel.cancelled, 0);

    SurfaceRefreshRegistry.instance.onAppBackgrounded();
    expect(channel.cancelled, 1);

    channel.controller.add(
      const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, isEmpty);
  });

  test('onAppResumed resubscribes update-channel handles', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    final versionBySlug = <String, int?>{'live': 1};
    _configureStampRpc(versionBySlug);
    SurfaceRefreshRegistry.instance.register(_handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));
    SurfaceRefreshRegistry.instance.onAppBackgrounded();

    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(channel.watched, hasLength(2));
    expect(refreshed, isEmpty);

    versionBySlug['live'] = 2;
    channel.controller.add(
      const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']);
  });

  test('a synchronous channel failure cannot escape register or resume',
      () async {
    final channel = _ThrowingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    final handle = _handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      refreshed: refreshed,
    );

    expect(
      () => SurfaceRefreshRegistry.instance.register(handle),
      returnsNormally,
    );
    await expectLater(
      SurfaceRefreshRegistry.instance.onAppResumed(),
      completes,
    );

    expect(channel.watchCalls, 2);
    expect(refreshed, ['live']);
  });

  test('channel emissions skip the stamp probe', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    var stampChecks = 0;
    _configureStampRpc(
      {'live': 1},
      onStampRequest: () => stampChecks++,
    );
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(_handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));

    channel.controller.add(
      const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(stampChecks, 0);
    expect(refreshed, ['live']);

    await SurfaceRefreshRegistry.instance.reload(slug: 'live');
    expect(stampChecks, 1);
    expect(refreshed, ['live']);
  });

  test(
      'onAppResumed stamp-checks an update-channel handle with a changed stamp',
      () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    _configureStampRpc({'changed': 2});
    SurfaceRefreshRegistry.instance.register(_handle(
      'changed',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));
    SurfaceRefreshRegistry.instance.onAppBackgrounded();

    await SurfaceRefreshRegistry.instance.onAppResumed();

    expect(refreshed, ['changed']);
  });

  test(
      'onAppResumed stamp-checks an update-channel handle with an unchanged stamp',
      () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    var stampChecks = 0;
    _configureStampRpc(
      {'unchanged': 1},
      onStampRequest: () => stampChecks++,
    );
    SurfaceRefreshRegistry.instance.register(_handle(
      'unchanged',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));
    SurfaceRefreshRegistry.instance.onAppBackgrounded();

    await SurfaceRefreshRegistry.instance.onAppResumed();

    expect(stampChecks, 1);
    expect(refreshed, isEmpty);
  });

  test('a non-updateChannel handle opens no subscription', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    SurfaceRefreshRegistry.instance
        .register(_handle('a', refreshed: <String>[]));
    expect(channel.watched, isEmpty);
  });

  test('a throwing refresh is swallowed and does not block siblings', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance
      ..register(SurfaceRefreshHandle(
        surface: const SurfaceRef(surfaceType: 'paywall', slug: 'boom'),
        triggers: const {},
        canSwap: () => true,
        refresh: () async => throw StateError('x'),
      ))
      ..register(_handle('ok', refreshed: refreshed));
    await SurfaceRefreshRegistry.instance.reload();
    expect(refreshed, ['ok']);
  });

  test('a handle whose refresh is in flight is skipped by a second producer',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final h = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'paywall', slug: 'slow'),
      triggers: const {},
      canSwap: () => true,
      refresh: () async {
        calls++;
        await gate.future;
      },
    );
    SurfaceRefreshRegistry.instance.register(h);
    final first = SurfaceRefreshRegistry.instance.reload();
    // Second producer fires while the first refresh is still in flight.
    await SurfaceRefreshRegistry.instance.reload();
    expect(calls, 1); // re-entrancy guard skipped the second
    gate.complete();
    await first;
    // Now that it's settled, a fresh producer fires again.
    await SurfaceRefreshRegistry.instance.reload();
    expect(calls, 2);
  });

  test('stamp equal to rendered version skips refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'same': 5});
    SurfaceRefreshRegistry.instance.register(_handle(
      'same',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, isEmpty);
  });

  test('moved stamp runs refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'moved': 6});
    SurfaceRefreshRegistry.instance.register(_handle(
      'moved',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['moved']);
  });

  test('null stamp runs refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'unknown': null});
    SurfaceRefreshRegistry.instance.register(_handle(
      'unknown',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['unknown']);
  });

  test('non-null stamp with null rendered version runs refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'versionless': 5});
    SurfaceRefreshRegistry.instance.register(_handle(
      'versionless',
      renderedVersion: () => null,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['versionless']);
  });

  test('handle without a stamp probe runs refresh as before', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(
      _handle('legacy', refreshed: refreshed),
    );

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['legacy']);
  });

  test(
      'a stampable handle with no configured service still refreshes '
      '(bundled-only path)', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(_handle(
      'bundled',
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['bundled']);
  });
}

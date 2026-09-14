import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_assignment_persistence.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

final _assignment = CanonicalSurfaceExperimentAssignmentV1(
  experimentId: ExperimentPublicIdV1('experiment.reset'),
  experimentRevisionId: ExperimentPublicRevisionIdV1('revision.reset'),
  experimentEpochId: ExperimentPublicEpochIdV1('epoch.reset'),
  armId: ExperimentPublicArmIdV1('arm.reset'),
  outcomeLinkCarrier: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
);

bool _isAssignmentKey(String key) =>
    key.contains('restage.assignmentRegistration.') ||
    key.contains('restage.assignment.');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ControlledPreferences storage;
  var registrations = 0;
  Future<void> Function()? beforeResponse;

  setUp(() async {
    await Restage.debugResetAndWait();
    SharedPreferences.setMockInitialValues({});
    storage = _ControlledPreferences();
    SharedPreferencesStorePlatform.instance = storage;
    registrations = 0;
    beforeResponse = null;
    Restage.configure(
      apiKey: 'rs_pk_reset',
      baseUrl: 'https://surfaces.example.com',
    );
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_reset',
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('measurement-assignment-credential'));
        final number = ++registrations;
        await beforeResponse?.call();
        return http.Response(
            jsonEncode({
              'credentialHandle': 'ic1.${number.toString().padLeft(64, '0')}',
              'expiresAtMicros': 4102444800000000,
            }),
            200);
      }),
    );
  });

  tearDown(() async {
    storage.failRemoval = false;
    storage.releaseWrite();
    await SurfaceAssignmentPersistence.forget();
    await Restage.debugResetAndWait();
  });

  Future<void> retain(SurfaceAssignmentResolutionLease lease) =>
      SurfaceCanonicalCarrierProvider.retain(
        surface: 'message',
        slug: 'reset',
        lease: lease,
        assignment: _assignment,
      );

  Future<Set<String>> durableKeys() async =>
      (await storage.getAll()).keys.where(_isAssignmentKey).toSet();

  test('reset deletes retired records and keeps unrelated preferences',
      () async {
    final first = await SurfaceAssignmentKeyProvider.captureLease();
    await retain(first);
    final oldKeys = await durableKeys();
    expect(oldKeys, hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host.setting', 'keep');
    await prefs.setString('restage.assignment.other-retired-scope', 'old');

    Restage.reset();
    expect(first.isCurrent, isFalse);
    final second = await SurfaceAssignmentKeyProvider.captureLease();
    expect(second.assignmentKey, isNotNull);
    expect(second.assignmentKey, isNot(first.assignmentKey));
    expect((await durableKeys()).intersection(oldKeys), isEmpty);
    expect(await durableKeys(), hasLength(1));
    await prefs.reload();
    expect(prefs.getString('host.setting'), 'keep');
    expect(
        await SurfaceCanonicalCarrierProvider.heldAssignment(
          surface: 'message',
          slug: 'reset',
          assignmentKey: first.assignmentKey,
        ),
        isNull);
  });

  test('a credential response arriving after reset cannot recreate old state',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeResponse = () {
      entered.complete();
      return release.future;
    };
    final pending = SurfaceAssignmentKeyProvider.captureLease();
    await entered.future;
    Restage.reset();
    await SurfaceAssignmentPersistence.ready;
    expect(await durableKeys(), isEmpty);
    beforeResponse = null;
    final current = await SurfaceAssignmentKeyProvider.captureLease();
    final currentKeys = await durableKeys();
    release.complete();
    final stale = await pending;
    expect(stale.assignmentKey, isNull);
    expect(stale.isCurrent, isFalse);
    expect(current.isCurrent, isTrue);
    expect(await durableKeys(), currentKeys);
  });

  for (final write in [1, 2]) {
    test('reset erases an in-flight credential persistence write $write',
        () async {
      storage.blockRegistrationWrite = write;
      final pending = SurfaceAssignmentKeyProvider.captureLease();
      await storage.writeEntered.future;
      final oldKey = storage.blockedKey!;
      Restage.reset();
      storage.releaseWrite();
      expect((await pending).assignmentKey, isNull);
      await SurfaceAssignmentPersistence.ready;
      expect((await storage.getAll()).containsKey(oldKey), isFalse);
      final current = await SurfaceAssignmentKeyProvider.captureLease();
      expect(current.assignmentKey, isNotNull);
      expect(await durableKeys(), hasLength(1));
    });
  }

  test('reset erases an in-flight assignment write without losing the new one',
      () async {
    final first = await SurfaceAssignmentKeyProvider.captureLease();
    storage.blockAssignmentWrite = true;
    final pending = retain(first);
    await storage.writeEntered.future;
    final oldKey = storage.blockedKey!;
    Restage.reset();
    final next = SurfaceAssignmentKeyProvider.captureLease();
    storage.releaseWrite();
    await pending;
    final second = await next;
    await retain(second);
    expect((await storage.getAll()).containsKey(oldKey), isFalse);
    expect(await durableKeys(), hasLength(2));
    expect(
        await SurfaceCanonicalCarrierProvider.heldAssignment(
          surface: 'message',
          slug: 'reset',
          assignmentKey: second.assignmentKey,
        ),
        isNotNull);
  });

  test('failed erasure blocks enrollment until another explicit reset succeeds',
      () async {
    final first = await SurfaceAssignmentKeyProvider.captureLease();
    await retain(first);
    storage.failRemoval = true;
    Restage.reset();
    await expectLater(SurfaceAssignmentPersistence.ready, throwsStateError);
    expect(await SurfaceAssignmentKeyProvider.resolve(), isNull);
    expect(registrations, 1);
    expect(await durableKeys(), isNotEmpty);
    storage.failRemoval = false;
    Restage.reset();
    await SurfaceAssignmentPersistence.ready;
    expect(await durableKeys(), isEmpty,
        reason: 'reload finds keys removed from the cache by a failed removal');
    expect(await SurfaceAssignmentKeyProvider.resolve(), isNotNull);
  });

  test('cleanup waits for actor persistence before reloading preferences',
      () async {
    await SurfaceAssignmentKeyProvider.captureLease();
    final prefs = await SharedPreferences.getInstance();
    final oldActor = prefs.getString('restage.analytics.anonymous_id');
    storage.blockActorWrite = true;
    Restage.reset();
    await storage.writeEntered.future;
    var cleanupDone = false;
    final cleanup =
        SurfaceAssignmentPersistence.ready.then((_) => cleanupDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(cleanupDone, isFalse);
    storage.releaseWrite();
    await cleanup;
    expect(prefs.getString('restage.analytics.anonymous_id'), isNot(oldActor));
    expect(await durableKeys(), isEmpty);
  });

  test('repeated resets do not accumulate retired records', () async {
    for (var i = 0; i < 3; i++) {
      await retain(await SurfaceAssignmentKeyProvider.captureLease());
      expect(await durableKeys(), hasLength(2));
      Restage.reset();
      Restage.reset();
      await SurfaceAssignmentPersistence.ready;
      expect(await durableKeys(), isEmpty);
    }
  });
}

class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences() : super.empty();
  int? blockRegistrationWrite;
  bool blockAssignmentWrite = false;
  bool blockActorWrite = false;
  bool failRemoval = false;
  int _registrationWrites = 0;
  final writeEntered = Completer<void>();
  final _release = Completer<void>();
  String? blockedKey;

  void releaseWrite() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final block = (key.contains('restage.assignmentRegistration.') &&
            ++_registrationWrites == blockRegistrationWrite) ||
        (key.contains('restage.assignment.') && blockAssignmentWrite) ||
        (key.endsWith('restage.analytics.anonymous_id') && blockActorWrite);
    if (block && !writeEntered.isCompleted) {
      blockedKey = key;
      writeEntered.complete();
      await _release.future;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (failRemoval && _isAssignmentKey(key)) return false;
    return super.remove(key);
  }
}

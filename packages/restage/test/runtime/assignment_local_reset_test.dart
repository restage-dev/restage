import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_assignment_persistence.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../surface_screen/surface_screen_test_support.dart';

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
  late ScreenFixture<String> screenFixture;
  var surfaceRequests = 0;
  var confirmedHandles = 0;
  Future<void> Function()? beforeResponse;

  setUp(() async {
    await Restage.debugResetAndWait();
    SharedPreferences.setMockInitialValues({});
    storage = _ControlledPreferences();
    screenFixture = stringScreenFixture(slug: 'reset');
    SharedPreferencesStorePlatform.instance = storage;
    surfaceRequests = 0;
    confirmedHandles = 0;
    beforeResponse = null;
    Restage.configure(
      apiKey: 'rs_pk_reset',
      baseUrl: 'https://surfaces.example.com',
    );
    final serverNow = DateTime.now().microsecondsSinceEpoch;
    final responseBody = jsonEncode({
      ...SurfaceScreenDeliveryDescriptorV1Codec.encode(
          screenFixture.delivery()),
      'credentialHandle': 'ic1.${'a' * 64}',
      'expiresAtMicros': serverNow + 30 * Duration.microsecondsPerDay,
      'serverNowMicros': serverNow,
    });
    Restage.debugRestageRpcClient = RestageRpcClient(
      baseUrl: 'https://surfaces.example.com',
      apiKey: 'rs_pk_reset',
      httpClient: screenFixture.hostedDelivery.client((request) async {
        expect(request.url.path, '/sdk/v1/surface');
        surfaceRequests++;
        await beforeResponse?.call();
        return http.Response(responseBody, 200);
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

  /// Simulates the store write after a successful folded serve. These tests
  /// exercise local persistence races; the delayed-response case below uses
  /// the actual surface RPC instead.
  Future<SurfaceAssignmentResolutionLease> confirmLease() async {
    final lease = await SurfaceAssignmentKeyProvider.captureLease();
    final registration = lease.registration!;
    final serverNow = DateTime.now().microsecondsSinceEpoch;
    final handle =
        'ic1.${(++confirmedHandles).toRadixString(16).padLeft(64, '0')}';
    expect(
        await lease.confirmRegistration!(
          registration,
          serverNow,
          handle,
          serverNow + 30 * Duration.microsecondsPerDay,
          serverNow,
        ),
        isTrue);
    lease.confirmHandle(handle);
    return lease;
  }

  Future<Set<String>> durableKeys() async =>
      (await storage.getAll()).keys.where(_isAssignmentKey).toSet();

  test('reset deletes retired records and keeps unrelated preferences',
      () async {
    final first = await confirmLease();
    await retain(first);
    final oldKeys = await durableKeys();
    expect(oldKeys, hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host.setting', 'keep');
    await prefs.setString('restage.assignment.other-retired-scope', 'old');

    Restage.reset();
    expect(first.isCurrent, isFalse);
    final second = await SurfaceAssignmentKeyProvider.captureLease();
    expect(second.registration, isNotNull);
    expect(second.registration!.registrationNonce,
        isNot(first.registration!.registrationNonce));
    expect(second.assignmentKey, isNull);
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
    final old = await SurfaceAssignmentKeyProvider.captureLease();
    final pending = Restage.debugRestageRpcClient!.fetchSurfaceScreen(
      SurfaceScreenDeliveryRequest(
        surface: Surface.general,
        slug: 'reset',
        contractVersion: 1,
      ),
      registrationLease: old,
    );
    await entered.future;
    Restage.reset();
    await SurfaceAssignmentPersistence.ready;
    expect(await durableKeys(), isEmpty);
    beforeResponse = null;
    final current = await SurfaceAssignmentKeyProvider.captureLease();
    final currentKeys = await durableKeys();
    release.complete();
    expect(await pending, isA<SurfaceScreenDeliveryInvalidResponse>());
    expect(old.assignmentKey, isNull);
    expect(old.isCurrent, isFalse);
    expect(surfaceRequests, 1);
    expect(current.registration, isNotNull);
    expect(current.assignmentKey, isNull);
    expect(current.isCurrent, isTrue);
    expect(await durableKeys(), currentKeys);

    // The same otherwise-valid response confirms a live registration.
    expect(
      await Restage.debugRestageRpcClient!.fetchSurfaceScreen(
        SurfaceScreenDeliveryRequest(
          surface: Surface.general,
          slug: 'reset',
          contractVersion: 1,
        ),
        registrationLease: current,
      ),
      isA<SurfaceScreenDeliveryAvailable>(),
    );
    expect(current.assignmentKey, 'ic1.${'a' * 64}');
    expect(surfaceRequests, 2);
    expect(screenFixture.hostedDelivery.artifactRequests, hasLength(1));
  });

  for (final write in [1, 2]) {
    test('reset erases an in-flight registration persistence write $write',
        () async {
      storage.blockRegistrationWrite = write;
      final Future<void> pending;
      if (write == 1) {
        pending = SurfaceAssignmentKeyProvider.captureLease().then(
          (lease) => expect(lease.registration, isNull),
        );
      } else {
        final first = await SurfaceAssignmentKeyProvider.captureLease();
        final now = DateTime.now().microsecondsSinceEpoch;
        pending = first.confirmRegistration!(
          first.registration!,
          now,
          'ic1.${'b' * 64}',
          now + 30 * Duration.microsecondsPerDay,
          now,
        )
            .then((accepted) => expect(accepted, isFalse));
      }
      await storage.writeEntered.future;
      final oldKey = storage.blockedKey!;
      Restage.reset();
      storage.releaseWrite();
      await pending;
      await SurfaceAssignmentPersistence.ready;
      expect((await storage.getAll()).containsKey(oldKey), isFalse);
      final current = await SurfaceAssignmentKeyProvider.captureLease();
      expect(current.registration, isNotNull);
      expect(current.registration!.registrationNonce, isNotNull);
      expect(current.assignmentKey, isNull);
      expect(await durableKeys(), hasLength(1));
    });
  }

  test('reset erases an in-flight assignment write without losing the new one',
      () async {
    final first = await confirmLease();
    storage.blockAssignmentWrite = true;
    final pending = retain(first);
    await storage.writeEntered.future;
    final oldKey = storage.blockedKey!;
    Restage.reset();
    final next = SurfaceAssignmentKeyProvider.captureLease();
    storage.releaseWrite();
    await pending;
    final second = await next;
    expect(second.registration, isNotNull);
    final renewed = await confirmLease();
    expect(renewed.registration!.registrationNonce,
        second.registration!.registrationNonce);
    await retain(renewed);
    expect((await storage.getAll()).containsKey(oldKey), isFalse);
    expect(await durableKeys(), hasLength(2));
    expect(
        await SurfaceCanonicalCarrierProvider.heldAssignment(
          surface: 'message',
          slug: 'reset',
          assignmentKey: renewed.assignmentKey,
        ),
        isNotNull);
  });

  test('failed erasure blocks enrollment until another explicit reset succeeds',
      () async {
    final first = await confirmLease();
    await retain(first);
    storage.failRemoval = true;
    Restage.reset();
    await expectLater(SurfaceAssignmentPersistence.ready, throwsStateError);
    expect((await SurfaceAssignmentKeyProvider.captureLease()).registration,
        isNull);
    expect(surfaceRequests, 0);
    expect(await durableKeys(), isNotEmpty);
    storage.failRemoval = false;
    Restage.reset();
    await SurfaceAssignmentPersistence.ready;
    expect(await durableKeys(), isEmpty,
        reason: 'reload finds keys removed from the cache by a failed removal');
    expect((await SurfaceAssignmentKeyProvider.captureLease()).registration,
        isNotNull);
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
      await retain(await confirmLease());
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

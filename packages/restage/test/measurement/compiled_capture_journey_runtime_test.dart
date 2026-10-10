import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/measurement/measurement_capture_edge.dart';
import 'package:restage/src/measurement/measurement_host_construction_owner.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_test_support.dart' show StaticFlowResolver;
import '../support/restage_runtime_test_support.dart';

/// Invoked by the persisted backend proof with its actual accepted publication.
/// The only handoff is canonical input/output files; no occurrences are authored
/// here. Real generated controls, host callbacks and the native worker collect.
void main() {
  installRestageRuntimeTestSupport();
  final inputPath = Platform.environment['MEASUREMENT_RUNTIME_INPUT'];
  testWidgets('compiled journey emits the real worker request', (tester) async {
    final decodedInput = jsonDecode(File(inputPath!).readAsStringSync());
    if (decodedInput is! Map<String, dynamic>) {
      throw const FormatException('Runtime bridge input must be an object');
    }
    final input = decodedInput.cast<String, Object?>();
    void stage(String value) => File('${input['outputPath']}.progress')
        .writeAsStringSync('$value\n', mode: FileMode.append);
    final diagnosticScenario = input['diagnosticScenario'];
    if (diagnosticScenario != null) {
      await _runPresentationDiagnosticJourney(
        tester,
        input: input,
        stage: stage,
      );
      return;
    }
    stage('decoding actual publication');
    final publication = MeasurementPublicationBindingV1.fromCanonicalBytes(
        base64Decode(input['bindingBase64'] as String));
    final attestation = RegisteredPublicationAttestationV1.fromCanonicalBytes(
        base64Decode(input['attestationBase64'] as String));
    final context = ExactMeasurementPublicationContextRefV1.fromCanonicalBytes(
        base64Decode(input['contextBase64'] as String));
    final payload =
        SurfacePayload.decode(base64Decode(input['payloadBase64'] as String))
            as FlowSurfacePayload;
    final accepted = MeasurementPublicationBindingReadAccepted(
        reference: attestation.bindingReference,
        binding: publication,
        registeredPublicationAttestation: attestation);
    final resolved = attachMeasurementPublicationBindingReference(
        ResolvedFlow(
            document: payload.flowDocument,
            screenBlobs: payload.screenBlobs,
            cacheHit: false),
        attestation.bindingReference);
    final observed = <String>[];
    late Zone realZone;
    late HttpServer server;
    late Directory support;
    await tester.runAsync(() async {
      realZone = Zone.current;
      support =
          await Directory.systemTemp.createTemp('capture-journey-worker-');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final raw = body['canonicalRequestBase64'] as String;
        observed.add(raw);
        stage(
            "worker request observed: final=${MeasurementIngestRequestV1.fromBase64(raw).factFrame.isFinal}");
        // This observer is not the ingest authority. The backend forwards these
        // exact bytes to authenticated ingest and obtains its actual receipt.
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
    });
    final owner = MeasurementHostConstructionOwner.forTesting(
        profileReadPort: _Profile(MeasurementHostConstructionProfile(
            publicationContext: context,
            endpoint: 'http://127.0.0.1:${server.port}/sdk/v1/measurement',
            analyticsEnabled: true,
            policyStatus: MeasurementHostConstructionPolicyStatus.supported,
            measurementClassAdmitted: true,
            remainingSessionBudget: 16,
            deliveryAdapterAvailable: true,
            configurationFingerprint: 'actual-compiled-journey-runtime.v1')),
        pathResolver: _Path(support.path),
        monotonicClock: _Clock(),
        workerRuntimeStarter: (
                {required configuration, required pathResolver}) =>
            realZone.run(() async {
              stage('starting native worker');
              final result = await MeasurementWorkerOwnedDeliveryRuntime.start(
                  configuration: configuration, pathResolver: pathResolver);
              stage('native worker started: ${result.outcome}');
              return result.runtime;
            }));
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
        MeasurementHostSessionConstructionAuthority
            .forWorkerOwnedDeliveryTesting(
                constructionOwner: owner,
                nonceBytesSource:
                    MeasurementHostSessionConstructionAuthority.production(
                            constructionOwner: owner)
                        .takeNonceBytes,
                hostedBindingReadPortLookup: () => _Binding(accepted)));
    var completed = false;
    try {
      stage('mounting compiled flow');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RestageFlowGraph<Map<String, Object?>>(
                  flow: const SurfaceFlowRef(
                      id: 'capture_journey',
                      version: 1,
                      minClient: 3,
                      surface: Surface.survey,
                      decodeResult: _decode),
                  resolver: StaticFlowResolver(resolved),
                  unavailable:
                      FlowUnavailablePolicy.fallback(builder: (_, error) {
                    stage('flow unavailable: $error');
                    return Text('unavailable:${error.reason}');
                  }),
                  onComplete: (_) {
                    completed = true;
                  }))));
      await _settleReal(
          tester, () => find.text('Continue').evaluate().isNotEmpty);
      stage('tapping rendered Continue');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      Finder finalControl() => find.text('Finish').evaluate().isNotEmpty
          ? find.text('Finish')
          : find.text('Continue');
      await _settleReal(tester, () => finalControl().evaluate().isNotEmpty);
      stage('tapping rendered terminal control');
      await tester.tap(finalControl());
      await tester.pumpAndSettle();
      await _settleReal(
          tester,
          () =>
              completed &&
              observed.any((raw) => MeasurementIngestRequestV1.fromBase64(raw)
                  .factFrame
                  .isFinal));
      final raw = observed.lastWhere((raw) =>
          MeasurementIngestRequestV1.fromBase64(raw).factFrame.isFinal);
      final frame = MeasurementIngestRequestV1.fromBase64(raw).factFrame;
      final answers = [
        for (final fact in frame.facts)
          for (final occurrence in fact.timedOccurrencesV1 ?? [])
            if (occurrence.answerValueV1 != null)
              occurrence.answerValueV1!.toJson(),
      ];
      expect(
          answers,
          unorderedEquals([
            {'kind': 'category', 'value': 'alpha'},
            {'kind': 'scaledDecimal', 'coefficient': '3', 'scale': 0},
          ]));
      File(input['outputPath'] as String)
          .writeAsStringSync(jsonEncode({'canonicalRequestBase64': raw}));
    } finally {
      stage('disposing flow');
      await tester.pumpWidget(const SizedBox.shrink());
      restore();
      var closed = false;
      final closing = owner.close().whenComplete(() {
        closed = true;
      });
      await _settleReal(tester, () => closed);
      await closing;
      await tester.runAsync(() async {
        await server.close(force: true);
        await support.delete(recursive: true);
      });
    }
  }, skip: inputPath == null);
}

Map<String, Object?> _decode(Map<String, Object?> value) => value;
Future<void> _settleReal(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!ready()) debugDumpApp();
  expect(ready(), isTrue,
      reason: 'Actual flow/worker did not reach next source boundary');
}

Future<void> _runPresentationDiagnosticJourney(
  WidgetTester tester, {
  required Map<String, Object?> input,
  required void Function(String) stage,
}) async {
  final scenario = switch (input['diagnosticScenario']) {
    'rootlessStep' => _PresentationDiagnosticScenario.rootlessStep,
    'duplicateRootPaint' => _PresentationDiagnosticScenario.duplicateRootPaint,
    _ => throw StateError('Unknown presentation diagnostic scenario'),
  };
  stage('decoding actual publication for ${scenario.name}');
  final publication = MeasurementPublicationBindingV1.fromCanonicalBytes(
    base64Decode(input['bindingBase64'] as String),
  );
  final attestation = RegisteredPublicationAttestationV1.fromCanonicalBytes(
    base64Decode(input['attestationBase64'] as String),
  );
  final context = ExactMeasurementPublicationContextRefV1.fromCanonicalBytes(
    base64Decode(input['contextBase64'] as String),
  );
  final accepted = MeasurementPublicationBindingReadAccepted(
    reference: attestation.bindingReference,
    binding: publication,
    registeredPublicationAttestation: attestation,
  );
  final proxy = _AuthenticatedIngestProxy(
    endpoint: Uri.parse(input['authenticatedIngestEndpoint'] as String),
    bearerToken: input['authenticatedBearerToken'] as String,
    stage: stage,
  );
  late Zone realZone;
  late HttpServer server;
  late Directory support;
  await tester.runAsync(() async {
    realZone = Zone.current;
    support = await Directory.systemTemp.createTemp(
      'presentation-diagnostic-worker-',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      unawaited(proxy.forward(request));
    });
  });
  final owner = MeasurementHostConstructionOwner.forTesting(
    profileReadPort: _Profile(
      MeasurementHostConstructionProfile(
        publicationContext: context,
        endpoint: 'http://127.0.0.1:${server.port}/sdk/v1/measurement',
        analyticsEnabled: true,
        policyStatus: MeasurementHostConstructionPolicyStatus.supported,
        measurementClassAdmitted: true,
        presentationMetadataAdmitted: true,
        remainingSessionBudget: 16,
        deliveryAdapterAvailable: true,
        configurationFingerprint: 'actual-presentation-diagnostic-runtime.v1',
      ),
    ),
    pathResolver: _Path(support.path),
    monotonicClock: _Clock(),
    workerRuntimeStarter: ({required configuration, required pathResolver}) =>
        realZone.run(() async {
      stage('starting native diagnostic worker');
      final result = await MeasurementWorkerOwnedDeliveryRuntime.start(
        configuration: configuration,
        pathResolver: pathResolver,
      );
      stage('native diagnostic worker started: ${result.outcome}');
      return result.runtime;
    }),
  );
  final restore = MeasurementHostSessionConstructionRegistry.installForTest(
    MeasurementHostSessionConstructionAuthority.forWorkerOwnedDeliveryTesting(
      constructionOwner: owner,
      nonceBytesSource: MeasurementHostSessionConstructionAuthority.production(
        constructionOwner: owner,
      ).takeNonceBytes,
      hostedBindingReadPortLookup: () => _Binding(accepted),
    ),
  );
  try {
    stage('opening actual presentation attempt');
    final session = (await tester.runAsync(
      () => MeasurementHostSessionController.open(
        MeasurementHostSessionOpenRequest.hosted(
          bindingReference: attestation.bindingReference,
          bindingReadPort: _Binding(accepted),
        ),
      ),
    ))!;
    expect(session.debugState, MeasurementHostSessionDebugState.active);
    final construction = session.debugConstructionSession;
    expect(construction, isNotNull);
    final childScreenId = _diagnosticChildScreenId(publication);
    switch (scenario) {
      case _PresentationDiagnosticScenario.rootlessStep:
        stage('recording actual rootless child step');
        construction!.recordLifecycle(
          MeasurementOccurrenceChannelV1.presentation,
          screenId: childScreenId,
        );
      case _PresentationDiagnosticScenario.duplicateRootPaint:
        stage('mounting two actual root presentation hooks');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                session.wrapRootSubtree(
                  const SizedBox(width: 10, height: 10),
                ),
                session.wrapRootSubtree(
                  const SizedBox(width: 10, height: 10),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        construction!.recordLifecycle(
          MeasurementOccurrenceChannelV1.presentation,
          screenId: childScreenId,
        );
    }
    stage('tearing down actual presentation attempt');
    await tester.runAsync(session.teardown);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final expectedDeliveries =
        scenario == _PresentationDiagnosticScenario.rootlessStep ? 1 : 2;
    await _settleReal(
      tester,
      () =>
          proxy.failureKind != null ||
          proxy.deliveries.length == expectedDeliveries,
    );
    expect(proxy.failureKind, isNull);
    _assertActualPresentationDiagnostic(
      scenario: scenario,
      deliveries: proxy.deliveries,
      attestation: attestation,
    );
    File(input['outputPath'] as String).writeAsStringSync(
      jsonEncode({
        'diagnosticChildScreenId': childScreenId,
        'deliveries': [
          for (final delivery in proxy.deliveries) delivery.toJson(),
        ],
      }),
    );
  } finally {
    stage('disposing presentation diagnostic attempt');
    await tester.pumpWidget(const SizedBox.shrink());
    restore();
    var closed = false;
    final closing = owner.close().whenComplete(() {
      closed = true;
    });
    await _settleReal(tester, () => closed);
    await closing;
    await tester.runAsync(() async {
      await server.close(force: true);
      await support.delete(recursive: true);
    });
  }
}

String _diagnosticChildScreenId(MeasurementPublicationBindingV1 publication) {
  final orderedCapture = publication.orderedCaptureV1;
  if (orderedCapture == null) {
    throw StateError('Presentation diagnostic requires ordered capture routes');
  }
  for (final route in orderedCapture.routes) {
    final lifecycle = route.lifecycle;
    if (lifecycle?.channel == MeasurementOccurrenceChannelV1.presentation &&
        lifecycle?.screenId != null) {
      return lifecycle!.screenId!;
    }
  }
  throw StateError('Presentation diagnostic requires a declared child screen');
}

void _assertActualPresentationDiagnostic({
  required _PresentationDiagnosticScenario scenario,
  required List<_ForwardedDelivery> deliveries,
  required RegisteredPublicationAttestationV1 attestation,
}) {
  for (final delivery in deliveries) {
    expect(
      delivery.responseStatusCode,
      HttpStatus.ok,
      reason: delivery.responseReason ?? 'no bounded backend refusal reason',
    );
    final receipt = delivery.receipt;
    expect(receipt, isNotNull);
    expect(receipt!.sequence, delivery.sequence);
    final request = delivery.request;
    if (request != null) {
      expect(receipt.requestSha256, request.requestSha256);
    }
    final diagnosticRequest = delivery.diagnosticRequest;
    if (diagnosticRequest != null) {
      expect(receipt.requestSha256, diagnosticRequest.requestSha256);
    }
  }
  final diagnostic = deliveries
      .singleWhere((delivery) => delivery.diagnosticRequest != null)
      .diagnosticRequest!;
  expect(
    diagnostic.publicationBindingReference.canonicalBytes,
    orderedEquals(attestation.bindingReference.canonicalBytes),
  );
  final summary = diagnostic.diagnostic;
  expect(summary.stepObserved, isTrue);
  expect(summary.captureIncomplete, isFalse);
  switch (scenario) {
    case _PresentationDiagnosticScenario.rootlessStep:
      expect(deliveries, hasLength(1));
      expect(diagnostic.sequence, 1);
      expect(
        summary.rootPresentationReports,
        MeasurementRootPresentationReportsV1.none,
      );
      expect(
        summary.finishReason,
        MeasurementPresentationFinishReasonV1.abandoned,
      );
    case _PresentationDiagnosticScenario.duplicateRootPaint:
      expect(deliveries, hasLength(2));
      final frame = deliveries.first.request;
      expect(frame, isNotNull);
      expect(frame!.factFrame.isFinal, isTrue);
      expect(frame.factFrame.sequence, 1);
      expect(diagnostic.sequence, 2);
      expect(
        diagnostic.captureSessionNonce,
        frame.factFrame.captureSessionNonce,
      );
      expect(
        summary.rootPresentationReports,
        MeasurementRootPresentationReportsV1.many,
      );
      expect(
        summary.finishReason,
        MeasurementPresentationFinishReasonV1.committed,
      );
  }
}

enum _PresentationDiagnosticScenario { rootlessStep, duplicateRootPaint }

/// Forwards byte-identical native worker bodies to the actual authenticated
/// backend endpoint and returns its unchanged response to the worker.
final class _AuthenticatedIngestProxy {
  _AuthenticatedIngestProxy({
    required this.endpoint,
    required this.bearerToken,
    required this.stage,
  });

  final Uri endpoint;
  final String bearerToken;
  final void Function(String) stage;
  final List<_ForwardedDelivery> deliveries = <_ForwardedDelivery>[];
  String? failureKind;

  Future<void> forward(HttpRequest incoming) async {
    final client = _actualAuthenticatedIngestClient();
    try {
      final exactBody = await _readBytes(incoming);
      final outgoing = await client.postUrl(endpoint);
      outgoing
        ..followRedirects = false
        ..contentLength = exactBody.length
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          incoming.headers.contentType?.toString() ?? 'application/json',
        )
        ..headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      outgoing.add(exactBody);
      final response = await outgoing.close();
      final responseBody = await _readBytes(response);
      final delivery = _ForwardedDelivery.fromExactWorkerBody(
        exactBody,
        responseStatusCode: response.statusCode,
        responseBody: responseBody,
        responseReason: _boundedResponseReason(responseBody),
      );
      deliveries.add(delivery);
      incoming.response.statusCode = response.statusCode;
      final contentType = response.headers.contentType;
      if (contentType != null) {
        incoming.response.headers.contentType = contentType;
      }
      incoming.response.add(responseBody);
      await incoming.response.close();
      stage(
        'authenticated ${delivery.kind} response ${delivery.responseStatusCode} '
        'at sequence ${delivery.sequence}',
      );
    } on Object catch (error) {
      failureKind ??= error.runtimeType.toString();
      stage('authenticated ingest proxy failed: $failureKind');
      incoming.response.statusCode = HttpStatus.badGateway;
      await incoming.response.close();
    } finally {
      client.close(force: true);
    }
  }
}

/// Flutter's widget-test binding replaces its global [HttpClient] with a 400
/// responder. Construct only the bridge's outbound client under the native IO
/// factory, then immediately restore that test binding for the rest of the
/// runtime journey.
HttpClient _actualAuthenticatedIngestClient() {
  final widgetTestHttpOverrides = HttpOverrides.current;
  HttpOverrides.global = null;
  try {
    return HttpClient()..autoUncompress = false;
  } finally {
    HttpOverrides.global = widgetTestHttpOverrides;
  }
}

Future<Uint8List> _readBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

final class _ForwardedDelivery {
  _ForwardedDelivery._({
    required this.kind,
    required this.canonicalRequestBase64,
    required this.sequence,
    required this.responseStatusCode,
    this.responseReason,
    this.request,
    this.diagnosticRequest,
    this.receipt,
  });

  factory _ForwardedDelivery.fromExactWorkerBody(
    List<int> exactBody, {
    required int responseStatusCode,
    required List<int> responseBody,
    required String? responseReason,
  }) {
    final envelope = jsonDecode(utf8.decode(exactBody)) as Map;
    final canonicalRequestBase64 = envelope['canonicalRequestBase64'];
    if (canonicalRequestBase64 is! String) {
      throw const FormatException('Worker body omitted canonical request');
    }
    final receipt = _actualReceipt(
      responseBody,
      responseStatusCode: responseStatusCode,
    );
    try {
      final request =
          MeasurementIngestRequestV1.fromBase64(canonicalRequestBase64);
      return _ForwardedDelivery._(
        kind: 'frame',
        canonicalRequestBase64: canonicalRequestBase64,
        sequence: request.factFrame.sequence,
        responseStatusCode: responseStatusCode,
        responseReason: responseReason,
        request: request,
        receipt: receipt,
      );
    } on Object {
      final diagnostic = MeasurementPresentationDiagnosticRequestV1.fromBase64(
        canonicalRequestBase64,
      );
      return _ForwardedDelivery._(
        kind: 'presentationDiagnostic',
        canonicalRequestBase64: canonicalRequestBase64,
        sequence: diagnostic.sequence,
        responseStatusCode: responseStatusCode,
        responseReason: responseReason,
        diagnosticRequest: diagnostic,
        receipt: receipt,
      );
    }
  }

  final String kind;
  final String canonicalRequestBase64;
  final int sequence;
  final int responseStatusCode;
  final String? responseReason;
  final MeasurementIngestRequestV1? request;
  final MeasurementPresentationDiagnosticRequestV1? diagnosticRequest;
  final MeasurementIngestReceiptV1? receipt;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'canonicalRequestBase64': canonicalRequestBase64,
        'sequence': sequence,
        'responseStatusCode': responseStatusCode,
        if (receipt != null)
          'receiptCanonicalBase64': receipt!.canonicalReceiptBase64,
      };
}

/// Returns only the route's closed refusal vocabulary, never a raw body.
String? _boundedResponseReason(List<int> responseBody) {
  try {
    final decoded = jsonDecode(utf8.decode(responseBody));
    if (decoded is! Map) return null;
    final candidate = decoded['reason'] ?? decoded['error'];
    return candidate is String &&
            RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(candidate)
        ? candidate
        : null;
  } on Object {
    return null;
  }
}

MeasurementIngestReceiptV1? _actualReceipt(
  List<int> responseBody, {
  required int responseStatusCode,
}) {
  if (responseStatusCode < HttpStatus.ok ||
      responseStatusCode >= HttpStatus.multipleChoices) {
    return null;
  }
  try {
    final envelope = jsonDecode(utf8.decode(responseBody)) as Map;
    final carrier = envelope['receiptCanonicalBase64'];
    return carrier is String
        ? MeasurementIngestReceiptV1.fromBase64(carrier)
        : null;
  } on Object {
    return null;
  }
}

final class _Clock implements MeasurementCaptureMonotonicClock {
  int micros = 0;
  @override
  int readMicros() => micros += 1000;
}

final class _Path implements MeasurementWorkerOwnedDeliveryPathResolver {
  _Path(this.path);
  final String path;
  @override
  Future<String> resolveApplicationSupportPath() async => path;
}

final class _Profile implements MeasurementHostConstructionProfileReadPort {
  _Profile(this.profile);
  final MeasurementHostConstructionProfile profile;
  @override
  Future<MeasurementHostConstructionProfileReadResult> readExact(
      ExactMeasurementPublicationContextRefV1 context) async {
    expect(context, profile.publicationContext);
    return MeasurementHostConstructionProfileReadAccepted(profile);
  }
}

final class _Binding implements MeasurementPublicationBindingReadPort {
  _Binding(this.accepted);
  final MeasurementPublicationBindingReadAccepted accepted;
  @override
  Future<MeasurementPublicationBindingReadResult> readExact(
      MeasurementPublicationBindingReferenceV1 reference) async {
    expect(reference, accepted.reference);
    return accepted;
  }
}

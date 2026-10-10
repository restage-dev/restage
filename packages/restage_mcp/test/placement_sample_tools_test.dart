import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_shared/restage_shared.dart'
    show PlacementSampleStatusV1, PlacementSampleDeletionStatusV1;
import 'package:test/test.dart';

import '_support/delivery_fixtures.dart';
import '_support/fake_backend.dart';
import '_support/harness.dart';

void main() {
  late Directory home;
  late FileCredentialStore store;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('sample-tools-');
    store = FileCredentialStore('${home.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'http://localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:sample_tool_session_token_value',
      ),
    );
  });
  tearDown(() => home.delete(recursive: true));

  test(
    'registered local import has explicit content and never mutates; complete handoff reaches all sample RPCs',
    () async {
      final png = samplePng();
      final draft = sampleDraft(sampleTarget(), png);
      final ticket = sampleTicket(draft);
      final stored = PlacementSampleStoredV1(
        sampleId: sampleId,
        manifestDigest: draft.manifestDigest,
        imageSha256: draft.manifest.pngSha256,
      );
      final ref = PlacementScreenSampleRefV1(
        target: sampleTarget(),
        sampleId: sampleId,
        appBuildContractHash: draft.manifest.appBuildContractHash,
        manifestDigest: draft.manifestDigest,
        imageSha256: draft.manifest.pngSha256,
        screenLabel: 'Welcome',
        bindingRevision: 2,
      );
      final responses = <List<int>>[
        ticket.canonicalBytes,
        stored.canonicalBytes,
        ref.canonicalBytes,
        PlacementSampleReadResultV1(
          sampleId: sampleId,
          status: PlacementSampleStatusV1.bound,
          manifest: draft.manifest,
          ref: ref,
          bindingRevision: 2,
        ).canonicalBytes,
        png,
        PlacementSampleDeleteResultV1(
          sampleId: sampleId,
          status: PlacementSampleDeletionStatusV1.removed,
          bindingRevision: 3,
        ).canonicalBytes,
      ];
      final calls = <BackendCall>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend((call) async {
          expect(call.endpoint, 'placementSample');
          expect(responses, isNotEmpty, reason: 'Unexpected extra sample RPC');
          return http.Response(
            jsonEncode(encodeByteDataWire(responses.removeAt(0))),
            200,
          );
        }, calls: calls),
      );
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_placement_sample_import',
          arguments: {
            ...targetArguments(),
            'captureJson': utf8.decode(sampleCapture(png).canonicalBytes),
            'pngBase64': base64Encode(png),
          },
        ),
      );
      expect(result.isError ?? false, isFalse);
      expect(text(result), utf8.decode(draft.canonicalBytes));
      expect(calls.where((c) => c.endpoint == 'placementSample'), isEmpty);
      final requests = <(String, Map<String, Object?>)>[
        (
          'prepare',
          {
            'draftJson': text(result),
            'pngBase64': base64Encode(png),
            'reviewedDigest': draft.reviewedDigest,
            'operationId': operationId,
          },
        ),
        (
          'store',
          {
            'ticketJson': utf8.decode(ticket.canonicalBytes),
            'pngBase64': base64Encode(png),
          },
        ),
        (
          'bind',
          {
            'storedJson': utf8.decode(stored.canonicalBytes),
            'operationId': operationId,
            'expectedBindingRevision': 1,
          },
        ),
        ('read', {'sampleId': sampleId}),
        ('read_image', {'sampleId': sampleId}),
        (
          'delete',
          {
            'sampleId': sampleId,
            'operationId': operationId,
            'expectedBindingRevision': 2,
          },
        ),
      ];
      for (final (name, args) in requests) {
        final output = await connection.callTool(
          CallToolRequest(
            name: 'restage_placement_sample_$name',
            arguments: {...targetArguments(), ...args},
          ),
        );
        expect(output.isError ?? false, isFalse, reason: text(output));
        if (name == 'read_image') {
          expect(jsonDecode(text(output))['pngBase64'], base64Encode(png));
        }
      }
      final rpc = calls.where((c) => c.endpoint == 'placementSample').toList();
      expect(rpc.map((c) => c.method), [
        'prepare',
        'store',
        'bind',
        'read',
        'readImage',
        'delete',
      ]);
      for (final call in rpc) {
        expect(call.body['environmentTargetId'], 42);
        expect(call.body['runtimePlane'], 'sandbox');
        expect(call.body['organizationId'], 7);
      }
      expect(
        decodeByteDataWire(
          rpc[1].body['pngBytes'],
          malformed: FormatException.new,
        ),
        png,
      );
      final tools = (await connection.listTools(ListToolsRequest())).tools;
      for (final tool in tools.where(
        (t) => t.name.startsWith('restage_placement_sample'),
      )) {
        expect(
          tool.inputSchema.properties,
          isNot(contains('projectDirectory')),
        );
        expect(tool.inputSchema.properties, isNot(contains('path')));
        expect(tool.inputSchema.additionalProperties, false);
      }
    },
  );

  test(
    'sample prepare live guard refuses before mutation and accepts the same valid arguments',
    () async {
      final png = samplePng();
      final draft = sampleDraft(sampleTarget(live: true), png);
      final calls = <BackendCall>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend(
          (call) async => http.Response(
            jsonEncode(encodeByteDataWire(sampleTicket(draft).canonicalBytes)),
            200,
          ),
          calls: calls,
        ),
      );
      final args = {
        ...targetArguments(live: true),
        'draftJson': utf8.decode(draft.canonicalBytes),
        'pngBase64': base64Encode(png),
        'reviewedDigest': draft.reviewedDigest,
        'operationId': operationId,
      };
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_placement_sample_prepare',
          arguments: args,
        ),
      );
      expect(refused.isError, true);
      expect(text(refused), contains('confirmLive'));
      expect(calls.where((c) => c.endpoint == 'placementSample'), isEmpty);
      final accepted = await connection.callTool(
        CallToolRequest(
          name: 'restage_placement_sample_prepare',
          arguments: {...args, 'confirmLive': true},
        ),
      );
      expect(accepted.isError ?? false, false, reason: text(accepted));
      expect(
        calls.where(
          (c) => c.endpoint == 'placementSample' && c.method == 'prepare',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'changed PNG after review is refused before store while original bytes reach the registered handler',
    () async {
      final png = samplePng();
      final draft = sampleDraft(sampleTarget(), png);
      final calls = <BackendCall>[];
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend(
          (call) async => http.Response(
            jsonEncode(
              encodeByteDataWire(
                PlacementSampleStoredV1(
                  sampleId: sampleId,
                  manifestDigest: draft.manifestDigest,
                  imageSha256: draft.manifest.pngSha256,
                ).canonicalBytes,
              ),
            ),
            200,
          ),
          calls: calls,
        ),
      );
      final args = {
        ...targetArguments(),
        'ticketJson': utf8.decode(sampleTicket(draft).canonicalBytes),
      };
      final refused = await connection.callTool(
        CallToolRequest(
          name: 'restage_placement_sample_store',
          arguments: {...args, 'pngBase64': base64Encode(samplePng(255))},
        ),
      );
      expect(refused.isError, true);
      expect(calls.where((c) => c.endpoint == 'placementSample'), isEmpty);
      final accepted = await connection.callTool(
        CallToolRequest(
          name: 'restage_placement_sample_store',
          arguments: {...args, 'pngBase64': base64Encode(png)},
        ),
      );
      expect(accepted.isError ?? false, false, reason: text(accepted));
      expect(
        calls.where(
          (c) => c.endpoint == 'placementSample' && c.method == 'store',
        ),
        hasLength(1),
      );
    },
  );
}

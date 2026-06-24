import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show AssetBundle;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

@internal
typedef BundledFlowErrorFactory = Object Function(
  String reason,
  String message, [
  Object? cause,
]);

@internal
final class BundledFlowArtifacts {
  const BundledFlowArtifacts({
    required this.documentBytes,
    required this.documentHash,
    required this.document,
    required this.screenBlobs,
  });

  final Uint8List documentBytes;
  final FlowContentHash documentHash;
  final FlowDocument document;
  final Map<String, Uint8List> screenBlobs;
}

@internal
Future<BundledFlowArtifacts> loadBundledFlowArtifacts({
  required AssetBundle bundle,
  required String flowJsonPath,
  required String screenAssetPathPrefix,
  required String flowId,
  required int supportedMinClient,
  required BundledFlowErrorFactory buildError,
  int? expectedVersion,
  String clientDescription = 'requested client',
}) async {
  final documentBytes = await _loadBytes(
    bundle,
    flowJsonPath,
    missingReason: 'missing_flow_json',
    buildError: buildError,
  );
  final documentHash = FlowContentHash.compute(documentBytes);
  final document = _decode(
    flowId: flowId,
    bytes: documentBytes,
    buildError: buildError,
  );

  _checkCompatibility(
    document: document,
    flowId: flowId,
    expectedVersion: expectedVersion,
    supportedMinClient: supportedMinClient,
    clientDescription: clientDescription,
    buildError: buildError,
  );
  _checkValidation(document, buildError);

  final screenBlobs = <String, Uint8List>{};
  for (final entry in document.screenArtifacts.entries) {
    final screenId = entry.key;
    final artifact = entry.value;
    final path = '$screenAssetPathPrefix/${artifact.path}';
    final bytes = await _loadBytes(
      bundle,
      path,
      missingReason: 'missing_screen_blob',
      buildError: buildError,
    );
    final actualHash = FlowContentHash.compute(bytes);
    if (actualHash != artifact.contentHash) {
      throw buildError(
        'hash_mismatch',
        artifact.contentHash.diagnosticForMismatch(
          path: path,
          actual: actualHash,
        ),
      );
    }
    screenBlobs[screenId] = bytes;
  }

  return BundledFlowArtifacts(
    documentBytes: documentBytes,
    documentHash: documentHash,
    document: document,
    screenBlobs: screenBlobs,
  );
}

Future<Uint8List> _loadBytes(
  AssetBundle bundle,
  String path, {
  required String missingReason,
  required BundledFlowErrorFactory buildError,
}) async {
  try {
    final data = await bundle.load(path);
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } on FlutterError catch (e) {
    throw buildError(missingReason, 'Missing flow asset "$path".', e);
  } on Object catch (e) {
    throw buildError('load_failed', 'Failed to load "$path": $e.', e);
  }
}

FlowDocument _decode({
  required String flowId,
  required Uint8List bytes,
  required BundledFlowErrorFactory buildError,
}) {
  try {
    return FlowDocumentCodec.decodeJson(utf8.decode(bytes));
  } on Object catch (e) {
    throw buildError(
      'decode_failed',
      'Failed to decode flow JSON for "$flowId": $e.',
      e,
    );
  }
}

void _checkCompatibility({
  required FlowDocument document,
  required String flowId,
  required int? expectedVersion,
  required int supportedMinClient,
  required String clientDescription,
  required BundledFlowErrorFactory buildError,
}) {
  if (document.flow != flowId) {
    throw buildError(
      'flow_mismatch',
      'Flow JSON id "${document.flow}" does not match requested '
          'flow "$flowId".',
    );
  }
  if (expectedVersion != null && document.version != expectedVersion) {
    throw buildError(
      'version_mismatch',
      'Flow JSON version ${document.version} does not match requested '
          'version $expectedVersion.',
    );
  }
  if (document.schemaVersion != 1) {
    throw buildError(
      'unsupported_schema_version',
      'Unsupported flow schemaVersion ${document.schemaVersion}.',
    );
  }
  if (document.minClient > supportedMinClient) {
    throw buildError(
      'unsupported_min_client',
      'Flow minClient ${document.minClient} exceeds $clientDescription '
          '$supportedMinClient.',
    );
  }

  for (final entry in document.screenArtifacts.entries) {
    final artifact = entry.value;
    if (artifact.schemaVersion != 1) {
      throw buildError(
        'unsupported_schema_version',
        'Unsupported screen artifact schemaVersion '
            '${artifact.schemaVersion} for "${entry.key}".',
      );
    }
    if (artifact.minClient > supportedMinClient) {
      throw buildError(
        'unsupported_min_client',
        'Screen artifact minClient ${artifact.minClient} for "${entry.key}" '
            'exceeds $clientDescription $supportedMinClient.',
      );
    }
  }
}

void _checkValidation(
  FlowDocument document,
  BundledFlowErrorFactory buildError,
) {
  final issues = FlowDocumentValidation.validate(document);
  if (issues.isEmpty) {
    return;
  }

  final reason = issues.any((issue) => issue.code == 'unsupportedStateKind')
      ? 'unsupported_state_kind'
      : issues.any((issue) => issue.code == 'unsupportedFeature')
          ? 'unsupported_feature'
          : 'validation_failed';
  throw buildError(
    reason,
    'Flow document failed validation: ${issues.join('; ')}.',
  );
}

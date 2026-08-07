import 'dart:convert';

import 'hosted_render_bundle_session.dart';
import 'protocol.dart';
import 'wire_json.dart';

/// Exact static dashboard path for the native preview polling shell.
const renderBundlePreviewShellPath = '/render-bundle-preview-shell.html';

final _noncePattern = RegExp(r'^[0-9a-f]{32,64}$');

/// Non-secret identity for one native-to-shell polling generation.
final class PreviewShellSessionKey {
  /// Creates one bounded generation and cryptographically random hex nonce.
  PreviewShellSessionKey({required this.generation, required this.nonce}) {
    if (generation < 1 || !_noncePattern.hasMatch(nonce)) {
      throw ArgumentError('Invalid preview shell session key.');
    }
  }

  /// Monotonically increasing native session generation.
  final int generation;

  /// Lowercase random hex nonce, 128–256 bits.
  final String nonce;
}

/// One validated event drained from the trusted top-level shell.
sealed class PreviewShellEvent {
  const PreviewShellEvent();
}

/// The reveal-once bootstrap form was submitted and immediately cleared.
final class PreviewShellSubmitted extends PreviewShellEvent {
  const PreviewShellSubmitted();
}

/// The bootstrap POST child has completed its post-submission load.
final class PreviewShellLoaded extends PreviewShellEvent {
  const PreviewShellLoaded();
}

/// One exact-origin child protocol message.
final class PreviewShellMessage extends PreviewShellEvent {
  const PreviewShellMessage(this.message);

  /// Transport message ready for [SeamRenderProvider].
  final RenderTransportMessage message;
}

/// Terminal shell failure with a stable, non-sensitive reason.
final class PreviewShellError extends PreviewShellEvent {
  const PreviewShellError(this.reason);

  /// Stable shell-local reason.
  final String reason;
}

/// Generates injection-safe top-level polling calls and validates drain data.
///
/// Every invocation is intended for main-document `runJavaScript`; no native
/// JavaScript channel is needed or permitted.
final class PreviewShellBridgeCodec {
  const PreviewShellBridgeCodec._();

  /// Creates the one reveal-once bootstrap invocation.
  static String bootstrapInvocation({
    required PreviewShellSessionKey key,
    required HostedRenderBundleBootstrap bootstrap,
  }) =>
      _invocation('bootstrap', <String, Object?>{
        'v': renderProtocolV1,
        'generation': key.generation,
        'nonce': key.nonce,
        'bootstrapUrl': bootstrap.bootstrapUrl.toString(),
        'bundleOrigin': bootstrap.bundleOrigin.origin,
        'bootstrapGrant': bootstrap.bootstrapGrant,
      });

  /// Creates one outbound frozen-v1 protocol invocation.
  static String acceptInvocation({
    required PreviewShellSessionKey key,
    required String targetOrigin,
    required Map<String, Object?> payload,
  }) =>
      _invocation('accept', <String, Object?>{
        'v': renderProtocolV1,
        'generation': key.generation,
        'nonce': key.nonce,
        'targetOrigin': targetOrigin,
        'payload': snapshotWireMap(payload, argumentName: 'payload'),
      });

  /// Creates one bounded queue-drain invocation.
  static String drainInvocation({
    required PreviewShellSessionKey key,
    int maxCount = 16,
  }) {
    if (maxCount < 1 || maxCount > 16) {
      throw ArgumentError.value(maxCount, 'maxCount', 'must be from 1 to 16');
    }
    return _invocation('drain', <String, Object?>{
      'v': renderProtocolV1,
      'generation': key.generation,
      'nonce': key.nonce,
      'maxCount': maxCount,
    });
  }

  /// Creates the idempotent shell-dispose invocation.
  static String disposeInvocation(PreviewShellSessionKey key) =>
      _invocation('dispose', <String, Object?>{
        'v': renderProtocolV1,
        'generation': key.generation,
        'nonce': key.nonce,
      });

  /// Decodes one bounded drain result for the exact active session and origin.
  static List<PreviewShellEvent> decodeDrain(
    Object? result, {
    required PreviewShellSessionKey key,
    required String bundleOrigin,
  }) {
    if (result is! String || result.length > 32 * 1024 * 1024) {
      throw const FormatException('Invalid preview shell drain.');
    }
    final decoded = jsonDecode(result);
    if (decoded is! List<Object?> || decoded.length > 16) {
      throw const FormatException('Invalid preview shell drain.');
    }
    return decoded.map((item) {
      if (item is! Map<String, Object?> ||
          item['generation'] != key.generation ||
          item['nonce'] != key.nonce ||
          item['kind'] is! String) {
        throw const FormatException('Invalid preview shell drain.');
      }
      switch (item['kind']) {
        case 'submitted':
          if (!_hasExactKeys(item, const {
            'kind',
            'generation',
            'nonce',
          })) {
            throw const FormatException('Invalid preview shell drain.');
          }
          return const PreviewShellSubmitted();
        case 'loaded':
          if (!_hasExactKeys(item, const {
            'kind',
            'generation',
            'nonce',
          })) {
            throw const FormatException('Invalid preview shell drain.');
          }
          return const PreviewShellLoaded();
        case 'message':
          if (!_hasExactKeys(item, const {
                'kind',
                'generation',
                'nonce',
                'origin',
                'payload',
              }) ||
              item['origin'] != bundleOrigin ||
              item['payload'] is! Map<String, Object?>) {
            throw const FormatException('Invalid preview shell drain.');
          }
          return PreviewShellMessage(
            RenderTransportMessage(
              origin: bundleOrigin,
              payload: snapshotWireMap(
                item['payload']! as Map<String, Object?>,
                argumentName: 'payload',
              ),
            ),
          );
        case 'error':
          if (!_hasExactKeys(item, const {
                'kind',
                'generation',
                'nonce',
                'reason',
              }) ||
              item['reason'] is! String) {
            throw const FormatException('Invalid preview shell drain.');
          }
          return PreviewShellError(item['reason']! as String);
        default:
          throw const FormatException('Invalid preview shell drain.');
      }
    }).toList(growable: false);
  }
}

String _invocation(String method, Map<String, Object?> command) {
  final encoded = base64Encode(utf8.encode(jsonEncode(command)));
  return 'window.RestagePreviewBridge.$method('
      'window.RestagePreviewBridge.decode("$encoded"))';
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

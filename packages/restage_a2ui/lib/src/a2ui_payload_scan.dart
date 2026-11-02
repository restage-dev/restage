import 'package:a2ui_core/a2ui_core.dart';

/// Parses a cached v1 message, flat message list, or `{"messages": [...]}`
/// wrapper with upstream validation.
///
/// Only protocol envelopes are interpreted; arbitrary component property data
/// and data-model values are never scanned for component-looking objects.
/// Malformed containers fail before upstream's transport normalization, which
/// otherwise tolerates null and nested batches.
AgentToRendererMessagePayload parseA2uiV1Messages(Object? payload) {
  final isWrapper = payload is Map && payload.containsKey('messages');
  if (isWrapper && (payload.length != 1 || payload['messages'] is! List)) {
    throw const FormatException(
      'a messages wrapper must hold only a "messages" list',
    );
  }
  final unwrapped = isWrapper ? payload['messages'] : payload;
  final entries = unwrapped is List ? unwrapped : [unwrapped];
  final envelopes = <Map<String, Object?>>[];
  for (final entry in entries) {
    if (entry is! Map || entry.keys.any((key) => key is! String)) {
      throw const FormatException('expected an A2UI message object');
    }
    envelopes.add(Map<String, Object?>.from(entry));
  }
  return AgentToRendererMessage.parseAll(
    envelopes,
    protocolVersion: A2uiProtocolVersion.v1_0,
  );
}

import 'dart:async';
import 'dart:js_interop';

import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:web/web.dart' as web;

@JS('Object.is')
external bool _isSameJsObject(JSAny? first, JSAny? second);

const int _maxJsonDepth = 64;
const int _maxJsonNodes = 100000;
const double _maxSafeJsonInteger = 9007199254740991.0;

/// Browser-only observation hooks for focused DOM tests.
///
/// Production construction never supplies these hooks. They expose raw browser
/// calls without replacing message filtering or protocol behavior.
final class BrowserRenderMessageTransportWebHooks {
  const BrowserRenderMessageTransportWebHooks({
    this.onListenerInstalled,
    this.onListenerRemoved,
    this.postMessage,
    this.readParentWindow,
  });

  final void Function()? onListenerInstalled;
  final void Function()? onListenerRemoved;
  final void Function(
    web.Window target,
    Map<String, Object?> payload,
    String targetOrigin,
  )? postMessage;
  final web.Window? Function()? readParentWindow;
}

/// Creates the browser transport used by an isolated render bundle.
RenderMessageTransport createBrowserRenderMessageTransport({
  required String parentOrigin,
}) =>
    _BrowserRenderMessageTransport(parentOrigin: parentOrigin);

/// Test-only constructor that observes raw browser side effects.
RenderMessageTransport createBrowserRenderMessageTransportForTest({
  required String parentOrigin,
  BrowserRenderMessageTransportWebHooks hooks =
      const BrowserRenderMessageTransportWebHooks(),
}) =>
    _BrowserRenderMessageTransport(parentOrigin: parentOrigin, hooks: hooks);

final class _BrowserRenderMessageTransport implements RenderMessageTransport {
  _BrowserRenderMessageTransport({
    required String parentOrigin,
    this.hooks = const BrowserRenderMessageTransportWebHooks(),
  })  : parentOrigin = _validateParentOrigin(parentOrigin),
        _parent = _validateParentWindow(
          (hooks.readParentWindow ?? () => web.window.parent)(),
        ) {
    _listener = ((web.Event event) => _receive(event)).toJS;
    web.window.addEventListener('message', _listener);
    hooks.onListenerInstalled?.call();
  }

  final String parentOrigin;
  final BrowserRenderMessageTransportWebHooks hooks;
  final web.Window _parent;
  final StreamController<RenderTransportMessage> _messages =
      StreamController<RenderTransportMessage>.broadcast(sync: true);
  late final JSFunction _listener;
  bool _disposed = false;

  @override
  Stream<RenderTransportMessage> get messages => _messages.stream;

  void _receive(web.Event rawEvent) {
    if (_disposed) return;
    final event = rawEvent as web.MessageEvent;
    if (event.origin != parentOrigin ||
        !_isSameJsObject(event.source, _parent)) {
      return;
    }
    try {
      final payload = _boundedJsonObject(event.data.dartify());
      if (payload == null) return;
      _messages.add(
        RenderTransportMessage(origin: event.origin, payload: payload),
      );
    } on Object {
      // Malformed or over-budget messages are untrusted input and are dropped.
    }
  }

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {
    if (_disposed) {
      throw StateError('A disposed browser render transport cannot send.');
    }
    if (targetOrigin != '*' && targetOrigin != parentOrigin) {
      throw ArgumentError(
        'targetOrigin must be the configured parent origin or the initial '
        'ready sentinel.',
      );
    }
    final normalized = _boundedJsonObject(payload);
    if (normalized == null) {
      throw ArgumentError('payload must be a bounded JSON object.');
    }
    final postMessage = hooks.postMessage;
    if (postMessage == null) {
      _parent.postMessage(normalized.jsify(), parentOrigin.toJS);
    } else {
      postMessage(_parent, normalized, parentOrigin);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    web.window.removeEventListener('message', _listener);
    hooks.onListenerRemoved?.call();
    await _messages.close();
  }
}

String _validateParentOrigin(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path.isNotEmpty ||
      uri.origin != source) {
    throw ArgumentError(
      'parentOrigin must be one canonical HTTP or HTTPS origin.',
    );
  }
  return source;
}

web.Window _validateParentWindow(web.Window? parent) {
  if (parent == null || _isSameJsObject(parent, web.window)) {
    throw StateError('The render bundle must run inside a parent window.');
  }
  return parent;
}

Map<String, Object?>? _boundedJsonObject(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  var nodes = 0;

  Object? normalize(Object? current, int depth) {
    if (depth > _maxJsonDepth || ++nodes > _maxJsonNodes) {
      throw const FormatException('JSON message exceeds transport bounds.');
    }
    if (current == null || current is bool || current is String) {
      return current;
    }
    if (current is num) {
      if (!current.isFinite) {
        throw const FormatException('JSON numbers must be finite.');
      }
      if (current is double) {
        final isNegativeZero = current == 0 && current.isNegative;
        final isSafeInteger = current >= -_maxSafeJsonInteger &&
            current <= _maxSafeJsonInteger &&
            current.truncateToDouble() == current;
        if (!isNegativeZero && isSafeInteger) return current.toInt();
      }
      return current;
    }
    if (current is List<Object?>) {
      return List<Object?>.unmodifiable(
        current.map((child) => normalize(child, depth + 1)),
      );
    }
    if (current is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in current.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('JSON object keys must be strings.');
        }
        result[key] = normalize(entry.value, depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    throw const FormatException('Message must contain only JSON values.');
  }

  return normalize(value, 0)! as Map<String, Object?>;
}

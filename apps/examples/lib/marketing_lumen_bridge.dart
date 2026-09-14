import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

@JS('Object.is')
external bool _isSameJsObject(JSAny? first, JSAny? second);

final class MarketingLumenState {
  const MarketingLumenState({
    this.dark = true,
    this.published = false,
    this.enabled = false,
    this.requestId = 0,
    this.resetGeneration = 0,
  });

  final bool dark;
  final bool published;
  final bool enabled;
  final int requestId;
  final int resetGeneration;
}

final class MarketingLumenBridge {
  MarketingLumenBridge({required this.onState}) {
    _listener = ((web.Event event) => _receive(event)).toJS;
    web.window.addEventListener('message', _listener);
  }

  final ValueChanged<MarketingLumenState> onState;
  late final JSFunction _listener;

  void _receive(web.Event rawEvent) {
    final event = rawEvent as web.MessageEvent;
    final parent = web.window.parent;
    if (event.origin != web.window.location.origin ||
        !_isSameJsObject(event.source, parent)) {
      return;
    }
    final value = event.data.dartify();
    if (value is! Map<Object?, Object?> ||
        value['type'] != 'restage-lumen-state') {
      return;
    }
    final dark = value['dark'];
    final published = value['published'];
    final enabled = value['enabled'];
    final rawRequestId = value['requestId'];
    final rawResetGeneration = value['resetGeneration'] ?? 0;
    if (dark is! bool ||
        published is! bool ||
        enabled is! bool ||
        rawRequestId is! num ||
        rawResetGeneration is! num ||
        !rawRequestId.isFinite ||
        !rawResetGeneration.isFinite ||
        rawRequestId < 0 ||
        rawResetGeneration < 0 ||
        rawRequestId > 9007199254740991 ||
        rawResetGeneration > 9007199254740991 ||
        rawRequestId.truncateToDouble() != rawRequestId.toDouble() ||
        rawResetGeneration.truncateToDouble() !=
            rawResetGeneration.toDouble()) {
      return;
    }
    final requestId = rawRequestId.toInt();
    final resetGeneration = rawResetGeneration.toInt();
    onState(
      MarketingLumenState(
        dark: dark,
        published: published,
        enabled: enabled,
        requestId: requestId,
        resetGeneration: resetGeneration,
      ),
    );
  }

  void sendReady() => _send(const {'type': 'restage-lumen-ready'});

  void sendEvent(String name) => _send({
        'type': 'restage-lumen-event',
        'name': name,
      });

  void sendApplied(MarketingLumenState state) => _send({
        'type': 'restage-lumen-applied',
        'dark': state.dark,
        'published': state.published,
        'enabled': state.enabled,
        'requestId': state.requestId,
        'resetGeneration': state.resetGeneration,
      });

  void sendError(Object error, {required int requestId}) => _send({
        'type': 'restage-lumen-error',
        'message': error.toString(),
        'requestId': requestId,
      });

  void _send(Map<String, Object?> message) {
    web.window.parent?.postMessage(
      message.jsify(),
      web.window.location.origin.toJS,
    );
  }

  void dispose() {
    web.window.removeEventListener('message', _listener);
  }
}

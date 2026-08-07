import 'dart:async';

import 'package:restage_preview_host/restage_preview_host.dart';

final class SentMessage {
  const SentMessage(this.payload, this.targetOrigin);

  final Map<String, Object?> payload;
  final String targetOrigin;
}

final class FakeRenderMessageTransport implements RenderMessageTransport {
  final StreamController<RenderTransportMessage> _messages =
      StreamController<RenderTransportMessage>.broadcast(sync: true);
  final List<SentMessage> sent = <SentMessage>[];
  Object? nextSendError;

  @override
  Stream<RenderTransportMessage> get messages => _messages.stream;

  void receive(String origin, Map<String, Object?> payload) {
    _messages.add(RenderTransportMessage(origin: origin, payload: payload));
  }

  @override
  void send(Map<String, Object?> payload, {required String targetOrigin}) {
    final error = nextSendError;
    nextSendError = null;
    if (error != null) {
      throw error;
    }
    sent.add(SentMessage(payload, targetOrigin));
  }

  @override
  Future<void> dispose() => _messages.close();
}

final class ManualFrameScheduler {
  final List<void Function()> _callbacks = <void Function()>[];

  void schedule(void Function() callback) => _callbacks.add(callback);

  void flush() {
    final callbacks = List<void Function()>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

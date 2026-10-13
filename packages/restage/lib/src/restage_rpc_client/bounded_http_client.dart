import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Bounds the wait for response headers and each silence between body
/// chunks, so a server that stops answering fails the request with a
/// [TimeoutException] while a slow but steady body still completes.
@internal
final class BoundedHttpClient extends http.BaseClient {
  BoundedHttpClient(this._inner, {this.timeout = defaultTimeout});

  /// Long enough for a first byte over a poor mobile link.
  static const Duration defaultTimeout = Duration(seconds: 8);

  final http.Client _inner;

  /// The longest wait for headers, and for each next body chunk.
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final expired = Completer<void>();
    final timer = Timer(timeout, expired.complete);
    final http.StreamedResponse? response;
    final sending = _inner.send(request);
    try {
      response = await Future.any<http.StreamedResponse?>([
        sending,
        expired.future.then((_) => null),
      ]);
    } finally {
      timer.cancel();
    }
    if (response == null) {
      // Releases the connection if the headers ever arrive.
      unawaited(sending.then(
        (late) => late.stream.listen(null).cancel(),
        onError: (Object _) {},
      ));
      throw TimeoutException('No response', timeout);
    }
    return http.StreamedResponse(
      http.ByteStream(_untilSilent(response.stream)),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Passes [body] through, failing it once no chunk arrives for [timeout]
  /// while the reader is listening.
  Stream<List<int>> _untilSilent(Stream<List<int>> body) {
    StreamSubscription<List<int>>? subscription;
    Timer? idle;
    late final StreamController<List<int>> controller;

    void finish() {
      idle?.cancel();
      idle = null;
      subscription = null;
      unawaited(controller.close());
    }

    void stalled() {
      final active = subscription;
      if (active == null) return;
      unawaited(active.cancel());
      controller.addError(TimeoutException('Response body stalled', timeout));
      finish();
    }

    void arm() {
      idle?.cancel();
      idle = Timer(timeout, stalled);
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        subscription = body.listen(
          (chunk) {
            arm();
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            controller.addError(error, stack);
            finish();
          },
          onDone: finish,
          cancelOnError: true,
        );
        arm();
      },
      // A paused reader is not a silent server.
      onPause: () {
        idle?.cancel();
        subscription?.pause();
      },
      onResume: () {
        subscription?.resume();
        if (subscription != null) arm();
      },
      onCancel: () {
        idle?.cancel();
        idle = null;
        final active = subscription;
        subscription = null;
        return active?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  void close() => _inner.close();
}

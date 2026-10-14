import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/bounded_http_client.dart';

void main() {
  test('passes an answered response through unchanged', () async {
    final client = BoundedHttpClient(MockClient((request) async {
      return http.Response('{"ok":true}', 201, headers: {'x-a': 'b'});
    }));

    final response = await client.get(Uri.parse('https://a.example/x'));

    expect(response.statusCode, 201);
    expect(response.body, '{"ok":true}');
    expect(response.headers['x-a'], 'b');
  });

  test('fails a request whose headers never arrive', () async {
    final client = BoundedHttpClient(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      client.get(Uri.parse('https://a.example/x')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('fails a response whose body stalls', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final client = BoundedHttpClient(
      MockClient.streaming((_, __) async {
        body.add([1, 2, 3]);
        return http.StreamedResponse(body.stream, 200);
      }),
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      client.get(Uri.parse('https://a.example/x')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('completes a slow but steady body that outlasts the timeout', () {
    fakeAsync((async) {
      final chunks = StreamController<List<int>>();
      final client = BoundedHttpClient(
        MockClient.streaming((_, __) async {
          return http.StreamedResponse(chunks.stream, 200);
        }),
        timeout: const Duration(milliseconds: 60),
      );

      List<int>? body;
      client
          .get(Uri.parse('https://a.example/x'))
          .then((response) => body = response.bodyBytes);
      async.flushMicrotasks();
      for (var i = 0; i < 10; i++) {
        chunks.add([i]);
        async.elapse(const Duration(milliseconds: 15));
      }
      expect(body, isNull);

      chunks.close();
      async.flushMicrotasks();
      expect(body, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });
  });

  test('fails a body that stalls after steady progress', () {
    fakeAsync((async) {
      final body = StreamController<List<int>>();
      final client = BoundedHttpClient(
        MockClient.streaming((_, __) async {
          return http.StreamedResponse(body.stream, 200);
        }),
        timeout: const Duration(milliseconds: 40),
      );

      final received = <int>[];
      Object? failure;
      client
          .send(http.Request('GET', Uri.parse('https://a.example')))
          .then((response) {
        response.stream.listen(
          received.addAll,
          onError: (Object error) => failure = error,
        );
      });
      async.flushMicrotasks();
      for (var i = 0; i < 4; i++) {
        body.add([i]);
        async.elapse(const Duration(milliseconds: 20));
      }
      expect(failure, isNull);

      async.elapse(const Duration(milliseconds: 40));
      expect(failure, isA<TimeoutException>());
      expect(received, [0, 1, 2, 3]);
      body.close();
      async.flushMicrotasks();
    });
  });

  test('streams body bytes as they arrive', () async {
    final body = StreamController<List<int>>();
    final client = BoundedHttpClient(
      MockClient.streaming((_, __) async {
        return http.StreamedResponse(body.stream, 200);
      }),
    );

    final response =
        await client.send(http.Request('GET', Uri.parse('https://a.example')));
    final chunks = <List<int>>[];
    final done = response.stream.listen(chunks.add).asFuture<void>();
    body.add([1, 2, 3]);
    await pumpEventQueue();
    expect(chunks, [
      [1, 2, 3],
    ]);

    await body.close();
    await done;
    expect(chunks, hasLength(1));
  });
}

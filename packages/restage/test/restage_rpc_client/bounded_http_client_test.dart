import 'dart:async';

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

  test('completes a slow but steady body that outlasts the timeout', () async {
    final client = BoundedHttpClient(
      MockClient.streaming((_, __) async {
        final chunks = Stream<List<int>>.periodic(
          const Duration(milliseconds: 15),
          (index) => [index],
        ).take(10);
        return http.StreamedResponse(chunks, 200);
      }),
      timeout: const Duration(milliseconds: 60),
    );

    final started = DateTime.now();
    final response = await client.get(Uri.parse('https://a.example/x'));

    expect(response.bodyBytes, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(
      DateTime.now().difference(started),
      greaterThan(const Duration(milliseconds: 60)),
    );
  });

  test('fails a body that stalls after steady progress', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final client = BoundedHttpClient(
      MockClient.streaming((_, __) async {
        return http.StreamedResponse(body.stream, 200);
      }),
      timeout: const Duration(milliseconds: 40),
    );

    final response =
        await client.send(http.Request('GET', Uri.parse('https://a.example')));
    final received = <int>[];
    final done = response.stream
        .listen((chunk) => received.addAll(chunk))
        .asFuture<void>();
    for (var i = 0; i < 4; i++) {
      body.add([i]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    await expectLater(done, throwsA(isA<TimeoutException>()));
    expect(received, [0, 1, 2, 3]);
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

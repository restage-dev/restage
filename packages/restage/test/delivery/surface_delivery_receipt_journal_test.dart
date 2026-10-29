import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_journal.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_journal_io.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_uploader.dart';
import 'package:restage/src/resolver/surface_resolution_report.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

final class _MemoryJournal implements SurfaceDeliveryReceiptJournal {
  SurfaceDeliveryReceiptJournalState? stored;

  /// When set, a read waits for it.
  Future<void>? readGate;

  @override
  Future<SurfaceDeliveryReceiptJournalState?> read() async {
    await readGate;
    return stored;
  }

  @override
  Future<void> write(SurfaceDeliveryReceiptJournalState state) async =>
      stored = state.posts.isEmpty && state.receipts.isEmpty
          ? null
          : (
              fingerprint: state.fingerprint,
              posts: List.of(state.posts),
              receipts: List.of(state.receipts),
            );

  /// Every receipt held, in a post or not yet.
  int get receipts => stored == null
      ? 0
      : stored!.receipts.length +
          stored!.posts.fold(0, (sum, post) => sum + post.receipts.length);
}

void main() {
  late _MemoryJournal journal;
  late List<http.Request> requests;
  late FutureOr<http.Response> Function() answer;

  /// A fresh process: new batch and uploader over the same journal.
  SurfaceDeliveryReceiptUploader launch({String apiKey = 'rs_pk_test'}) {
    SurfaceDeliveryReceiptBatch.debugReset();
    SurfaceDeliveryReceiptUploader.debugReset();
    SurfaceDeliveryReceiptBatch.instance.deviceSource =
        () async => (platform: 'android', appBuild: 7);
    return SurfaceDeliveryReceiptUploader.instance
      ..debugJournal = journal
      ..debugHttpClient = MockClient((request) async {
        requests.add(request);
        return answer();
      })
      ..configure(
        baseUrl: 'https://api.example.test',
        apiKey: apiKey,
        enabled: true,
      );
  }

  void paint() => SurfaceDeliveryReceiptBatch.instance
      .open(
        surfaceType: Surface.paywall,
        surfaceSlug: 'pro',
        publishedVersion: 3,
        source: SurfaceResolutionSource.fresh,
        reason: SurfaceDeliveryReceiptReason.none,
        routeId: '',
      )
      .painted(const Duration(milliseconds: 50));

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<Object?> postedReceipts() => [
        for (final request in requests)
          ...(jsonDecode(request.body) as Map)['receipts'] as List,
      ];

  setUp(() {
    journal = _MemoryJournal();
    requests = [];
    answer = () => http.Response('', 204);
  });

  tearDown(() {
    SurfaceDeliveryReceiptUploader.debugReset();
    SurfaceDeliveryReceiptBatch.debugReset();
  });

  test('a view painted before a kill posts at the next launch', () async {
    launch();
    paint();
    paint();
    await settle();
    expect(requests, isEmpty, reason: 'painting posts nothing');
    expect(journal.receipts, 1);

    launch();
    await settle();
    expect(requests, hasLength(1));
    expect((postedReceipts().single! as Map)['count'], 2);
    expect(journal.stored, isNull);
  });

  test('an acknowledged post leaves nothing for the next launch', () async {
    final uploader = launch()..retain();
    paint();
    await settle();
    await uploader.flush();
    await settle();
    expect(requests, hasLength(1));
    expect(journal.stored, isNull);

    launch();
    await settle();
    expect(requests, hasLength(1));
  });

  test('a failed post stays journaled and posts at the next launch', () async {
    answer = () => throw http.ClientException('offline');
    final uploader = launch();
    paint();
    await settle();
    await uploader.flush();
    await settle();
    expect(requests, hasLength(1));
    expect(journal.receipts, 1);

    answer = () => http.Response('', 204);
    launch();
    await settle();
    expect(requests, hasLength(2));
    expect(requests[1].body, requests[0].body,
        reason: 'the unacknowledged post resends unchanged under its id');
    expect(journal.stored, isNull);
  });

  test('a view drained into a post stays journaled until it is answered',
      () async {
    final device = Completer<SurfaceDeliveryReceiptDevice>();
    final gate = Completer<http.Response>();
    final uploader = launch()
      ..debugHttpClient = MockClient((request) {
        requests.add(request);
        return gate.future;
      });
    SurfaceDeliveryReceiptBatch.instance.deviceSource = () => device.future;
    // The close starts a journal write; the flush drains while it waits.
    paint();
    final flushing = uploader.flush();
    device.complete((platform: 'android', appBuild: 7));
    await settle();
    expect(requests, hasLength(1), reason: 'the post is in flight');
    final sent = (jsonDecode(requests.single.body) as Map)['batchId'];
    expect(journal.stored!.receipts, isEmpty);
    expect(journal.stored!.posts.single.batchId, sent,
        reason: 'the post was journaled under its id before it was sent');
    gate.complete(http.Response('', 204));
    await flushing;
    await settle();
    expect(journal.stored, isNull);
  });

  test('a kill while a post is in flight resends it under the same id',
      () async {
    answer = () => Completer<http.Response>().future;
    final uploader = launch();
    paint();
    await settle();
    unawaited(uploader.flush());
    await settle();
    expect(requests, hasLength(1), reason: 'the post is in flight');

    final sent = (jsonDecode(requests.single.body) as Map)['batchId'];
    expect(journal.stored!.posts.single.batchId, sent);

    answer = () => http.Response('', 204);
    launch();
    await settle();
    expect(requests, hasLength(2));
    expect((jsonDecode(requests[1].body) as Map)['batchId'], sent);
    expect(requests[1].body, requests[0].body,
        reason: 'the post was journaled with its id before it was sent');
    expect(journal.stored, isNull);
  });

  test('a failing service keeps the queue for the next launch', () async {
    answer = () => http.Response('{"error":"unavailable"}', 503);
    final uploader = launch();
    paint();
    await settle();
    await uploader.flush();
    await settle();
    expect(requests, hasLength(1));
    expect(journal.receipts, 1);

    answer = () => http.Response('', 204);
    launch();
    await settle();
    expect(requests, hasLength(2));
    expect(requests[1].body, requests[0].body);
    expect(journal.stored, isNull);
  });

  /// Leaves one unacknowledged post journaled, then starts a process that
  /// queues a second post behind it.
  Future<void> twoPosts(List<int> statuses) async {
    answer = () => throw http.ClientException('offline');
    final first = launch();
    paint();
    await settle();
    await first.flush();
    await settle();
    requests.clear();
    final answers = [...statuses];
    answer = () => http.Response('', answers.removeAt(0));
    launch();
    paint();
    await settle();
  }

  test('an organization refused service keeps every post for later', () async {
    await twoPosts([403]);
    expect(requests, hasLength(1), reason: 'the flush stops at the refusal');
    expect(journal.stored!.posts, hasLength(2));

    answer = () => http.Response('', 204);
    await SurfaceDeliveryReceiptUploader.instance.flush();
    await settle();
    expect(requests, hasLength(3));
    expect(journal.stored, isNull);
  });

  test('a refused post is dropped alone', () async {
    await twoPosts([400, 204]);
    expect(requests, hasLength(2));
    expect((jsonDecode(requests[0].body) as Map)['batchId'],
        isNot((jsonDecode(requests[1].body) as Map)['batchId']));
    expect(journal.stored, isNull);
  });

  test('a refused key keeps every post journaled for its retries', () async {
    await twoPosts([401]);
    expect(requests, hasLength(1));
    expect(journal.stored!.posts, hasLength(2));
  });

  test('a keyless first configuration leaves the journal for the key',
      () async {
    launch();
    paint();
    await settle();
    expect(journal.receipts, 1);

    SurfaceDeliveryReceiptBatch.debugReset();
    SurfaceDeliveryReceiptUploader.debugReset();
    SurfaceDeliveryReceiptBatch.instance.deviceSource =
        () async => (platform: 'android', appBuild: 7);
    SurfaceDeliveryReceiptUploader.instance
      ..debugJournal = journal
      ..debugHttpClient = MockClient((request) async {
        requests.add(request);
        return answer();
      })
      ..configure(
          baseUrl: 'https://api.example.test', apiKey: null, enabled: true)
      ..configure(
        baseUrl: 'https://api.example.test',
        apiKey: 'rs_pk_test',
        enabled: true,
      );
    await settle();
    expect(requests, hasLength(1));
    expect((postedReceipts().single! as Map)['count'], 1);
    expect(journal.stored, isNull);
  });

  test('a reconfiguration during the journal read keeps the old key\'s posts',
      () async {
    launch();
    paint();
    await settle();
    expect(journal.receipts, 1);

    final gate = Completer<void>();
    journal.readGate = gate.future;
    final uploader = launch();
    uploader.configure(
      baseUrl: 'https://api.example.test',
      apiKey: 'rs_pk_other',
      enabled: true,
    );
    gate.complete();
    await settle();
    await uploader.flush();
    await settle();
    expect(requests, isEmpty,
        reason: 'receipts journaled under one key never post under another');
  });

  test('turning receipts off clears the journal', () async {
    launch();
    paint();
    await settle();
    expect(journal.receipts, 1);

    SurfaceDeliveryReceiptUploader.instance.configure(
      baseUrl: 'https://api.example.test',
      apiKey: 'rs_pk_test',
      enabled: false,
    );
    await settle();
    expect(journal.stored, isNull);
  });

  test('the oldest posts beyond the cap are dropped', () async {
    answer = () => throw http.ClientException('offline');
    final cap = kSurfaceDeliveryReceiptMaximumJournaledPosts;
    journal.stored = (
      fingerprint: sha256
          .convert(utf8.encode('https://api.example.test\nrs_pk_test'))
          .toString(),
      posts: [
        for (var i = 0; i < cap; i++)
          (
            batchId: 'post-$i',
            receipts: [
              jsonEncode({'surfaceSlug': 'pro', 'count': 1}),
            ],
            dropped: 0,
          ),
      ],
      receipts: const <String>[],
    );
    // The launch posts what it restored with the new view: one post too many.
    launch();
    paint();
    await settle();
    final posts = journal.stored!.posts;
    expect(posts, hasLength(cap));
    expect(posts.first.batchId, 'post-1', reason: 'post-0 was the oldest');
    expect(SurfaceDeliveryReceiptBatch.instance.dropped, 1);
  });

  test('receipts journaled under another key are never posted', () async {
    launch();
    paint();
    await settle();

    launch(apiKey: 'rs_pk_other');
    await settle();
    expect(requests, isEmpty);
    expect(journal.stored, isNull);
  });

  test('the file journal replaces itself and clears when empty', () async {
    final directory = await Directory.systemTemp.createTemp('receipts');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/restage/delivery/receipts-v1.json');
    final fileJournal = FileSurfaceDeliveryReceiptJournal(() async => file);

    expect(await fileJournal.read(), isNull);
    await fileJournal.write((
      fingerprint: 'abc',
      posts: [
        (batchId: 'b1', receipts: ['{"count":1}'], dropped: 2),
      ],
      receipts: ['{"count":3}'],
    ));
    final read = await fileJournal.read();
    expect(read?.fingerprint, 'abc');
    expect(read?.posts.single.batchId, 'b1');
    expect(read?.posts.single.receipts, ['{"count":1}']);
    expect(read?.posts.single.dropped, 2);
    expect(read?.receipts, ['{"count":3}']);
    await fileJournal.write((fingerprint: 'abc', posts: [], receipts: []));
    expect(file.existsSync(), isFalse);
    await file.parent.create(recursive: true);
    await file.writeAsString('not json');
    expect(await fileJournal.read(), isNull);
  });
}

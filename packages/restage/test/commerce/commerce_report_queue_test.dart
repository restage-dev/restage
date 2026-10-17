import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/commerce.dart';
import 'package:restage_shared/commerce.dart' show GooglePlayPurchaseReceipt;
import 'package:restage/src/commerce/commerce_report_queue_io.dart';
import 'package:restage/src/commerce/commerce_report_queue_protocol.dart';

void main() {
  test('updated Play signed snapshots retain one durable provider identity',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('restage-play-queue-');
    addTearDown(() => directory.delete(recursive: true));
    final queue = CommerceFileReportQueue(directoryPath: directory.path);
    CommerceReportRecord report(String id, bool acknowledged) =>
        CommerceReportRecord(
          reportId: id,
          store: CommerceStore.playStore,
          storeVerificationData: GooglePlayPurchaseReceipt(
            originalJson: jsonEncode(
                {'purchaseToken': 'owned-token', 'acknowledged': acknowledged}),
            signature:
                acknowledged ? 'updated-signature' : 'original-signature',
          ).toVerificationData(),
          storeProductId: 'subscription.monthly',
          storeTransactionId: 'initial-order',
          applicationAnonymousToken: 'purchaser',
          configurationFingerprint: 'same-scope',
        );
    final original = report('first-report', false);
    await queue.enqueue(original);
    expect(await queue.enqueue(report('resume-report', true)), same(original));
    expect(await queue.open(), hasLength(1));
    expect(
        (await CommerceFileReportQueue(directoryPath: directory.path).open())
            .single
            .hasSameProviderIdentity(report('later-resume', true)),
        isTrue);
  });

  test('persists a report and its retry schedule across a disk restart',
      () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'restage-commerce-report-',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final journalDirectory = '${supportDirectory.path}/journal';
    var now = DateTime.utc(2026, 9, 5, 12, 0, 0, 123, 456);
    final firstQueue = CommerceFileReportQueue(
      directoryPath: journalDirectory,
      clock: () => now,
    );
    final report = _report();

    expect(await firstQueue.open(), isEmpty);
    expect(await firstQueue.enqueue(report), same(report));

    final journal = File('$journalDirectory/reports.json');
    expect(await journal.exists(), isTrue);
    final persisted =
        jsonDecode(await journal.readAsString()) as Map<String, Object?>;
    final records = persisted['records'] as List<Object?>;
    expect(
      (records.single as Map<Object?, Object?>)['reportId'],
      report.reportId,
    );
    expect(
      (records.single as Map<Object?, Object?>)['applicationAnonymousToken'],
      report.applicationAnonymousToken,
    );
    expect(
      (records.single as Map<Object?, Object?>)['configurationFingerprint'],
      report.configurationFingerprint,
    );

    final retried = await firstQueue.scheduleRetry(report.reportId);
    expect(retried?.retryAttempt, 1);
    expect(
      retried?.nextRetryAt,
      DateTime.fromMillisecondsSinceEpoch(
        now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
        isUtc: true,
      ),
    );

    final restartedQueue = CommerceFileReportQueue(
      directoryPath: journalDirectory,
      clock: () => now,
    );
    expect(await restartedQueue.due(), isEmpty);

    now = now.add(const Duration(seconds: 1));
    final due = await restartedQueue.due();
    expect(due, hasLength(1));
    expect(due.single.reportId, report.reportId);
    expect(due.single.intentId, report.intentId);
    expect(due.single.storeVerificationData, report.storeVerificationData);

    await restartedQueue.acknowledge(report.reportId);
    expect(await restartedQueue.due(), isEmpty);
  });

  test(
      'retains effective retry attempt and deadline after schedule write failure',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('restage-commerce-report-');
    addTearDown(() => directory.delete(recursive: true));
    var now = DateTime.utc(2026, 9, 30);
    final queue = CommerceFileReportQueue(
      directoryPath: directory.path,
      clock: () => now,
    );
    final report = _report();
    await queue.enqueue(report);
    final obstruction = Directory('${directory.path}/reports.json.tmp');
    await obstruction.create();
    final journal = File('${directory.path}/reports.json');

    for (final delay in <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    ]) {
      final previous = (await queue.open()).single;
      final expected = previous.retryAt(now.add(delay));
      await expectLater(queue.scheduleRetry(report.reportId),
          throwsA(isA<FileSystemException>()));
      expect((await queue.open()).single.hasSameContents(expected), isTrue);
      expect(await queue.due(), isEmpty);
      final published =
          jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      expect((published['records'] as List<dynamic>).single, report.toJson());
      now = expected.nextRetryAt;
      expect((await queue.due()).single.hasSameContents(expected), isTrue);
    }

    await obstruction.delete();
    final expected = (await queue.open()).single.retryAt(
          now.add(const Duration(seconds: 4)),
        );
    final retried = await queue.scheduleRetry(report.reportId);
    expect(retried?.retryAttempt, 3);
    expect(retried?.hasSameContents(expected), isTrue);
    final restarted = CommerceFileReportQueue(
      directoryPath: directory.path,
      clock: () => now,
    );
    expect((await restarted.open()).single.hasSameContents(expected), isTrue);
    expect(await restarted.due(), isEmpty);
    await queue.acknowledge(report.reportId);
    expect(await queue.open(), isEmpty);
    final acknowledged =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    expect(acknowledged['records'], isEmpty);
  });

  test('does not retain a report when its temporary file cannot be written',
      () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'restage-commerce-report-',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final journalDirectory = '${supportDirectory.path}/journal';
    final queue = CommerceFileReportQueue(directoryPath: journalDirectory);
    await queue.open();
    await Directory('$journalDirectory/reports.json.tmp').create();

    await expectLater(
      queue.enqueue(_report()),
      throwsA(isA<FileSystemException>()),
    );

    expect(await queue.due(), isEmpty);
    expect(await File('$journalDirectory/reports.json').exists(), isFalse);
  });

  test('keeps provider evidence separate for independent transport scopes',
      () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'restage-commerce-report-',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final journalDirectory = '${supportDirectory.path}/journal';
    final firstQueue = CommerceFileReportQueue(directoryPath: journalDirectory);
    final scopeA = _report();
    final scopeB = CommerceReportRecord(
      reportId: 'fa8e6f40-1bc5-4924-9d3b-bd0b5ec3ed29',
      intentId: scopeA.intentId,
      store: scopeA.store,
      storeVerificationData: scopeA.storeVerificationData,
      storeProductId: scopeA.storeProductId,
      storeTransactionId: scopeA.storeTransactionId,
      applicationAnonymousToken: scopeA.applicationAnonymousToken,
      configurationFingerprint: 'second-commerce-scope',
    );

    expect(await firstQueue.enqueue(scopeA), same(scopeA));
    expect(await firstQueue.enqueue(scopeB), same(scopeB));

    final reopenedQueue =
        CommerceFileReportQueue(directoryPath: journalDirectory);
    final reopened = await reopenedQueue.open();
    expect(reopened, hasLength(2));
    expect(
      reopened.map((record) => record.configurationFingerprint).toSet(),
      <String>{'test-commerce-scope', 'second-commerce-scope'},
    );
    expect(
      reopened.map((record) => record.reportId).toSet(),
      <String>{scopeA.reportId, scopeB.reportId},
    );
  });

  test('partitions provider identity by owner, product, and exact proof',
      () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'restage-commerce-report-',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final queue = CommerceFileReportQueue(
      directoryPath: '${supportDirectory.path}/journal',
    );
    final original = _report();
    final differentOwner = _copyReport(
      original,
      reportId: 'fa8e6f40-1bc5-4924-9d3b-bd0b5ec3ed29',
      applicationAnonymousToken: 'second-application-owner',
    );
    final differentProduct = _copyReport(
      original,
      reportId: '50f2ca4b-7e04-4b3e-9d0f-899cb83ce1d5',
      storeProductId: 'subscription.annual',
    );
    final differentProof = _copyReport(
      original,
      reportId: '59eb1fa6-e556-46a4-9fb8-1f77244fe865',
      storeVerificationData: 'new.signed.transaction.jws',
    );
    final duplicate = _copyReport(
      original,
      reportId: '65f81e99-48e0-4acf-a532-12a27b6b119c',
    );

    expect(await queue.enqueue(original), same(original));
    expect(await queue.enqueue(differentOwner), same(differentOwner));
    expect(await queue.enqueue(differentProduct), same(differentProduct));
    expect(await queue.enqueue(differentProof), same(differentProof));
    expect(await queue.enqueue(duplicate), same(original));
    expect(await queue.open(), hasLength(4));
  });

  test('rejects an unscoped pre-release journal version', () async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'restage-commerce-report-',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final journalDirectory = '${supportDirectory.path}/journal';
    await Directory(journalDirectory).create();
    await File('$journalDirectory/reports.json').writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'records': const <Object?>[],
      }),
    );

    final queue = CommerceFileReportQueue(directoryPath: journalDirectory);
    await expectLater(queue.open(), throwsFormatException);
  });
}

CommerceReportRecord _report() => CommerceReportRecord(
      reportId: '8ba77254-6ab0-4ec8-ae50-f12273ac1f51',
      intentId: '50f2ca4b-7e04-4b3e-9d0f-899cb83ce1d5',
      store: CommerceStore.appStore,
      storeVerificationData: 'signed.transaction.jws',
      storeProductId: 'subscription.monthly',
      storeTransactionId: 'apple-transaction',
      applicationAnonymousToken: 'application-anonymous-token',
      configurationFingerprint: 'test-commerce-scope',
    );

CommerceReportRecord _copyReport(
  CommerceReportRecord source, {
  required String reportId,
  String? applicationAnonymousToken,
  String? storeProductId,
  String? storeVerificationData,
}) =>
    CommerceReportRecord(
      reportId: reportId,
      intentId: source.intentId,
      store: source.store,
      storeVerificationData:
          storeVerificationData ?? source.storeVerificationData,
      storeProductId: storeProductId ?? source.storeProductId,
      storeTransactionId: source.storeTransactionId,
      applicationAnonymousToken:
          applicationAnonymousToken ?? source.applicationAnonymousToken,
      configurationFingerprint: source.configurationFingerprint,
    );

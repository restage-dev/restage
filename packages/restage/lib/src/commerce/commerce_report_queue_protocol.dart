import 'commerce_store_adapter.dart';

/// One report retained locally until the server acknowledges it.
final class CommerceReportRecord {
  CommerceReportRecord({
    required this.reportId,
    required this.store,
    required this.storeVerificationData,
    required this.storeProductId,
    required this.applicationAnonymousToken,
    required this.configurationFingerprint,
    this.intentId,
    this.storeTransactionId,
    this.retryAttempt = 0,
    DateTime? nextRetryAt,
  }) : nextRetryAt = _utcMilliseconds(
          nextRetryAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ) {
    _requireNonEmpty(reportId, 'reportId');
    _requireNonEmpty(storeVerificationData, 'storeVerificationData');
    _requireNonEmpty(storeProductId, 'storeProductId');
    _requireNonEmpty(applicationAnonymousToken, 'applicationAnonymousToken');
    _requireNonEmpty(configurationFingerprint, 'configurationFingerprint');
    _requireOptionalNonEmpty(intentId, 'intentId');
    _requireOptionalNonEmpty(storeTransactionId, 'storeTransactionId');
    if (retryAttempt < 0) {
      throw ArgumentError.value(
        retryAttempt,
        'retryAttempt',
        'must not be negative',
      );
    }
  }

  final String reportId;
  final String? intentId;
  final CommerceStore store;
  final String storeVerificationData;
  final String storeProductId;
  final String? storeTransactionId;
  final String applicationAnonymousToken;

  /// A non-secret fingerprint of the configured commerce transport scope.
  ///
  /// Records only resume when that scope is configured again. It deliberately
  /// contains neither an endpoint nor credentials.
  final String configurationFingerprint;
  final int retryAttempt;
  final DateTime nextRetryAt;

  bool hasSameProviderIdentity(CommerceReportRecord other) =>
      configurationFingerprint == other.configurationFingerprint &&
      applicationAnonymousToken == other.applicationAnonymousToken &&
      store == other.store &&
      (storeTransactionId ?? storeVerificationData) ==
          (other.storeTransactionId ?? other.storeVerificationData) &&
      storeProductId == other.storeProductId &&
      storeVerificationData == other.storeVerificationData;

  bool hasSameContents(CommerceReportRecord other) =>
      reportId == other.reportId &&
      intentId == other.intentId &&
      store == other.store &&
      storeVerificationData == other.storeVerificationData &&
      storeProductId == other.storeProductId &&
      storeTransactionId == other.storeTransactionId &&
      applicationAnonymousToken == other.applicationAnonymousToken &&
      configurationFingerprint == other.configurationFingerprint &&
      retryAttempt == other.retryAttempt &&
      nextRetryAt == other.nextRetryAt;

  CommerceReportRecord retryAt(DateTime value) => CommerceReportRecord(
        reportId: reportId,
        intentId: intentId,
        store: store,
        storeVerificationData: storeVerificationData,
        storeProductId: storeProductId,
        storeTransactionId: storeTransactionId,
        applicationAnonymousToken: applicationAnonymousToken,
        configurationFingerprint: configurationFingerprint,
        retryAttempt: retryAttempt + 1,
        nextRetryAt: value,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'reportId': reportId,
        if (intentId != null) 'intentId': intentId,
        'store': store.value,
        'storeVerificationData': storeVerificationData,
        'storeProductId': storeProductId,
        if (storeTransactionId != null)
          'storeTransactionId': storeTransactionId,
        'applicationAnonymousToken': applicationAnonymousToken,
        'configurationFingerprint': configurationFingerprint,
        'retryAttempt': retryAttempt,
        'nextRetryAtUtcMilliseconds': nextRetryAt.millisecondsSinceEpoch,
      };

  factory CommerceReportRecord.fromJson(Map<String, Object?> json) {
    final reportId = json['reportId'];
    final intentId = json['intentId'];
    final store = json['store'];
    final verificationData = json['storeVerificationData'];
    final productId = json['storeProductId'];
    final transactionId = json['storeTransactionId'];
    final applicationAnonymousToken = json['applicationAnonymousToken'];
    final configurationFingerprint = json['configurationFingerprint'];
    final retryAttempt = json['retryAttempt'];
    final nextRetryAt = json['nextRetryAtUtcMilliseconds'];
    if (reportId is! String ||
        (intentId != null && intentId is! String) ||
        store is! String ||
        verificationData is! String ||
        productId is! String ||
        (transactionId != null && transactionId is! String) ||
        applicationAnonymousToken is! String ||
        configurationFingerprint is! String ||
        retryAttempt is! int ||
        nextRetryAt is! int) {
      throw const FormatException('Invalid persisted commerce report');
    }
    return CommerceReportRecord(
      reportId: reportId,
      intentId: intentId as String?,
      store: CommerceStore(store),
      storeVerificationData: verificationData,
      storeProductId: productId,
      storeTransactionId: transactionId as String?,
      applicationAnonymousToken: applicationAnonymousToken,
      configurationFingerprint: configurationFingerprint,
      retryAttempt: retryAttempt,
      nextRetryAt:
          DateTime.fromMillisecondsSinceEpoch(nextRetryAt, isUtc: true),
    );
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireOptionalNonEmpty(String? value, String name) {
  if (value != null) _requireNonEmpty(value, name);
}

DateTime _utcMilliseconds(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

/// The bounded retry delay shared by retained reports and in-memory admission.
Duration commerceReportRetryDelay(int attempt) {
  const initial = Duration(seconds: 1);
  const maximum = Duration(minutes: 5);
  final exponent = attempt > 9 ? 9 : attempt;
  final delay = Duration(seconds: initial.inSeconds * (1 << exponent));
  return delay > maximum ? maximum : delay;
}

/// A serialized durable queue for commerce reports.
abstract interface class CommerceReportQueue {
  Future<List<CommerceReportRecord>> open();

  Future<CommerceReportRecord> enqueue(CommerceReportRecord record);

  Future<List<CommerceReportRecord>> due();

  Future<CommerceReportRecord?> scheduleRetry(String reportId);

  Future<void> acknowledge(String reportId);
}

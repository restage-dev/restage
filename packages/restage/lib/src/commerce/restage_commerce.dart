import 'dart:async';

final RegExp _commerceLogicalIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,127}$');
final RegExp _commerceCodePattern = RegExp(r'^[a-z][a-z0-9._]{0,63}$');

String _requireCommerceLogicalId(String value) {
  if (!_commerceLogicalIdPattern.hasMatch(value)) {
    throw FormatException('Invalid commerce logical identifier', value);
  }
  return value;
}

String _requireCommerceCode(String value) {
  if (!_commerceCodePattern.hasMatch(value)) {
    throw FormatException('Invalid commerce code', value);
  }
  return value;
}

/// An application- or Restage-defined logical offer selector.
///
/// It is not a raw provider product ID, offer token or identifier, promo code,
/// receipt, or provider evidence.
final class CommerceOfferId {
  factory CommerceOfferId(String value) =>
      CommerceOfferId._(_requireCommerceLogicalId(value));

  const CommerceOfferId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is CommerceOfferId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A Restage-defined capability code.
///
/// Unknown values are preserved for forward compatibility. Applications and
/// provider adapters must not use this type as a namespace for provider codes.
final class CommerceCapabilityCode {
  factory CommerceCapabilityCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'purchase' => purchase,
      'restore' => restore,
      'purchaser_state.read' => purchaserStateRead,
      _ => CommerceCapabilityCode._(code, false),
    };
  }

  const CommerceCapabilityCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Initiating a purchase for a logical offer.
  static const purchase = CommerceCapabilityCode._('purchase', true);

  /// Restoring purchases through the configured commerce authority.
  static const restore = CommerceCapabilityCode._('restore', true);

  /// Reading the current Restage purchaser state.
  static const purchaserStateRead = CommerceCapabilityCode._(
    'purchaser_state.read',
    true,
  );

  @override
  bool operator ==(Object other) =>
      other is CommerceCapabilityCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A normalized, Restage-defined action status.
///
/// Unknown values are preserved for forward compatibility. Provider status
/// names are mapped to Restage semantics before they reach this boundary.
final class CommerceActionStatusCode {
  factory CommerceActionStatusCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'unavailable' => unavailable,
      'not_presented' => notPresented,
      'dismissed' => dismissed,
      'pending' => pending,
      'submitted_for_reconciliation' => submittedForReconciliation,
      'failed' => failed,
      _ => CommerceActionStatusCode._(code, false),
    };
  }

  const CommerceActionStatusCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// The requested action is not available and was not started.
  static const unavailable = CommerceActionStatusCode._('unavailable', true);

  /// The action ended before any provider presentation began.
  static const notPresented = CommerceActionStatusCode._('not_presented', true);

  /// The provider presentation was dismissed before authoritative completion.
  static const dismissed = CommerceActionStatusCode._('dismissed', true);

  /// The action is still pending and grants no entitlement or fulfillment.
  static const pending = CommerceActionStatusCode._('pending', true);

  /// The action was submitted for asynchronous authority reconciliation.
  ///
  /// This is not proof of purchase, entitlement, fulfillment, refund, or
  /// refund protection. Applications wait for authoritative purchaser state.
  static const submittedForReconciliation = CommerceActionStatusCode._(
    'submitted_for_reconciliation',
    true,
  );

  /// The action ended without authoritative completion.
  static const failed = CommerceActionStatusCode._('failed', true);

  @override
  bool operator ==(Object other) =>
      other is CommerceActionStatusCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A normalized, Restage-defined commerce failure code.
///
/// Unknown values are preserved for forward compatibility. Raw provider
/// errors, identifiers, and evidence do not cross this boundary.
final class CommerceFailureCode {
  factory CommerceFailureCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'not_activated' => notActivated,
      'unsupported_capability' => unsupportedCapability,
      'invalid_request' => invalidRequest,
      'unsupported_response' => unsupportedResponse,
      _ => CommerceFailureCode._(code, false),
    };
  }

  const CommerceFailureCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Commerce has not been activated for this application.
  static const notActivated = CommerceFailureCode._('not_activated', true);

  /// The requested capability is not supported.
  static const unsupportedCapability = CommerceFailureCode._(
    'unsupported_capability',
    true,
  );

  /// The request violates the typed commerce contract.
  static const invalidRequest = CommerceFailureCode._('invalid_request', true);

  /// A response could not be mapped to recognized Restage semantics.
  static const unsupportedResponse = CommerceFailureCode._(
    'unsupported_response',
    true,
  );

  @override
  bool operator ==(Object other) =>
      other is CommerceFailureCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A normalized, Restage-defined purchaser-state status.
///
/// Unknown values are preserved for forward compatibility. Provider status
/// names are mapped to Restage semantics before they reach this boundary.
final class CommercePurchaserStateStatusCode {
  factory CommercePurchaserStateStatusCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'unavailable' => unavailable,
      'available' => available,
      'stale' => stale,
      'unknown' => unknown,
      _ => CommercePurchaserStateStatusCode._(code, false),
    };
  }

  const CommercePurchaserStateStatusCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Purchaser state cannot currently be read.
  static const unavailable = CommercePurchaserStateStatusCode._(
    'unavailable',
    true,
  );

  /// Purchaser state is current from the Restage authority.
  static const available =
      CommercePurchaserStateStatusCode._('available', true);

  /// Retained state may be out of date and must not authorize fulfillment.
  static const stale = CommercePurchaserStateStatusCode._('stale', true);

  /// The authority could not establish the purchaser's current state.
  static const unknown = CommercePurchaserStateStatusCode._('unknown', true);

  @override
  bool operator ==(Object other) =>
      other is CommercePurchaserStateStatusCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

abstract final class CommerceRequest<R extends CommerceResponse> {
  const CommerceRequest._();

  Future<R> _dispatch(RestageCommerce commerce);
}

abstract final class CommerceResponse {
  const CommerceResponse._();
}

final class CommerceAvailabilityRequest
    extends CommerceRequest<CommerceAvailability> {
  const CommerceAvailabilityRequest(this.capability, {this.offerId})
      : super._();

  final CommerceCapabilityCode capability;
  final CommerceOfferId? offerId;

  @override
  Future<CommerceAvailability> _dispatch(RestageCommerce commerce) =>
      commerce.availability(this);

  @override
  bool operator ==(Object other) =>
      other is CommerceAvailabilityRequest &&
      other.capability == capability &&
      other.offerId == offerId;

  @override
  int get hashCode => Object.hash(capability, offerId);
}

/// Requests a purchase of one logical offer.
///
/// The commerce authority resolves [offerId] to the exact purchasable
/// configuration; the request never names provider products, and device input
/// cannot widen what the authority resolved. Selection among multiple
/// purchasable alternatives under one offer is reserved for future optional
/// parameters.
final class CommercePurchaseRequest
    extends CommerceRequest<CommerceActionResult> {
  const CommercePurchaseRequest(this.offerId) : super._();

  final CommerceOfferId offerId;

  @override
  Future<CommerceActionResult> _dispatch(RestageCommerce commerce) =>
      commerce.purchase(this);

  @override
  bool operator ==(Object other) =>
      other is CommercePurchaseRequest && other.offerId == offerId;

  @override
  int get hashCode => offerId.hashCode;
}

final class CommerceRestoreRequest
    extends CommerceRequest<CommerceActionResult> {
  const CommerceRestoreRequest() : super._();

  @override
  Future<CommerceActionResult> _dispatch(RestageCommerce commerce) =>
      commerce.restore();

  @override
  bool operator ==(Object other) => other is CommerceRestoreRequest;

  @override
  int get hashCode => 0;
}

final class CommerceRefreshRequest
    extends CommerceRequest<CommercePurchaserState> {
  const CommerceRefreshRequest() : super._();

  @override
  Future<CommercePurchaserState> _dispatch(RestageCommerce commerce) =>
      commerce.refresh();

  @override
  bool operator ==(Object other) => other is CommerceRefreshRequest;

  @override
  int get hashCode => 0;
}

/// Whether a commerce capability can currently be requested.
final class CommerceAvailability extends CommerceResponse {
  CommerceAvailability._({
    required this.capability,
    required this.offerId,
    required this.available,
    required this.failureCode,
  }) : super._() {
    if (available != (failureCode == null)) {
      throw StateError('Available iff failureCode is null');
    }
    if (!capability.isKnown &&
        failureCode != CommerceFailureCode.unsupportedCapability) {
      throw StateError(
        'Unknown capability requires unsupportedCapability failure code',
      );
    }
  }

  final CommerceCapabilityCode capability;
  final CommerceOfferId? offerId;
  final bool available;
  final CommerceFailureCode? failureCode;

  @override
  bool operator ==(Object other) =>
      other is CommerceAvailability &&
      other.capability == capability &&
      other.offerId == offerId &&
      other.available == available &&
      other.failureCode == failureCode;

  @override
  int get hashCode => Object.hash(capability, offerId, available, failureCode);
}

/// The normalized result of requesting a commerce action.
final class CommerceActionResult extends CommerceResponse {
  CommerceActionResult._({
    required this.status,
    CommerceFailureCode? failureCode,
  })  : failureCode = status.isKnown
            ? failureCode
            : CommerceFailureCode.unsupportedResponse,
        super._() {
    if (status.isKnown) {
      final requiresFailure = status == CommerceActionStatusCode.unavailable ||
          status == CommerceActionStatusCode.failed;
      if (requiresFailure != (this.failureCode != null)) {
        throw StateError('Failure code does not match the known action status');
      }
    }
  }

  final CommerceActionStatusCode status;
  final CommerceFailureCode? failureCode;

  @override
  bool operator ==(Object other) =>
      other is CommerceActionResult &&
      other.status == status &&
      other.failureCode == failureCode;

  @override
  int get hashCode => Object.hash(status, failureCode);
}

/// The current purchaser-state authority status.
final class CommercePurchaserState extends CommerceResponse {
  CommercePurchaserState._({required this.status}) : super._();

  final CommercePurchaserStateStatusCode status;

  @override
  bool operator ==(Object other) =>
      other is CommercePurchaserState && other.status == status;

  @override
  int get hashCode => status.hashCode;
}

abstract final class RestageCommerce {
  CommercePurchaserState get currentState;

  Stream<CommercePurchaserState> get states;

  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  );

  Future<CommerceActionResult> purchase(CommercePurchaseRequest request);

  Future<CommerceActionResult> restore();

  Future<CommercePurchaserState> refresh();

  Future<R> perform<R extends CommerceResponse>(CommerceRequest<R> request);
}

final class _RetainedCommerceStateStream
    extends Stream<CommercePurchaserState> {
  _RetainedCommerceStateStream(this._state);

  final CommercePurchaserState _state;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<CommercePurchaserState> listen(
    void Function(CommercePurchaserState event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<CommercePurchaserState>(sync: true);
    final subscription = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    controller.add(_state);
    return subscription;
  }
}

final class _RestageCommerce implements RestageCommerce {
  _RestageCommerce() {
    _currentState = CommercePurchaserState._(
      status: CommercePurchaserStateStatusCode.unavailable,
    );
    _states = _RetainedCommerceStateStream(_currentState);
  }

  late final CommercePurchaserState _currentState;
  late final Stream<CommercePurchaserState> _states;

  @override
  CommercePurchaserState get currentState => _currentState;

  @override
  Stream<CommercePurchaserState> get states => _states;

  @override
  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  ) async {
    final CommerceFailureCode failureCode;
    if (!request.capability.isKnown) {
      failureCode = CommerceFailureCode.unsupportedCapability;
    } else if (request.offerId != null &&
        request.capability != CommerceCapabilityCode.purchase) {
      failureCode = CommerceFailureCode.invalidRequest;
    } else {
      failureCode = CommerceFailureCode.notActivated;
    }
    return CommerceAvailability._(
      capability: request.capability,
      offerId: request.offerId,
      available: false,
      failureCode: failureCode,
    );
  }

  @override
  Future<CommerceActionResult> purchase(CommercePurchaseRequest request) async {
    return CommerceActionResult._(
      status: CommerceActionStatusCode.unavailable,
      failureCode: CommerceFailureCode.notActivated,
    );
  }

  @override
  Future<CommerceActionResult> restore() async {
    return CommerceActionResult._(
      status: CommerceActionStatusCode.unavailable,
      failureCode: CommerceFailureCode.notActivated,
    );
  }

  @override
  Future<CommercePurchaserState> refresh() async => _currentState;

  @override
  Future<R> perform<R extends CommerceResponse>(CommerceRequest<R> request) =>
      request._dispatch(this);
}

final _RestageCommerce _restageCommerceInstance = _RestageCommerce();

RestageCommerce get restageCommerceInstance => _restageCommerceInstance;

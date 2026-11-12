import 'dart:convert';

import 'package:restage_shared/src/entitlements/commerce_wire.dart';

/// One package-boundary page of a named or current offering.
final class CommerceOfferingsPage {
  /// Creates a page without fetching additional packages.
  CommerceOfferingsPage({
    required int catalogRevision,
    this.currentOfferId,
    this.offering,
    this.nextCursor,
  }) : catalogRevision = commerceCatalogRevision(catalogRevision) {
    if (currentOfferId != null) {
      requireCommerceOfferId(currentOfferId!, 'currentOfferId');
    }
    if (nextCursor != null && nextCursor!.isEmpty) {
      throw ArgumentError.value(nextCursor, 'nextCursor');
    }
  }

  /// Parses a page while allowing future additive response fields.
  factory CommerceOfferingsPage.fromJson(Map<String, dynamic> json) =>
      CommerceOfferingsPage(
        catalogRevision: commerceCatalogRevision(json['catalogRevision']),
        currentOfferId: optionalCommerceString(json, 'currentOfferId'),
        offering: json['offering'] == null
            ? null
            : CommerceOfferingSummary.fromJson(_object(json['offering'])),
        nextCursor: optionalCommerceString(json, 'nextCursor'),
      );

  /// Current catalog association revision.
  final int catalogRevision;

  /// Current offering pointer for the selected environment, when configured.
  final String? currentOfferId;

  /// Selected offering, or null when no matching offering exists.
  final CommerceOfferingSummary? offering;

  /// Opaque continuation at the next package boundary.
  final String? nextCursor;

  /// Converts this value to its wire representation.
  Map<String, dynamic> toJson() => {
        'catalogRevision': catalogRevision,
        'currentOfferId': currentOfferId,
        'offering': offering?.toJson(),
        'nextCursor': nextCursor,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceOfferingsPage &&
          other.catalogRevision == catalogRevision &&
          other.currentOfferId == currentOfferId &&
          other.offering == offering &&
          other.nextCursor == nextCursor;

  @override
  int get hashCode =>
      Object.hash(catalogRevision, currentOfferId, offering, nextCursor);
}

/// A logical offering with its metadata and this page's complete packages.
final class CommerceOfferingSummary {
  /// Creates an offering and freezes its JSON metadata.
  CommerceOfferingSummary({
    required this.offerId,
    required List<CommercePackageSummary> packages,
    Map<String, Object?> metadata = const {},
  })  : metadata = _metadata(metadata),
        packages = List.unmodifiable(packages) {
    requireCommerceOfferId(offerId, 'offerId');
  }

  /// Parses one offering summary.
  factory CommerceOfferingSummary.fromJson(Map<String, dynamic> json) =>
      CommerceOfferingSummary(
        offerId: requiredCommerceString(json, 'offerId'),
        metadata: _object(json['metadata']),
        packages: _entries(json['packages'], CommercePackageSummary.fromJson),
      );

  /// Logical offering identifier used by purchase requests.
  final String offerId;

  /// Immutable JSON metadata, including nested maps and lists.
  final Map<String, Object?> metadata;

  /// Complete logical packages included in this page.
  final List<CommercePackageSummary> packages;

  /// Converts this value to its wire representation.
  Map<String, dynamic> toJson() => {
        'offerId': offerId,
        'metadata': metadata,
        'packages': [for (final package in packages) package.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommerceOfferingSummary &&
          other.offerId == offerId &&
          _sameJson(other.metadata, metadata) &&
          _sameList(other.packages, packages);

  @override
  int get hashCode =>
      Object.hash(offerId, _jsonHash(metadata), Object.hashAll(packages));
}

/// One logical package, retaining every configured store child.
final class CommercePackageSummary {
  /// Creates one ordered logical package.
  CommercePackageSummary({
    required this.packageId,
    required this.position,
    required List<CommercePackageProduct> products,
  }) : products = List.unmodifiable(products) {
    requireCommerceOfferId(packageId, 'packageId');
    if (position < 0) throw ArgumentError.value(position, 'position');
  }

  /// Parses a package including all configured store children.
  factory CommercePackageSummary.fromJson(Map<String, dynamic> json) =>
      CommercePackageSummary(
        packageId: requiredCommerceString(json, 'packageId'),
        position: optionalCommerceInt(json, 'position') ??
            (throw ArgumentError.value(
                json['position'], 'position', 'Expected an int')),
        products: _entries(json['products'], CommercePackageProduct.fromJson),
      );

  /// Logical identifier used as the purchase package selection.
  final String packageId;

  /// Nonnegative position within the offering.
  final int position;

  /// Exact store selections for this package.
  final List<CommercePackageProduct> products;

  /// Converts this value to its wire representation.
  Map<String, dynamic> toJson() => {
        'packageId': packageId,
        'position': position,
        'products': [for (final product in products) product.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommercePackageSummary &&
          other.packageId == packageId &&
          other.position == position &&
          _sameList(other.products, products);

  @override
  int get hashCode =>
      Object.hash(packageId, position, Object.hashAll(products));
}

/// Exact store selection for a package; display values never authorize access.
final class CommercePackageProduct {
  /// Creates an exact store selection.
  CommercePackageProduct({
    required this.store,
    required this.storeProductId,
    required this.productKind,
    this.fulfillmentForm,
    this.basePlanId,
    this.storeOfferIdentifier,
  }) {
    for (final value in [store, storeProductId, productKind]) {
      if (value.isEmpty) throw ArgumentError('Expected a non-empty selection');
    }
    for (final value in [fulfillmentForm, basePlanId, storeOfferIdentifier]) {
      if (value != null && value.isEmpty) {
        throw ArgumentError('Expected a non-empty optional selection');
      }
    }
  }

  /// Parses a store selection while preserving future product forms.
  factory CommercePackageProduct.fromJson(Map<String, dynamic> json) =>
      CommercePackageProduct(
        store: requiredCommerceString(json, 'store'),
        storeProductId: requiredCommerceString(json, 'storeProductId'),
        productKind: requiredCommerceString(json, 'productKind'),
        fulfillmentForm: optionalCommerceString(json, 'fulfillmentForm'),
        basePlanId: optionalCommerceString(json, 'basePlanId'),
        storeOfferIdentifier:
            optionalCommerceString(json, 'storeOfferIdentifier'),
      );

  /// Application store code.
  final String store;

  /// Store SKU retained exactly as configured.
  final String storeProductId;

  /// Provider product form.
  final String productKind;

  /// Configured local fulfillment form for a one-time purchase.
  final String? fulfillmentForm;

  /// Exact Google subscription base plan, when selected.
  final String? basePlanId;

  /// Selected store promotion or subscription offer, when present.
  final String? storeOfferIdentifier;

  /// Converts this value to its wire representation.
  Map<String, dynamic> toJson() => {
        'store': store,
        'storeProductId': storeProductId,
        'productKind': productKind,
        if (fulfillmentForm != null) 'fulfillmentForm': fulfillmentForm,
        if (basePlanId != null) 'basePlanId': basePlanId,
        if (storeOfferIdentifier != null)
          'storeOfferIdentifier': storeOfferIdentifier,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommercePackageProduct &&
          other.store == store &&
          other.storeProductId == storeProductId &&
          other.productKind == productKind &&
          other.fulfillmentForm == fulfillmentForm &&
          other.basePlanId == basePlanId &&
          other.storeOfferIdentifier == storeOfferIdentifier;

  @override
  int get hashCode => Object.hash(store, storeProductId, productKind,
      fulfillmentForm, basePlanId, storeOfferIdentifier);
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

bool _sameJson(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    return left.length == right.length &&
        left.entries.every((entry) =>
            right.containsKey(entry.key) &&
            _sameJson(entry.value, right[entry.key]));
  }
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_sameJson(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) => switch (value) {
      Map<String, Object?>() => Object.hashAllUnordered(value.entries
          .map((entry) => Object.hash(entry.key, _jsonHash(entry.value)))),
      List<Object?>() => Object.hashAll(value.map(_jsonHash)),
      _ => value.hashCode,
    };

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw ArgumentError('Expected an object');
  }
  return value;
}

List<T> _entries<T>(Object? value, T Function(Map<String, dynamic>) decode) {
  if (value is! List) throw ArgumentError('Expected a list');
  return [for (final entry in value) decode(_object(entry))];
}

Map<String, Object?> _metadata(Map<String, Object?> value) {
  if (utf8.encode(jsonEncode(value)).length > commerceMetadataMaxBytes) {
    throw ArgumentError('Offering metadata is too large');
  }
  Object? freeze(Object? value, int depth) {
    if (depth > 16) throw ArgumentError('Offering metadata is too deep');
    return switch (value) {
      Map<String, Object?>() => Map<String, Object?>.unmodifiable({
          for (final entry in value.entries)
            entry.key: freeze(entry.value, depth + 1),
        }),
      List<Object?>() => List<Object?>.unmodifiable(
          value.map((entry) => freeze(entry, depth + 1))),
      null || String() || bool() || int() => value,
      double() when value.isFinite => value,
      _ => throw ArgumentError('Expected JSON metadata'),
    };
  }

  return freeze(value, 0)! as Map<String, Object?>;
}

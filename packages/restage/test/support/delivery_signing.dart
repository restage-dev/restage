import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/src/surface_delivery/delivery_signing_testing.dart';

export 'package:restage_shared/src/surface_delivery/delivery_signing_testing.dart'
    show TestDeliverySigner;

/// The key every test in this package is configured to accept.
final TestDeliverySigner testDeliverySigner =
    TestDeliverySigner(organizationId: 1);

/// A well-formed signature no key verifies; [testDeliverySigner.signed]
/// replaces it.
final DeliverySignature unsignedTestSignature =
    DeliverySignature(keyId: '0' * 16, bytes: Uint8List(64));

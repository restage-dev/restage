// ignore_for_file: implementation_imports
import 'package:restage_shared/src/surface_delivery/delivery_signing_testing.dart';

/// Stands in for the server's signing key in the in-app fake servers.
final demoDeliverySigner = TestDeliverySigner();

/// The public half, as `Restage.configure(deliveryKeys:)` takes it.
String get demoDeliveryKey => demoDeliverySigner.publicKey.toString();

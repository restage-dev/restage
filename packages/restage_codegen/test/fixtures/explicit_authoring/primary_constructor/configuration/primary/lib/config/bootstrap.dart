// @dart=3.13
import 'package:restage/restage.dart';

class Bootstrap(final String name) {
  void configure() {
    Restage.configure(apiKey: 'rs_pk_test', measurementEnabled: false);
  }
}

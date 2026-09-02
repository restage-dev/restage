import 'package:restage/restage.dart';

const bool disableMeasurement = false;

void configureApp() {
  Restage.configure(
    apiKey: 'rs_pk_test',
    measurementEnabled: disableMeasurement,
  );
}

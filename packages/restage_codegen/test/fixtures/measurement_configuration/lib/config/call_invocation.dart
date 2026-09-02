import 'package:restage/restage.dart';

void configureApp() {
  Restage.configure.call(
    apiKey: 'rs_pk_test',
    measurementEnabled: false,
  );
}

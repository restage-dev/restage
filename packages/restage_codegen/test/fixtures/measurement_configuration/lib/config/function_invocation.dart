import 'package:restage/restage.dart';

void configureApp() {
  (Restage.configure)(
    apiKey: 'rs_pk_test',
    measurementEnabled: false,
  );
}

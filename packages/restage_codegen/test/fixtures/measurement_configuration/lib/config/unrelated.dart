class AppConfiguration {
  static void configure({bool? measurementEnabled}) {}
}

void configureApp() {
  AppConfiguration.configure(measurementEnabled: false);
  (AppConfiguration.configure)(measurementEnabled: false);
  AppConfiguration.configure.call(measurementEnabled: false);
}

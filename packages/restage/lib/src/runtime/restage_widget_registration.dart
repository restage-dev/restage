/// An app's widget and icon registration for `Restage.configure`.
abstract interface class RestageWidgetRegistration {
  /// Adds app entries and any complete widget families its mode enables.
  void call({
    required bool includeMaterial,
    required bool includeCupertino,
  });
}

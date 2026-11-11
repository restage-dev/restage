/// An app's widget and icon registration for `Restage.configure`.
abstract interface class RestageWidgetRegistration {
  /// Adds app entries and any complete widget families its mode enables.
  void call({
    required bool includeMaterial,
    required bool includeCupertino,
  });
}

/// The publishable key and service URL in an app's generated Restage setup.
///
/// Generated `kRestageWidgetRegistration` is that setup: it registers the
/// app's widgets and, when build.yaml sets `api_key` and `base_url`, carries
/// them too, so `Restage.configure(registerWidgets: kRestageWidgetRegistration)`
/// needs no `apiKey` or `baseUrl`.
abstract interface class RestageBuildDelivery implements RestageBuildAnalytics {
  /// The publishable key (`rs_pk_...`).
  String get apiKey;

  /// The service URL.
  String get baseUrl;

  /// The delivery channel build.yaml names, or null.
  String? get channel;

  @override
  bool get analyticsEnabled;
}

/// The analytics default an app's build.yaml sets.
abstract interface class RestageBuildAnalytics {
  /// True unless build.yaml sets `analytics: false`.
  bool get analyticsEnabled;
}

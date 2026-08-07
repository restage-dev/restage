/// Finite code-owned authority for deployed render-bundle origin pairs.
///
/// This library is intentionally absent from the public `restage_shared`
/// barrel. Adding a future deployment root requires an explicit code change;
/// configuration cannot nominate a new credential-bearing trust boundary.
const Set<String> _approvedDeploymentRoots = <String>{'restage.dev'};
const String _localApiHost = 'api.restage.localhost';
const String _localDashboardHost = 'dashboard.restage.localhost';
const String _localBundleControlHost = 'bundles.restage.localhost';
const String _localSiteSuffix = '.restage.localhost';

/// Exact decimal ceiling for immutable PostgreSQL signed-64 bundle ids.
///
/// This is a decimal string because JavaScript runtimes cannot represent the
/// signed-64 maximum exactly as a Dart [int].
const String maxSignedRenderBundleIdDecimal = '9223372036854775807';

/// Whether [source] is one of the finite code-approved deployment roots.
bool isApprovedRenderBundleDeploymentRoot(String source) =>
    _approvedDeploymentRoots.contains(source);

/// Whether [origin] is an exact code-approved render-bundle parent authority.
bool isApprovedRenderBundleParentOrigin(Uri origin) =>
    _isExactLocalHttpOrigin(origin, _localDashboardHost) ||
    _isApprovedDirectDeployedOrigin(origin);

/// Whether [apiOrigin], [dashboardOrigin], and [bundleOrigin] form one exact
/// render-bundle authority triplet.
///
/// Deployed origins must be pairwise-distinct, direct HTTPS siblings beneath
/// one code-approved deployment root. Local origins must use the finite
/// `api.restage.localhost`, `dashboard.restage.localhost`, and
/// `bundles.restage.localhost` roles with pairwise-distinct explicit ports.
bool isApprovedRenderBundleOriginTriplet(
  Uri apiOrigin,
  Uri dashboardOrigin,
  Uri bundleOrigin,
) {
  final origins = <Uri>[apiOrigin, dashboardOrigin, bundleOrigin];
  final deployed = _approvedDeploymentRoots.any(
    (root) => origins.every(
      (origin) =>
          _isExactDefaultHttpsOrigin(origin) &&
          _isDirectHostUnderRoot(origin.host, root),
    ),
  );
  if (deployed) {
    return origins.map((origin) => origin.origin).toSet().length ==
        origins.length;
  }

  final local = _isExactLocalHttpOrigin(apiOrigin, _localApiHost) &&
      _isExactLocalHttpOrigin(dashboardOrigin, _localDashboardHost) &&
      _isExactLocalHttpOrigin(bundleOrigin, _localBundleControlHost);
  return local &&
      origins.map((origin) => origin.port).toSet().length == origins.length;
}

/// Whether a local preview shell and control origin use the finite dev roles.
bool isApprovedRenderBundleLocalShellControlPair(
  Uri shellOrigin,
  Uri controlOrigin,
) =>
    _isExactLocalHttpOrigin(shellOrigin, _localDashboardHost) &&
    _isExactLocalHttpOrigin(controlOrigin, _localBundleControlHost) &&
    shellOrigin.port != controlOrigin.port;

/// Whether a local API and control origin use the finite dev roles.
bool isApprovedRenderBundleLocalApiControlPair(
  Uri apiOrigin,
  Uri controlOrigin,
) =>
    _isExactLocalHttpOrigin(apiOrigin, _localApiHost) &&
    _isExactLocalHttpOrigin(controlOrigin, _localBundleControlHost) &&
    apiOrigin.port != controlOrigin.port;

/// Whether [controlOrigin] and [bundleOrigin] are distinct direct HTTPS
/// siblings beneath one code-approved deployment root.
///
/// This check is deterministic and performs no DNS or public-suffix lookup.
bool isApprovedRenderBundleDeployedOriginPair(
  Uri controlOrigin,
  Uri bundleOrigin,
) {
  if (!_isApprovedDirectDeployedOrigin(controlOrigin) ||
      !_isApprovedDirectDeployedOrigin(bundleOrigin) ||
      controlOrigin.origin == bundleOrigin.origin) {
    return false;
  }
  for (final root in _approvedDeploymentRoots) {
    if (_isDirectHostUnderRoot(controlOrigin.host, root) &&
        _isDirectHostUnderRoot(bundleOrigin.host, root)) {
      return true;
    }
  }
  return false;
}

/// Derives the exact browser execution origin for one immutable bundle.
///
/// [configuredBundleOrigin] is the upload/control authority. Local execution
/// uses one host under the finite `restage.localhost` dev site per id.
/// Deployed execution uses one direct sibling label under the same finite,
/// code-approved deployment root.
Uri? deriveRenderBundleExecutionOrigin(
  Uri configuredBundleOrigin,
  int renderBundleId,
) {
  final id = _validRenderBundleIdDecimal(renderBundleId);
  if (id == null) return null;
  return _deriveRenderBundleExecutionOrigin(configuredBundleOrigin, id);
}

/// Whether [configuredBundleOrigin] can derive an origin at the exact
/// PostgreSQL signed-64 id ceiling.
///
/// This capacity check uses the ceiling's exact decimal representation, so it
/// behaves identically on VM and JavaScript runtimes.
bool canDeriveMaxSignedRenderBundleExecutionOrigin(
  Uri configuredBundleOrigin,
) =>
    _deriveRenderBundleExecutionOrigin(
      configuredBundleOrigin,
      maxSignedRenderBundleIdDecimal,
    ) !=
    null;

Uri? _deriveRenderBundleExecutionOrigin(
  Uri configuredBundleOrigin,
  String id,
) {
  if (_isExactLocalHttpOrigin(
    configuredBundleOrigin,
    _localBundleControlHost,
  )) {
    return Uri(
      scheme: 'http',
      host: 'b-$id$_localSiteSuffix',
      port: configuredBundleOrigin.port,
    );
  }
  if (!_isApprovedDirectDeployedOrigin(configuredBundleOrigin)) return null;

  for (final root in _approvedDeploymentRoots) {
    final suffix = '.$root';
    if (!configuredBundleOrigin.host.endsWith(suffix)) continue;
    final configuredLabel = configuredBundleOrigin.host.substring(
      0,
      configuredBundleOrigin.host.length - suffix.length,
    );
    final executionLabel = 'rb-$id-$configuredLabel';
    if (!_isDnsLabel(executionLabel)) return null;
    return Uri(scheme: 'https', host: '$executionLabel.$root');
  }
  return null;
}

String? _validRenderBundleIdDecimal(int renderBundleId) {
  if (renderBundleId < 1) return null;
  final decimal = '$renderBundleId';
  if (decimal.length > maxSignedRenderBundleIdDecimal.length ||
      (decimal.length == maxSignedRenderBundleIdDecimal.length &&
          decimal.compareTo(maxSignedRenderBundleIdDecimal) > 0)) {
    return null;
  }
  return decimal;
}

/// Whether [executionOrigin] is the exact derived origin for [renderBundleId].
bool isExactRenderBundleExecutionOrigin({
  required Uri configuredBundleOrigin,
  required int renderBundleId,
  required Uri executionOrigin,
}) =>
    deriveRenderBundleExecutionOrigin(
      configuredBundleOrigin,
      renderBundleId,
    ) ==
    executionOrigin;

bool _isApprovedDirectDeployedOrigin(Uri uri) =>
    _isExactDefaultHttpsOrigin(uri) &&
    _approvedDeploymentRoots.any(
      (root) => _isDirectHostUnderRoot(uri.host, root),
    );

bool _isExactDefaultHttpsOrigin(Uri uri) =>
    _isExactOrigin(uri) && uri.scheme == 'https' && !uri.hasPort;

bool _isExactLocalHttpOrigin(Uri uri, String expectedHost) =>
    _isExactOrigin(uri) &&
    uri.scheme == 'http' &&
    uri.hasPort &&
    uri.host == expectedHost;

bool _isExactOrigin(Uri uri) =>
    uri.isAbsolute &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    (uri.path.isEmpty || uri.path == '/') &&
    !uri.hasQuery &&
    !uri.hasFragment;

bool _isDirectHostUnderRoot(String host, String root) {
  final suffix = '.$root';
  if (!host.endsWith(suffix)) return false;
  final label = host.substring(0, host.length - suffix.length);
  return !label.contains('.') && _isDnsLabel(label);
}

bool _isDnsLabel(String label) {
  if (label.isEmpty ||
      label.length > 63 ||
      label.startsWith('xn--') ||
      label.startsWith('-') ||
      label.endsWith('-')) {
    return false;
  }
  for (final codeUnit in label.codeUnits) {
    final isAsciiLower = codeUnit >= 0x61 && codeUnit <= 0x7a;
    final isAsciiDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    if (!isAsciiLower && !isAsciiDigit && codeUnit != 0x2d) return false;
  }
  return true;
}

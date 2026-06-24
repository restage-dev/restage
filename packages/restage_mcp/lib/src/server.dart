import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';

/// Backend origin used for in-server login when no credential exists yet.
/// Overridable at build time via `--define`; falls back to localhost.
const _defaultLoginEndpoint = String.fromEnvironment(
  'RESTAGE_DEFAULT_ENDPOINT',
  defaultValue: 'http://localhost:8080/',
);

/// How long a single `restage_login` poll call blocks before returning a
/// "still waiting" prompt — kept well under typical MCP-host request timeouts.
const _loginPollBudget = Duration(seconds: 30);

/// The server version reported to MCP hosts. Keep in sync with `pubspec.yaml`.
const restageMcpVersion = '0.1.0';

/// The Restage MCP server.
///
/// Exposes the Restage backend to an MCP host over the tools capability,
/// reusing the CLI's HTTP/auth/credential layer. Authentication comes from the
/// shared cached credential written by `restage login`.
base class RestageMcpServer extends MCPServer with ToolsSupport {
  /// Build the server over [channel] (typically a stdio channel).
  ///
  /// [credentialStore] and [httpClient] default to the shared on-disk
  /// credential and a fresh HTTP client per call. [sleep], [openBrowser],
  /// [loginEndpoint], and [now] are injectable so the device-code login can be
  /// driven against a fake backend in tests.
  ///
  /// The embedding API is `@experimental`: this constructor's signature is
  /// coupled to the pre-1.0 underlying MCP framework types ([channel], the
  /// [MCPServer] base) and may change as that framework stabilizes. Most users
  /// launch the `restage_mcp` executable directly rather than embedding the
  /// server in their own Dart code.
  @experimental
  RestageMcpServer.fromStreamChannel(
    super.channel, {
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
    Future<void> Function(String)? openBrowser,
    Uri? loginEndpoint,
    DateTime Function()? now,
  }) : _credentialStore = credentialStore,
       _httpClient = httpClient,
       _sleep = sleep ?? _defaultSleep,
       _openBrowser = openBrowser ?? _defaultOpenBrowser,
       _loginEndpoint = loginEndpoint,
       _now = now ?? DateTime.now,
       super.fromStreamChannel(
         implementation: Implementation(
           name: 'restage',
           version: restageMcpVersion,
         ),
         instructions:
             'Manage Restage paywalls and configuration. Sign in with '
             'restage_login (or reuse an existing `restage login` session).',
       ) {
    // Every handler is wrapped in _scrubbed: the by-construction value funnel
    // that removes the secrets this server holds (the session token + the
    // in-flight device grant) from every result, so no auth path — withApi,
    // raw-auth, or future — can surface them.
    registerTool(_loginTool, _scrubbed(_handleLogin));
    registerTool(_whoamiTool, _scrubbed(_handleWhoami));
    registerTool(_logoutTool, _scrubbed(_handleLogout));
    registerTool(_listPaywallsTool, _scrubbed(_handleListPaywalls));
    registerTool(_getPaywallTool, _scrubbed(_handleGetPaywall));
    registerTool(_publishPaywallTool, _scrubbed(_handlePublishPaywall));
    registerTool(
      _getPublishedVersionTool,
      _scrubbed(_handleGetPublishedVersion),
    );
    registerTool(_listOrganizationsTool, _scrubbed(_handleListOrganizations));
    registerTool(_listProjectsTool, _scrubbed(_handleListProjects));
    registerTool(_listAppsTool, _scrubbed(_handleListApps));
    registerTool(_listEnvironmentsTool, _scrubbed(_handleListEnvironments));
    registerTool(_listProductsTool, _scrubbed(_handleListProducts));
    registerTool(_importProductsTool, _scrubbed(_handleImportProducts));
    registerTool(_listProductSlotsTool, _scrubbed(_handleListProductSlots));
    registerTool(_upsertProductSlotTool, _scrubbed(_handleUpsertProductSlot));
    registerTool(
      _listStoreConnectionsTool,
      _scrubbed(_handleListStoreConnections),
    );
    registerTool(_getAppConfigTool, _scrubbed(_handleGetAppConfig));
    registerTool(_updateAppConfigTool, _scrubbed(_handleUpdateAppConfig));
    registerTool(_listApiKeysTool, _scrubbed(_handleListApiKeys));
    registerTool(_revokeApiKeyTool, _scrubbed(_handleRevokeApiKey));
  }

  /// Wrap [handler] so its result passes through the held-secret value funnel
  /// ([_scrubHeldSecrets]) before reaching the client.
  Future<CallToolResult> Function(CallToolRequest) _scrubbed(
    Future<CallToolResult> Function(CallToolRequest) handler,
  ) {
    return (request) async => _scrubHeldSecrets(await handler(request));
  }

  /// Remove the secrets this server holds — the stored session token (the full
  /// `keyId:key` and the bare key part) and any in-flight device grant — from
  /// [result]. Both are high-entropy values that can never legitimately appear
  /// in a tool result, so this cannot corrupt honest output. The single,
  /// uniform value funnel for every auth path.
  Future<CallToolResult> _scrubHeldSecrets(CallToolResult result) async {
    final secrets = <String>{};
    try {
      final credential = await _store.read();
      final authToken = credential?.authToken ?? '';
      if (authToken.isNotEmpty) {
        secrets.add(authToken);
        final colon = authToken.indexOf(':');
        if (colon >= 0 && colon + 1 < authToken.length) {
          secrets.add(authToken.substring(colon + 1));
        }
      }
      // A corrupt credentials file makes read() throw (its message can embed
      // the file's bytes). The funnel runs OUTSIDE the handler's guardErrors, so
      // it must swallow that — the handler already failed closed on the same
      // corrupt file (a clean error with no secret), leaving nothing to scrub.
    } on Object {
      // Intentionally ignored — see above.
    }
    final deviceCode = _pendingLogin?.deviceCode ?? '';
    if (deviceCode.isNotEmpty) secrets.add(deviceCode);
    return secrets.isEmpty ? result : scrubValues(result, secrets);
  }

  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final Future<void> Function(Duration) _sleep;
  final Future<void> Function(String) _openBrowser;
  final Uri? _loginEndpoint;
  final DateTime Function() _now;

  /// The in-flight device-authorization attempt, if any. Holds the device-code
  /// secret in process memory only — it is never returned to the client.
  _PendingLogin? _pendingLogin;

  /// Optional organization-id property reused by the paywall tools to
  /// disambiguate when the caller belongs to several organizations.
  static final _organizationIdProperty = Schema.int(
    description:
        'Optional organization id (from restage_list_organizations) to '
        'disambiguate when you belong to more than one organization.',
  );

  static final _listPaywallsTool = Tool(
    name: 'restage_list_paywalls',
    description:
        'List the paywalls under a Restage project and app. Returns each '
        "paywall's slug, name, last-draft timestamp, and per-environment "
        'published versions.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(
          description: 'The app slug under the project.',
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug'],
    ),
  );

  static final _getPaywallTool = Tool(
    name: 'restage_get_paywall',
    description:
        'Download the compiled draft blob of a paywall as base64 — useful for '
        'backup, inspection, or round-tripping. The blob is compiled binary, '
        'not human- or agent-editable; this tool is for inspection and backup, '
        'not authoring.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'paywallSlug': Schema.string(description: 'The paywall slug.'),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug', 'paywallSlug'],
    ),
  );

  static final _publishPaywallTool = Tool(
    name: 'restage_publish_paywall',
    description:
        'Publish a paywall\'s current draft to an environment. Returns the new '
        'published version number (monotonic per paywall + environment). '
        'Requires an admin role on the organization.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'paywallSlug': Schema.string(description: 'The paywall slug.'),
        'environmentSlug': Schema.string(
          description: 'The target environment slug (e.g. production).',
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug', 'paywallSlug', 'environmentSlug'],
    ),
  );

  static final _getPublishedVersionTool = Tool(
    name: 'restage_get_published_version',
    description:
        'Get the most-recent published version number of a paywall in an '
        'environment, or null when it has never been published there.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'paywallSlug': Schema.string(description: 'The paywall slug.'),
        'environmentSlug': Schema.string(
          description: 'The environment slug (e.g. production).',
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug', 'paywallSlug', 'environmentSlug'],
    ),
  );

  static final _listOrganizationsTool = Tool(
    name: 'restage_list_organizations',
    description:
        'List the organizations the signed-in account belongs to. Returns '
        "each organization's id, slug, name, and your role. Use an "
        'organizationId to address its projects, apps, and environments.',
    inputSchema: Schema.object(properties: {}),
  );

  static final _listProjectsTool = Tool(
    name: 'restage_list_projects',
    description:
        'List the projects under an organization. Call '
        'restage_list_organizations first to obtain the organizationId.',
    inputSchema: Schema.object(
      properties: {
        'organizationId': Schema.int(
          description: 'The organization id (from restage_list_organizations).',
        ),
      },
      required: ['organizationId'],
    ),
  );

  static final _listAppsTool = Tool(
    name: 'restage_list_apps',
    description: 'List the apps under a project in an organization.',
    inputSchema: Schema.object(
      properties: {
        'organizationId': Schema.int(description: 'The organization id.'),
        'projectSlug': Schema.string(description: 'The project slug.'),
      },
      required: ['organizationId', 'projectSlug'],
    ),
  );

  static final _listEnvironmentsTool = Tool(
    name: 'restage_list_environments',
    description:
        'List the environments under a project in an organization '
        '(e.g. dev, staging, production).',
    inputSchema: Schema.object(
      properties: {
        'organizationId': Schema.int(description: 'The organization id.'),
        'projectSlug': Schema.string(description: 'The project slug.'),
      },
      required: ['organizationId', 'projectSlug'],
    ),
  );

  // ---- Products / store ----

  /// The store-vendor enum, serialized by name on the wire.
  static const _storeVendorValues = ['appStore', 'playStore'];

  static final _listProductsTool = Tool(
    name: 'restage_list_products',
    description:
        'List the store products (SKUs) imported for an app, optionally '
        'filtered to one store. Each product carries its store, store product '
        'id, display name, price, and the product slot it is mapped to (if '
        'any).',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'store': Schema.string(
          description:
              'Optional store filter: "appStore" (Apple) or "playStore" '
              '(Google). Omit to list both stores.',
          enumValues: _storeVendorValues,
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug'],
    ),
  );

  static final _importProductsTool = Tool(
    name: 'restage_import_products',
    description:
        "Re-fetch a store's product catalog and upsert each entry as a "
        'product, refreshing prices and display names. Requires a verified '
        'store connection for that store and an admin role. Returns the '
        'upserted products.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'store': Schema.string(
          description:
              'Which store catalog to import: "appStore" (Apple) or '
              '"playStore" (Google).',
          enumValues: _storeVendorValues,
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug', 'store'],
    ),
  );

  static final _listProductSlotsTool = Tool(
    name: 'restage_list_product_slots',
    description:
        'List the product slots for an app. A slot is the paywall-facing handle '
        'for an entitlement; it owns the entitlement string that purchasing a '
        'mapped product grants. (To see which store products map to which slot, '
        'list products and read each product\'s product slot.)',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug'],
    ),
  );

  static final _upsertProductSlotTool = Tool(
    name: 'restage_upsert_product_slot',
    description:
        'Create or update a product slot and its store-product mapping. '
        'Requires an admin role. WARNING — this sets the slot\'s COMPLETE '
        'product mapping (full replace): any store id you omit or pass as null '
        'is UNMAPPED from this slot. To keep an existing mapping you MUST pass '
        'its current product id — call restage_list_product_slots and '
        'restage_list_products first to read the current mappings.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'name': Schema.string(
          description: 'The slot name (the handle a paywall references).',
        ),
        'entitlement': Schema.string(
          description:
              'The entitlement string purchasing a mapped product grants.',
        ),
        'iosProductId': _slotProductIdProperty('App Store (iOS)'),
        'androidProductId': _slotProductIdProperty('Play Store (Android)'),
        'organizationId': _organizationIdProperty,
      },
      // iosProductId + androidProductId are REQUIRED-but-nullable so the agent
      // must consciously state each store every call (full replace) — it cannot
      // silently drop a store by forgetting the field. Pass null to unmap.
      required: [
        'projectSlug',
        'appSlug',
        'name',
        'entitlement',
        'iosProductId',
        'androidProductId',
      ],
    ),
  );

  /// A required-but-nullable store-product-id property for the upsert tool.
  /// The key must be present every call (full-replace footgun-guard); its value
  /// is the product id to map for [storeLabel], or `null` to unmap that store.
  static Schema _slotProductIdProperty(String storeLabel) => Schema.combined(
    description:
        'The $storeLabel store product id to map to this slot, or null to '
        'UNMAP $storeLabel from it. Required every call (full replace): pass '
        'the CURRENT id to keep an existing mapping.',
    anyOf: [Schema.string(), Schema.nil()],
  );

  static final _listStoreConnectionsTool = Tool(
    name: 'restage_list_store_connections',
    description:
        'List the store connections configured for an app (one per store). '
        'Returns non-secret connection metadata only — store, status, the '
        'store app identifier, a short credential fingerprint, the RTDN topic, '
        'and timestamps. The stored credential bundle is never returned.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug'],
    ),
  );

  // ---- App configuration ----

  static final _getAppConfigTool = Tool(
    name: 'restage_get_app_config',
    description:
        'Get an app\'s platform configuration: its iOS bundle id, Android '
        'package name, and web domain (plus id, slug, and name). Needs the '
        'organization id (from restage_list_organizations).',
    inputSchema: Schema.object(
      properties: {
        'organizationId': Schema.int(
          description: 'The organization id (from restage_list_organizations).',
        ),
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
      },
      required: ['organizationId', 'projectSlug', 'appSlug'],
    ),
  );

  static final _updateAppConfigTool = Tool(
    name: 'restage_update_app_config',
    description:
        'Update an app\'s platform configuration. Requires an admin role. Each '
        'field is independent: OMIT a field to leave it unchanged; pass an '
        'EMPTY STRING to clear it. Returns the updated app.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'iosBundleId': Schema.string(
          description:
              'New iOS bundle id. Omit to leave unchanged; empty string to '
              'clear.',
        ),
        'androidPackage': Schema.string(
          description:
              'New Android package name. Omit to leave unchanged; empty string '
              'to clear.',
        ),
        'webDomain': Schema.string(
          description:
              'New web domain. Omit to leave unchanged; empty string to clear.',
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug'],
    ),
  );

  // ---- API keys (admin: audit + kill only; no mint) ----

  static final _listApiKeysTool = Tool(
    name: 'restage_list_api_keys',
    description:
        'List the active API keys for an app environment. Returns redacted '
        'views only — id, kind, a short key prefix, and lifecycle timestamps. '
        'The key hash and plaintext are never returned. (Minting is not '
        'available here; it issues a one-time secret — use the dashboard '
        'or CLI.)',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'environmentSlug': Schema.string(
          description: 'The environment slug (e.g. production).',
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug', 'environmentSlug'],
    ),
  );

  static final _revokeApiKeyTool = Tool(
    name: 'restage_revoke_api_key',
    description:
        'Revoke an API key by its id (from restage_list_api_keys). Requires an '
        'admin role. Idempotent — revoking an already-revoked key is a no-op.',
    inputSchema: Schema.object(
      properties: {
        'projectSlug': Schema.string(description: 'The project slug.'),
        'appSlug': Schema.string(description: 'The app slug.'),
        'apiKeyId': Schema.int(
          description: 'The id of the key to revoke (from list_api_keys).',
        ),
        'organizationId': _organizationIdProperty,
      },
      required: ['projectSlug', 'appSlug', 'apiKeyId'],
    ),
  );

  static final _loginTool = Tool(
    name: 'restage_login',
    description:
        'Sign in to Restage with the device-authorization flow. Call it once '
        'to start: it returns a verification URL and a short code and opens '
        'your browser. Approve there, THEN call restage_login AGAIN to '
        'complete sign-in. If a session is already active, it says so instead.',
    inputSchema: Schema.object(properties: {}),
  );

  static final _whoamiTool = Tool(
    name: 'restage_whoami',
    description:
        'Report whether a Restage session is active and, if so, the '
        'signed-in account.',
    inputSchema: Schema.object(properties: {}),
  );

  static final _logoutTool = Tool(
    name: 'restage_logout',
    description:
        'Sign out: revoke the stored Restage session and remove the local '
        'credential.',
    inputSchema: Schema.object(properties: {}),
  );

  /// The shared credential store — the injected one in tests, else the
  /// default shared on-disk location.
  FileCredentialStore get _store =>
      _credentialStore ?? FileCredentialStore.atDefaultLocation();

  /// The authenticated [withApi] seam bound to this server's store and client.
  /// Resolves the cached credential, runs [body], maps errors, and closes.
  Future<CallToolResult> _withApi(
    String action,
    Future<CallToolResult> Function(RestageApi api) body,
  ) => withApi(
    store: _store,
    httpClient: _httpClient,
    action: action,
    body: body,
  );

  /// Build a [RestageApi] against [endpoint] (optionally authed with
  /// [credential]), run [body], and close the client iff this server created
  /// it. The single home for the "only close what we created" rule.
  Future<T> _withRawApi<T>(
    Uri endpoint, {
    Credential? credential,
    required Future<T> Function(RestageApi api) body,
  }) async {
    final api = RestageApi(
      endpoint: endpoint,
      credential: credential,
      httpClient: _httpClient,
    );
    try {
      return await body(api);
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Handle a `restage_list_paywalls` call.
  ///
  /// Arguments are schema-validated by the framework before this runs, so the
  /// slugs are present and well-typed here. The shared [withApi] seam resolves
  /// auth, maps errors, and closes the client; the defensive catch-all there
  /// keeps any unexpected throwable (and its stack/secret) off the channel.
  Future<CallToolResult> _handleListPaywalls(CallToolRequest request) {
    final projectSlug = request.str('projectSlug');
    final appSlug = request.str('appSlug');
    final organizationId = request.optInt('organizationId');
    return _withApi('listing paywalls', (api) async {
      final summaries = await PaywallApi(api).list(
        project: projectSlug,
        app: appSlug,
        organizationId: organizationId,
      );
      return jsonResult(<String, Object?>{
        'paywalls': [for (final summary in summaries) summary.toJson()],
      });
    });
  }

  /// Handle `restage_get_paywall` — download the compiled draft blob as base64.
  Future<CallToolResult> _handleGetPaywall(CallToolRequest request) {
    final projectSlug = request.str('projectSlug');
    final appSlug = request.str('appSlug');
    final paywallSlug = request.str('paywallSlug');
    final organizationId = request.optInt('organizationId');
    return _withApi('downloading the paywall', (api) async {
      final bytes = await PaywallApi(api).load(
        project: projectSlug,
        app: appSlug,
        paywall: paywallSlug,
        organizationId: organizationId,
      );
      return jsonResult(<String, Object?>{
        'projectSlug': projectSlug,
        'appSlug': appSlug,
        'paywallSlug': paywallSlug,
        'byteLength': bytes.length,
        'paywallBase64': base64Encode(bytes),
      });
    });
  }

  /// Handle `restage_publish_paywall` — publish a draft to an environment.
  Future<CallToolResult> _handlePublishPaywall(CallToolRequest request) {
    final projectSlug = request.str('projectSlug');
    final appSlug = request.str('appSlug');
    final paywallSlug = request.str('paywallSlug');
    final environmentSlug = request.str('environmentSlug');
    final organizationId = request.optInt('organizationId');
    return _withApi('publishing the paywall', (api) async {
      final version = await PaywallApi(api).publish(
        project: projectSlug,
        app: appSlug,
        paywall: paywallSlug,
        environment: environmentSlug,
        organizationId: organizationId,
      );
      return jsonResult(<String, Object?>{'version': version});
    });
  }

  /// Handle `restage_get_published_version` — the latest published version.
  Future<CallToolResult> _handleGetPublishedVersion(CallToolRequest request) {
    final projectSlug = request.str('projectSlug');
    final appSlug = request.str('appSlug');
    final paywallSlug = request.str('paywallSlug');
    final environmentSlug = request.str('environmentSlug');
    final organizationId = request.optInt('organizationId');
    return _withApi('reading the published version', (api) async {
      final version = await PaywallApi(api).getPublishedVersion(
        project: projectSlug,
        app: appSlug,
        paywall: paywallSlug,
        environment: environmentSlug,
        organizationId: organizationId,
      );
      return jsonResult(<String, Object?>{'version': version});
    });
  }

  /// Invoke a list-returning backend method and wrap its JSON array under
  /// [resultKey]. The backend's rows are passed through verbatim (no decoding)
  /// — they carry only non-secret resource metadata. Null-valued optional
  /// [args] are dropped before the call (a missing nullable parameter reads as
  /// `null` server-side).
  Future<CallToolResult> _listVia({
    required String endpoint,
    required String method,
    required String resultKey,
    required String action,
    Map<String, dynamic> args = const {},
  }) {
    return _withApi(action, (api) async {
      final raw = await api.call(endpoint, method, compactArgs(args));
      return jsonResult(<String, Object?>{resultKey: raw as List<dynamic>});
    });
  }

  /// Invoke a single-object-returning backend method and wrap the decoded JSON
  /// object under [resultKey]. Like [_listVia] but for endpoints that return one
  /// resource (e.g. an upserted slot, an updated app); same verbatim
  /// passthrough + null-arg compaction.
  Future<CallToolResult> _objectVia({
    required String endpoint,
    required String method,
    required String resultKey,
    required String action,
    Map<String, dynamic> args = const {},
  }) {
    return _withApi(action, (api) async {
      final raw = await api.call(endpoint, method, compactArgs(args));
      return jsonResult(<String, Object?>{resultKey: raw});
    });
  }

  /// Handle `restage_list_organizations` (no inputs).
  Future<CallToolResult> _handleListOrganizations(CallToolRequest request) =>
      _listVia(
        endpoint: 'organization',
        method: 'listMine',
        resultKey: 'organizations',
        action: 'listing organizations',
      );

  /// Handle `restage_list_projects` (organizationId).
  Future<CallToolResult> _handleListProjects(CallToolRequest request) {
    return _listVia(
      endpoint: 'project',
      method: 'listProjects',
      resultKey: 'projects',
      action: 'listing projects',
      args: {'organizationId': request.reqInt('organizationId')},
    );
  }

  /// Handle `restage_list_apps` (organizationId, projectSlug).
  Future<CallToolResult> _handleListApps(CallToolRequest request) {
    return _listVia(
      endpoint: 'app',
      method: 'listApps',
      resultKey: 'apps',
      action: 'listing apps',
      args: {
        'organizationId': request.reqInt('organizationId'),
        'projectSlug': request.str('projectSlug'),
      },
    );
  }

  /// Handle `restage_list_environments` (organizationId, projectSlug).
  Future<CallToolResult> _handleListEnvironments(CallToolRequest request) {
    return _listVia(
      endpoint: 'environment',
      method: 'listEnvironments',
      resultKey: 'environments',
      action: 'listing environments',
      args: {
        'organizationId': request.reqInt('organizationId'),
        'projectSlug': request.str('projectSlug'),
      },
    );
  }

  // ---- Products / store ----

  /// Handle `restage_list_products` (projectSlug, appSlug, optional store).
  Future<CallToolResult> _handleListProducts(CallToolRequest request) {
    return _listVia(
      endpoint: 'product',
      method: 'list',
      resultKey: 'products',
      action: 'listing products',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'store': request.optStr('store'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  /// Handle `restage_import_products` (projectSlug, appSlug, store).
  Future<CallToolResult> _handleImportProducts(CallToolRequest request) {
    return _listVia(
      endpoint: 'product',
      method: 'importProducts',
      resultKey: 'products',
      action: 'importing products',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'store': request.str('store'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  /// Handle `restage_list_product_slots` (projectSlug, appSlug).
  Future<CallToolResult> _handleListProductSlots(CallToolRequest request) {
    return _listVia(
      endpoint: 'productSlot',
      method: 'list',
      resultKey: 'productSlots',
      action: 'listing product slots',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  /// Handle `restage_upsert_product_slot` — full-replace create/update.
  ///
  /// `iosProductId` / `androidProductId` are required-but-nullable: a present
  /// string maps that store; a null (compacted out of the wire args) unmaps it.
  /// The schema's required set forces the agent to state both every call.
  Future<CallToolResult> _handleUpsertProductSlot(CallToolRequest request) {
    return _objectVia(
      endpoint: 'productSlot',
      method: 'upsert',
      resultKey: 'productSlot',
      action: 'saving the product slot',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'name': request.str('name'),
        'entitlement': request.str('entitlement'),
        'iosProductId': request.optStr('iosProductId'),
        'androidProductId': request.optStr('androidProductId'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  /// Handle `restage_list_store_connections` (projectSlug, appSlug).
  ///
  /// The backend returns summaries only — the credential bundle is write-only
  /// and has no field on the wire type — so the verbatim passthrough surfaces
  /// no secret material.
  Future<CallToolResult> _handleListStoreConnections(CallToolRequest request) {
    return _listVia(
      endpoint: 'storeConnection',
      method: 'list',
      resultKey: 'storeConnections',
      action: 'listing store connections',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  // ---- App configuration ----

  /// Handle `restage_get_app_config` — read an app's config via `listApps`.
  ///
  /// There is no single-app config getter; app config rides on the project's
  /// app list. Read it and filter to the requested slug.
  Future<CallToolResult> _handleGetAppConfig(CallToolRequest request) {
    final organizationId = request.reqInt('organizationId');
    final projectSlug = request.str('projectSlug');
    final appSlug = request.str('appSlug');
    return _withApi('reading the app configuration', (api) async {
      final raw = await api.call(
        'app',
        'listApps',
        compactArgs({
          'organizationId': organizationId,
          'projectSlug': projectSlug,
        }),
      );
      final apps = raw as List<dynamic>;
      Object? match;
      for (final app in apps) {
        if ((app as Map)['slug'] == appSlug) {
          match = app;
          break;
        }
      }
      if (match == null) {
        return mcpError(
          "No app '$appSlug' was found in project '$projectSlug'.",
        );
      }
      return jsonResult(<String, Object?>{'app': match});
    });
  }

  /// Handle `restage_update_app_config`. Omitted fields are compacted off the
  /// wire (the backend leaves them unchanged); an explicit empty string is
  /// forwarded verbatim (the backend clears that field).
  Future<CallToolResult> _handleUpdateAppConfig(CallToolRequest request) {
    return _objectVia(
      endpoint: 'app',
      method: 'updateAppConfiguration',
      resultKey: 'app',
      action: 'updating the app configuration',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'iosBundleId': request.optStr('iosBundleId'),
        'androidPackage': request.optStr('androidPackage'),
        'webDomain': request.optStr('webDomain'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  // ---- API keys ----

  /// Handle `restage_list_api_keys` (projectSlug, appSlug, environmentSlug).
  ///
  /// The backend returns redacted [ApiKeyView]s — never the key hash or
  /// plaintext — so the verbatim passthrough surfaces no secret material.
  Future<CallToolResult> _handleListApiKeys(CallToolRequest request) {
    return _listVia(
      endpoint: 'apiKey',
      method: 'listKeys',
      resultKey: 'apiKeys',
      action: 'listing API keys',
      args: {
        'projectSlug': request.str('projectSlug'),
        'appSlug': request.str('appSlug'),
        'environmentSlug': request.str('environmentSlug'),
        'organizationId': request.optInt('organizationId'),
      },
    );
  }

  /// Handle `restage_revoke_api_key` (projectSlug, appSlug, apiKeyId). The
  /// backend returns void; report a structured confirmation.
  Future<CallToolResult> _handleRevokeApiKey(CallToolRequest request) {
    final apiKeyId = request.reqInt('apiKeyId');
    return _withApi('revoking the API key', (api) async {
      await api.call(
        'apiKey',
        'revokeKey',
        compactArgs({
          'projectSlug': request.str('projectSlug'),
          'appSlug': request.str('appSlug'),
          'apiKeyId': apiKeyId,
          'organizationId': request.optInt('organizationId'),
        }),
      );
      return jsonResult(<String, Object?>{
        'revoked': true,
        'apiKeyId': apiKeyId,
      });
    });
  }

  // ---- Auth: device-code login + whoami + logout ----

  /// Handle `restage_login` — the stateful, idempotent device-code flow.
  ///
  /// One slot, last-start-wins: a valid in-flight attempt is polled; otherwise
  /// (no attempt, an expired attempt, or already signed in) it short-circuits
  /// or starts fresh. The device-code secret never leaves this process.
  Future<CallToolResult> _handleLogin(CallToolRequest request) {
    return guardErrors('signing in', () async {
      final pending = _pendingLogin;
      if (pending != null && _now().isBefore(pending.expiresAt)) {
        return _pollPendingLogin(pending);
      }
      _pendingLogin = null; // no attempt, or an expired one — start fresh.

      final existing = await _store.read();
      if (existing != null) {
        final email = await _signedInEmail(existing);
        if (email != null) {
          return jsonResult(<String, Object?>{
            'status': 'already_signed_in',
            'email': email,
            'message':
                'Already signed in as $email. Run restage_logout first to '
                'switch accounts.',
          });
        }
      }
      return _startLogin();
    });
  }

  /// Start a new device authorization, stash it, open the browser best-effort,
  /// and return the verification URL + user code (never the device code).
  Future<CallToolResult> _startLogin() {
    final endpoint = _resolveLoginEndpoint();
    return _withRawApi(
      endpoint,
      body: (api) async {
        final start = await AuthApi(api).startDeviceAuthorization();
        // Fail closed on a malformed authorization response BEFORE storing it,
        // opening the browser, or surfacing it. (1) The verification URL is
        // handed to the OS browser opener — reject anything but https / loopback
        // http so a buggy/hostile backend can't drive `open`/`xdg-open` to a
        // file:// or custom-scheme target. (2) Refuse if the (public) userCode
        // or verificationUri alias the (secret) deviceCode — a backend leaking
        // its own grant into a field we surface.
        final verificationUri = Uri.tryParse(start.verificationUri);
        if (verificationUri == null ||
            !isAcceptableTransport(verificationUri)) {
          return mcpError(
            'Sign-in could not start: the server returned an unsupported '
            'verification URL. Please try again.',
          );
        }
        if (start.deviceCode.isNotEmpty &&
            (start.userCode.contains(start.deviceCode) ||
                start.verificationUri.contains(start.deviceCode))) {
          return mcpError(
            'Sign-in could not start: the server returned a malformed '
            'authorization response. Please try again.',
          );
        }
        final pending = _PendingLogin(
          deviceCode: start.deviceCode,
          userCode: start.userCode,
          verificationUri: start.verificationUri,
          expiresAt: _now().add(Duration(seconds: start.expiresInSeconds)),
          pollIntervalSeconds: start.pollIntervalSeconds,
          endpoint: endpoint,
        );
        _pendingLogin = pending;
        await _openBrowserBestEffort(start.verificationUri);
        return _authorizationPendingResult(
          pending,
          leadMessage: 'Action required:',
        );
      },
    );
  }

  /// Poll an in-flight attempt up to the per-call budget, honoring the server's
  /// back-off. Persists the credential on success.
  Future<CallToolResult> _pollPendingLogin(_PendingLogin pending) {
    return _withRawApi(
      pending.endpoint,
      body: (api) async {
        final auth = AuthApi(api);
        final deadline = _now().add(_loginPollBudget);
        // Floor the interval at 1s so a hostile/buggy backend returning 0 (or a
        // negative) cannot turn the bounded poll into a tight loop that never
        // crosses the deadline (and hammers the backend).
        var interval = Duration(seconds: max(1, pending.pollIntervalSeconds));
        while (true) {
          // The whole grant has expired — give up and clear the attempt.
          if (!_now().isBefore(pending.expiresAt)) {
            _pendingLogin = null;
            return _expiredResult();
          }
          final result = await auth.exchangeDeviceCode(pending.deviceCode);
          switch (result.status) {
            case DeviceAuthorizationStatus.success:
              await _persistCredential(pending.endpoint, result);
              final deviceCode = pending.deviceCode;
              _pendingLogin = null;
              var email = result.userInfo?.email;
              // Defense-in-depth: never surface an email that aliases a secret
              // — the deviceCode the backend generated or the minted key — even
              // if a backend places it in the email field. Sign-in still
              // completes; only the aliased value is withheld.
              if (email != null &&
                  _emailAliasesSecret(email, deviceCode, result)) {
                email = null;
              }
              return jsonResult(<String, Object?>{
                'status': 'signed_in',
                'email': email,
                'message': email == null
                    ? 'Signed in.'
                    : 'Signed in as $email.',
              });
            case DeviceAuthorizationStatus.expired:
              _pendingLogin = null;
              return _expiredResult();
            case DeviceAuthorizationStatus.notFound:
              _pendingLogin = null;
              return jsonResult(<String, Object?>{
                'status': 'failed',
                'message':
                    'The sign-in attempt could not be completed. Call '
                    'restage_login again to start over.',
              });
            case DeviceAuthorizationStatus.pending:
              // Honour the server's back-off (RFC 8628 slow_down), floored at
              // 1s for the same forward-progress guarantee.
              if (result.pollIntervalSeconds != null) {
                interval = Duration(
                  seconds: max(1, result.pollIntervalSeconds!),
                );
              }
              // If the next poll would exceed our per-call budget, return and
              // KEEP the attempt so a re-call resumes the same grant.
              if (!_now().add(interval).isBefore(deadline)) {
                return _authorizationPendingResult(
                  pending,
                  leadMessage: 'Still waiting for approval.',
                );
              }
              await _sleep(interval);
          }
        }
      },
    );
  }

  /// Quietly resolve the signed-in email, or null when the stored credential is
  /// missing/stale/unreachable (so login proceeds to a fresh sign-in).
  Future<String?> _signedInEmail(Credential credential) async {
    try {
      return await _withRawApi(
        Uri.parse(credential.endpoint),
        credential: credential,
        body: (api) async => (await AuthApi(api).whoami())?.email,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _persistCredential(
    Uri endpoint,
    DeviceAuthorizationResult result,
  ) async {
    final keyId = result.keyId;
    final key = result.key;
    if (keyId == null || key == null) {
      throw StateError('Backend reported success without a credential.');
    }
    await _store.write(
      Credential(
        endpoint: endpoint.toString(),
        kind: CredentialKind.authKey,
        authToken: '$keyId:$key',
      ),
    );
  }

  /// Whether [email] contains a secret a backend should never place there: the
  /// [deviceCode] it generated, the minted key, or the `keyId:key` token.
  /// Containment (not equality) so an aliased value embedded in a larger string
  /// is still caught.
  static bool _emailAliasesSecret(
    String email,
    String deviceCode,
    DeviceAuthorizationResult result,
  ) {
    if (deviceCode.isNotEmpty && email.contains(deviceCode)) return true;
    final key = result.key;
    if (key != null && key.isNotEmpty && email.contains(key)) return true;
    final keyId = result.keyId;
    if (keyId != null && key != null && email.contains('$keyId:$key')) {
      return true;
    }
    return false;
  }

  /// Build an authorization-pending result re-surfacing the (non-secret)
  /// verification URL + user code and the call-again instruction.
  CallToolResult _authorizationPendingResult(
    _PendingLogin pending, {
    required String leadMessage,
  }) {
    return jsonResult(<String, Object?>{
      'status': 'authorization_pending',
      'verificationUri': pending.verificationUri,
      'userCode': pending.userCode,
      'message':
          '$leadMessage open ${pending.verificationUri}, enter code '
          '${pending.userCode}, and approve in your browser. THEN call '
          'restage_login again to complete sign-in.',
    });
  }

  CallToolResult _expiredResult() => jsonResult(<String, Object?>{
    'status': 'expired',
    'message':
        'The sign-in attempt expired before it was approved. Call '
        'restage_login again to start over.',
  });

  /// Open [url] best-effort; a failure is non-fatal (the URL is in the result).
  Future<void> _openBrowserBestEffort(String url) async {
    try {
      await _openBrowser(url);
    } on Object {
      // Best-effort: the verification URL is already in the response.
    }
  }

  Uri _resolveLoginEndpoint() {
    final injected = _loginEndpoint;
    if (injected != null) return injected;
    final env = Platform.environment['RESTAGE_BACKEND_URL'];
    if (env != null && env.isNotEmpty) return Uri.parse(env);
    return Uri.parse(_defaultLoginEndpoint);
  }

  /// Handle `restage_whoami`.
  Future<CallToolResult> _handleWhoami(CallToolRequest request) {
    return guardErrors('checking the session', () async {
      final credential = await _store.read();
      if (credential == null) {
        return jsonResult(<String, Object?>{'signedIn': false});
      }
      return _withRawApi(
        Uri.parse(credential.endpoint),
        credential: credential,
        body: (api) async {
          final user = await AuthApi(api).whoami();
          return user == null
              ? jsonResult(<String, Object?>{'signedIn': false})
              : jsonResult(<String, Object?>{
                  'signedIn': true,
                  'id': user.id,
                  'email': user.email,
                });
        },
      );
    });
  }

  /// Handle `restage_logout` — best-effort server revoke, always remove local.
  Future<CallToolResult> _handleLogout(CallToolRequest request) {
    return guardErrors('signing out', () async {
      final credential = await _store.read();
      if (credential == null) {
        return jsonResult(<String, Object?>{'signedOut': true});
      }
      try {
        await _withRawApi(
          Uri.parse(credential.endpoint),
          credential: credential,
          body: (api) async {
            try {
              await AuthApi(api).logout();
            } on RestageApiException {
              // Server revoke failed; remove the local credential anyway.
            }
          },
        );
      } on InsecureEndpointException {
        // Never send the credential to an insecure endpoint; still remove it
        // locally so the user is not stranded.
      }
      await _store.delete();
      return jsonResult(<String, Object?>{'signedOut': true});
    });
  }
}

/// An in-flight device-authorization attempt. The [deviceCode] is the pre-auth
/// grant secret and is held only here — never returned to the client.
class _PendingLogin {
  _PendingLogin({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.pollIntervalSeconds,
    required this.endpoint,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final DateTime expiresAt;
  final int pollIntervalSeconds;
  final Uri endpoint;
}

/// Default poll delay — a real wait in production.
Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

/// Default browser opener — best-effort `open` / `xdg-open` / `start`.
Future<void> _defaultOpenBrowser(String url) async {
  final String executable;
  final List<String> args;
  if (Platform.isMacOS) {
    executable = 'open';
    args = <String>[url];
  } else if (Platform.isWindows) {
    executable = 'cmd';
    args = <String>['/c', 'start', '', url];
  } else {
    executable = 'xdg-open';
    args = <String>[url];
  }
  try {
    await Process.run(executable, args);
  } on ProcessException {
    // Best-effort; the caller surfaces the URL regardless.
  }
}

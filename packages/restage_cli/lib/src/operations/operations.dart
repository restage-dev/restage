import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/app_admin_api.dart';
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/audit_rendering.dart';
import 'package:restage_cli/src/commands/render_bundle_coverage.dart';
import 'package:restage_cli/src/operations/operation.dart';

/// Store vendors the product operations accept.
const storeVendorWireNames = <String>['appStore', 'playStore'];

/// The CLI value that unmaps a store from a slot.
const unmappedProductId = 'none';

/// Every operation the CLI and the MCP server share, in CLI order.
@experimental
final List<Operation> sharedOperations = [
  Operation(
    cliPath: 'orgs',
    mcpName: 'restage_list_organizations',
    description: 'List the organizations the signed-in account belongs to.',
    mcpDescription:
        'List the organizations the signed-in account belongs to. Returns '
        "each organization's id, slug, name, and your role. Use an "
        'organizationId to address its projects, apps, and environments.',
    scope: OperationScope.account,
    resultKey: 'organizations',
    columns: const [
      (header: 'ID', key: 'organizationId'),
      (header: 'SLUG', key: 'slug'),
      (header: 'NAME', key: 'name'),
      (header: 'ROLE', key: 'role'),
    ],
    call: (target, _) async => [
      for (final organization in await DiscoveryApi(
        target.api,
      ).listOrganizations())
        organization.toJson(),
    ],
  ),
  Operation(
    cliPath: 'org rename',
    mcpName: 'restage_rename_organization',
    description: 'Rename an organization. Its slug stays.',
    mcpDescription:
        'Rename an organization. Admins only. The slug, and every link and '
        'key using it, stay the same.',
    scope: OperationScope.organization,
    params: const [
      OperationParam(
        'name',
        cli: 'new name <name>',
        positional: true,
        required: true,
        help: 'The new organization name.',
      ),
    ],
    render: (out, _, args, _) =>
        out.writeln('Renamed the organization to ${args.str('name')}.'),
    call: (target, args) async {
      final organizationId = await target.organization();
      await target.api.call('organization', 'rename', {
        'organizationId': organizationId,
        'name': args.str('name'),
      });
      return <String, Object?>{
        'organizationId': organizationId,
        'name': args.str('name'),
      };
    },
  ),
  Operation(
    cliPath: 'projects',
    mcpName: 'restage_list_projects',
    description: 'List projects available to the signed-in account.',
    mcpDescription: 'List the projects under an organization.',
    scope: OperationScope.organization,
    resultKey: 'projects',
    columns: const [
      (header: 'SLUG', key: 'slug'),
      (header: 'NAME', key: 'name'),
    ],
    call: (target, _) async => _rows(target.api, 'project', 'listProjects', {
      'organizationId': await target.organization(),
    }),
  ),
  Operation(
    cliPath: 'apps',
    mcpName: 'restage_list_apps',
    description: 'List apps in a project.',
    mcpDescription: 'List the apps under a project in an organization.',
    scope: OperationScope.project,
    resultKey: 'apps',
    columns: const [
      (header: 'SLUG', key: 'slug'),
      (header: 'NAME', key: 'name'),
    ],
    call: (target, _) async => _rows(target.api, 'app', 'listApps', {
      'organizationId': await target.organization(),
      'projectSlug': target.project,
    }),
  ),
  Operation(
    cliPath: 'envs',
    mcpName: 'restage_list_environments',
    description: 'List environments in a project.',
    mcpDescription:
        'List the environments under a project in an organization '
        '(e.g. dev, staging, production).',
    scope: OperationScope.project,
    resultKey: 'environments',
    columns: const [(header: 'SLUG', key: 'slug')],
    call: (target, _) async =>
        _rows(target.api, 'environment', 'listEnvironments', {
          'organizationId': await target.organization(),
          'projectSlug': target.project,
        }),
  ),
  Operation(
    cliPath: 'targets',
    mcpName: 'restage_list_environment_targets',
    description: 'List environment targets in an app.',
    mcpDescription:
        'List the existing environment targets under one app, optionally '
        'filtered by runtime plane.',
    scope: OperationScope.app,
    params: [
      OperationParam(
        'runtimePlane',
        cli: 'plane',
        allowed: [for (final plane in RuntimePlane.values) plane.wireName],
        help: 'Runtime plane: sandbox or live.',
      ),
      const OperationParam(
        'appId',
        type: ParamType.integer,
        mcpOnly: true,
        help: 'The active numeric App id.',
      ),
    ],
    resultKey: 'environmentTargets',
    columns: const [
      (header: 'ID', key: 'environmentTargetId'),
      (header: 'ENVIRONMENT', key: 'environmentSlug'),
      (header: 'PLANE', key: 'runtimePlane'),
    ],
    call: (target, args) async {
      final rows =
          await _rows(target.api, 'environment', 'listEnvironmentTargets', {
            'organizationId': await target.organization(),
            'projectSlug': target.project,
            'appSlug': target.app,
            'appId': ?(args.optInt('appId') ?? target.appId),
            'runtimePlane': ?args.optStr('runtimePlane'),
          });
      return rows..sort(
        (left, right) => (left['environmentTargetId']! as int).compareTo(
          right['environmentTargetId']! as int,
        ),
      );
    },
  ),
  Operation(
    cliPath: 'app rename',
    mcpName: 'restage_rename_app',
    description: 'Rename an app. Its slug stays.',
    mcpDescription:
        'Rename an app. Admins only. The slug, and the SDK configuration and '
        'keys using it, stay the same. Returns the app.',
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'name',
        cli: 'new name <name>',
        positional: true,
        required: true,
        help: 'The new app name.',
      ),
    ],
    render: (out, _, args, _) =>
        out.writeln('Renamed the app to ${args.str('name')}.'),
    resultKey: 'app',
    columns: _appConfigColumns,
    call: (target, args) => AppAdminApi(target.api).renameApp(
      project: target.project!,
      app: target.app!,
      name: args.str('name'),
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'app-config show',
    mcpName: 'restage_get_app_config',
    description: "Show an app's platform configuration.",
    mcpDescription:
        "Get an app's platform configuration: its iOS bundle id, Android "
        'package name, and web domain (plus id, slug, and name).',
    scope: OperationScope.app,
    resultKey: 'app',
    columns: _appConfigColumns,
    call: (target, _) async {
      final row = await AppAdminApi(target.api).readAppConfig(
        organizationId: target.organizationId,
        project: target.project!,
        app: target.app!,
      );
      if (row == null) {
        throw TargetSelectionException(
          appNotFoundSentence(target.app!, target.project!),
        );
      }
      return row;
    },
  ),
  Operation(
    cliPath: 'app-config set',
    mcpName: 'restage_update_app_config',
    description:
        "Change an app's platform configuration (admin). Options left out "
        'stay unchanged.',
    mcpDescription:
        "Update an app's platform configuration. Requires an admin role. "
        'Each field is independent: OMIT a field to leave it unchanged; pass '
        'an EMPTY STRING to clear it. Returns the updated app.',
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'iosBundleId',
        cli: 'ios-bundle-id',
        help: 'New iOS bundle id. Pass an empty value to clear it.',
        mcpHelp:
            'New iOS bundle id. Omit to leave unchanged; empty string to '
            'clear.',
      ),
      OperationParam(
        'androidPackage',
        cli: 'android-package',
        help: 'New Android package name. Pass an empty value to clear it.',
        mcpHelp:
            'New Android package name. Omit to leave unchanged; empty string '
            'to clear.',
      ),
      OperationParam(
        'webDomain',
        cli: 'web-domain',
        help: 'New web domain. Pass an empty value to clear it.',
        mcpHelp:
            'New web domain. Omit to leave unchanged; empty string to clear.',
      ),
    ],
    validate: (args, name) =>
        args.optStr('iosBundleId') == null &&
            args.optStr('androidPackage') == null &&
            args.optStr('webDomain') == null
        ? 'Nothing to change. Pass ${name('iosBundleId')}, '
              '${name('androidPackage')}, or ${name('webDomain')}.'
        : null,
    resultKey: 'app',
    columns: _appConfigColumns,
    call: (target, args) => AppAdminApi(target.api).updateAppConfig(
      project: target.project!,
      app: target.app!,
      iosBundleId: args.optStr('iosBundleId'),
      androidPackage: args.optStr('androidPackage'),
      webDomain: args.optStr('webDomain'),
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'products list',
    mcpName: 'restage_list_products',
    description: 'List the store products imported for an app.',
    mcpDescription:
        'List the store products (SKUs) imported for an app, optionally '
        'filtered to one store. Each product carries its store, store '
        'product id, display name, price, and the product slot it is mapped '
        'to (if any).',
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'store',
        cli: 'store',
        allowed: storeVendorWireNames,
        help: 'Only this store. Lists both when left out.',
        mcpHelp:
            'Optional store filter: "appStore" (Apple) or "playStore" '
            '(Google). Omit to list both stores.',
      ),
    ],
    resultKey: 'products',
    columns: _productColumns,
    call: (target, args) => AppAdminApi(target.api).listProducts(
      project: target.project!,
      app: target.app!,
      store: args.optStr('store'),
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'products import',
    mcpName: 'restage_import_products',
    description:
        "Re-fetch a store's catalog and update the app's products (admin).",
    mcpDescription:
        "Re-fetch a store's product catalog and upsert each entry as a "
        'product, refreshing prices and display names. Requires a verified '
        'store connection for that store and an admin role. Returns the '
        'upserted products.',
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'store',
        cli: 'store',
        required: true,
        allowed: storeVendorWireNames,
        help: 'Which store catalog to import (required).',
        mcpHelp:
            'Which store catalog to import: "appStore" (Apple) or '
            '"playStore" (Google).',
      ),
    ],
    resultKey: 'products',
    columns: _productColumns,
    call: (target, args) => AppAdminApi(target.api).importProducts(
      project: target.project!,
      app: target.app!,
      store: args.str('store'),
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'slots list',
    mcpName: 'restage_list_product_slots',
    description: "List an app's product slots.",
    mcpDescription:
        'List the product slots for an app. A slot is the paywall-facing '
        'handle for an entitlement; it owns the entitlement string that '
        'purchasing a mapped product grants. (To see which store products '
        'map to which slot, list products and read each product\'s product '
        'slot.)',
    scope: OperationScope.app,
    resultKey: 'productSlots',
    columns: _slotColumns,
    call: (target, _) => AppAdminApi(target.api).listProductSlots(
      project: target.project!,
      app: target.app!,
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'slots set',
    mcpName: 'restage_upsert_product_slot',
    description:
        'Create or replace a slot and its complete product mapping (admin).',
    mcpDescription:
        'Create or update a product slot and its store-product mapping. '
        "Requires an admin role. WARNING — this sets the slot's COMPLETE "
        'product mapping (full replace): any store id you omit or pass as '
        'null is UNMAPPED from this slot. To keep an existing mapping you '
        'MUST pass its current product id — call restage_list_product_slots '
        'and restage_list_products first to read the current mappings.',
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'name',
        cli: 'slot <name>',
        positional: true,
        required: true,
        help: 'The slot name (the handle a paywall references).',
      ),
      OperationParam(
        'entitlement',
        cli: 'entitlement',
        required: true,
        help: 'Entitlement that buying a mapped product grants (required).',
        mcpHelp: 'The entitlement string purchasing a mapped product grants.',
      ),
      OperationParam(
        'iosProductId',
        cli: 'ios-product-id',
        type: ParamType.clearable,
        required: true,
        help:
            'App Store product id for this slot, or `$unmappedProductId` to '
            'unmap it (required).',
        mcpHelp:
            'The App Store (iOS) store product id to map to this slot, or '
            'null to UNMAP App Store (iOS) from it. Required every call (full '
            'replace): pass the CURRENT id to keep an existing mapping.',
      ),
      OperationParam(
        'androidProductId',
        cli: 'android-product-id',
        type: ParamType.clearable,
        required: true,
        help:
            'Play Store product id for this slot, or `$unmappedProductId` to '
            'unmap it (required).',
        mcpHelp:
            'The Play Store (Android) store product id to map to this slot, '
            'or null to UNMAP Play Store (Android) from it. Required every '
            'call (full replace): pass the CURRENT id to keep an existing '
            'mapping.',
      ),
    ],
    validate: (args, name) =>
        args.has('entitlement') &&
            args.has('iosProductId') &&
            args.has('androidProductId')
        ? null
        : 'Required: ${name('entitlement')}, ${name('iosProductId')} and '
              '${name('androidProductId')}. The mapping is replaced whole; '
              'pass `$unmappedProductId` to unmap a store.',
    resultKey: 'productSlot',
    columns: _slotColumns,
    call: (target, args) => AppAdminApi(target.api).upsertProductSlot(
      project: target.project!,
      app: target.app!,
      name: args.str('name'),
      entitlement: args.str('entitlement'),
      iosProductId: args.optStr('iosProductId'),
      androidProductId: args.optStr('androidProductId'),
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'stores list',
    mcpName: 'restage_list_store_connections',
    description:
        "List an app's store connections. Credentials are never shown.",
    mcpDescription:
        'List the store connections configured for an app (one per store). '
        'Returns non-secret connection metadata only — store, status, the '
        'store app identifier, a short credential fingerprint, the RTDN '
        'topic, and timestamps. The stored credential bundle is never '
        'returned.',
    scope: OperationScope.app,
    resultKey: 'storeConnections',
    columns: const [
      (header: 'STORE', key: 'store'),
      (header: 'STATUS', key: 'status'),
      (header: 'APP IDENTIFIER', key: 'storeAppIdentifier'),
      (header: 'FINGERPRINT', key: 'credentialFingerprint'),
      (header: 'LAST VERIFIED', key: 'lastVerifiedAt'),
    ],
    call: (target, _) => AppAdminApi(target.api).listStoreConnections(
      project: target.project!,
      app: target.app!,
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'keys list',
    mcpName: 'restage_list_api_keys',
    description:
        "List an environment's active API keys. Only a short prefix of each "
        'key is shown.',
    mcpDescription:
        'List the active API keys for an app environment. Returns redacted '
        'views only — id, kind, a short key prefix, and lifecycle '
        'timestamps. The key hash and plaintext are never returned. Keys are '
        'created in the dashboard.',
    scope: OperationScope.target,
    resultKey: 'apiKeys',
    columns: const [
      (header: 'ID', key: 'id'),
      (header: 'KIND', key: 'kind'),
      (header: 'PREFIX', key: 'keyPrefix'),
      (header: 'CREATED', key: 'createdAt'),
      (header: 'LAST USED', key: 'lastUsedAt'),
    ],
    call: (target, _) => AppAdminApi(target.api).listApiKeys(
      project: target.project!,
      app: target.app!,
      environment: target.environment!,
      environmentTargetId: target.environmentTargetId,
      runtimePlane: target.runtimePlane,
      organizationId: target.organizationId,
    ),
  ),
  Operation(
    cliPath: 'keys revoke',
    mcpName: 'restage_revoke_api_key',
    description:
        'Revoke an API key by id (admin). Revoking a revoked key changes '
        'nothing.',
    mcpDescription:
        'Revoke an API key by its id (from restage_list_api_keys). Requires '
        'an admin role. Idempotent — revoking an already-revoked key is a '
        'no-op.',
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'apiKeyId',
        cli: 'numeric key <id>',
        type: ParamType.integer,
        positional: true,
        required: true,
        help: 'The id of the key to revoke (from list_api_keys).',
      ),
    ],
    render: (out, _, args, _) =>
        out.writeln('Revoked key ${args.integer('apiKeyId')}.'),
    call: (target, args) async {
      final id = args.integer('apiKeyId');
      await AppAdminApi(target.api).revokeApiKey(
        project: target.project!,
        app: target.app!,
        apiKeyId: id,
        organizationId: target.organizationId,
      );
      return <String, Object?>{'revoked': true, 'apiKeyId': id};
    },
  ),
  Operation(
    cliPath: 'app delete',
    mcpName: 'restage_delete_app',
    description:
        "Delete an app nothing uses (admin). --name must be the app's name.",
    mcpDescription:
        'Delete an app nothing uses. Refused while it has serving surfaces, '
        'active API keys, running experiments or delivery rules. Requires '
        "the app's exact name.",
    scope: OperationScope.app,
    params: const [
      OperationParam(
        'name',
        cli: 'name',
        required: true,
        help: "The app's name, exactly as it is shown.",
      ),
    ],
    render: (out, _, _, target) => out.writeln('Deleted app ${target.app}.'),
    call: (target, args) async {
      await AppAdminApi(target.api).deleteApp(
        project: target.project!,
        app: target.app!,
        name: args.str('name'),
        organizationId: target.organizationId,
      );
      return <String, Object?>{'deleted': true, 'app': target.app};
    },
  ),
  Operation(
    cliPath: 'keys resolve',
    mcpName: 'restage_resolve_api_key',
    description:
        'Find the organization, project, app, environment and plane an API '
        'key belongs to. The key is matched here against key prefixes and '
        'never sent.',
    mcpDescription:
        'Find the organization, project, app, environment and runtime plane '
        'an API key belongs to, such as the rs_pk_ publishable key an app is '
        'configured with. The key is matched locally against the short '
        "prefixes of your organizations' active keys: it is never sent to "
        'the server, and only the matching prefix is returned. Pass the key '
        'or its leading part. Use the result as organizationId, projectSlug, '
        'appSlug, environmentSlug and runtimePlane to push and publish to '
        'the environment that key serves.',
    scope: OperationScope.account,
    params: const [
      OperationParam(
        'key',
        cli: 'key <value>',
        positional: true,
        required: true,
        help: 'The API key, or its leading part.',
      ),
      OperationParam(
        'organizationId',
        type: ParamType.integer,
        mcpOnly: true,
        help: 'Only search this organization.',
      ),
      OperationParam(
        'organization',
        cli: 'organization',
        cliOnly: true,
        help: 'Only search the organization with this slug.',
      ),
    ],
    validate: (args, _) => (args.optStr('key') ?? '').startsWith('rs_')
        ? null
        : 'Expected a Restage API key, starting with rs_pk_ or rs_sk_.',
    resultKey: 'matches',
    columns: const [
      (header: 'ORGANIZATION', key: 'organizationSlug'),
      (header: 'PROJECT', key: 'projectSlug'),
      (header: 'APP', key: 'appSlug'),
      (header: 'ENVIRONMENT', key: 'environmentSlug'),
      (header: 'PLANE', key: 'runtimePlane'),
      (header: 'TARGET', key: 'environmentTargetId'),
      (header: 'KEY', key: 'keyPrefix'),
    ],
    call: (target, args) => resolveApiKey(
      target.api,
      args.str('key'),
      organizationId: args.optInt('organizationId'),
      organizationSlug: args.optStr('organization'),
    ),
  ),
  Operation(
    cliPath: 'audit log',
    mcpName: 'restage_audit_log',
    description: 'Show the organization server audit log.',
    mcpDescription:
        "The organization's server audit log, newest first, the same as "
        '`restage audit log`: each row with its action, target, actor, '
        'outcome and reason. An experiment row carries `targetName`, the '
        "experiment's current name, absent once the experiment is gone. "
        'Each row carries `chain`: pending (not yet in the tamper-evident '
        'chain), chained (in the chain; the periodic verification has not '
        'reached it yet), or verified. restage_audit_verdict says whether '
        'the chain as a whole verifies.',
    scope: OperationScope.organization,
    resultKey: 'events',
    toJson: _auditRowsJson,
    render: (out, value, _, _) =>
        writeAuditLogTable(out, value! as List<SurfaceAuditLogEntry>),
    call: (target, _) async => SurfaceApi(
      target.api,
    ).listAuditLog(organizationId: await target.organization()),
  ),
  Operation(
    cliPath: 'audit export',
    mcpName: 'restage_audit_export',
    description: 'Export compliance audit rows as CSV.',
    mcpDescription:
        "The organization's compliance audit export, the same as `restage "
        'audit export`, as rows.',
    scope: OperationScope.organization,
    resultKey: 'rows',
    toJson: (value) => [
      for (final row in value! as List<SurfaceComplianceExportRow>)
        row.toJson(),
    ],
    render: (out, value, _, _) => writeComplianceExportCsv(
      out,
      value! as List<SurfaceComplianceExportRow>,
    ),
    call: (target, _) async => SurfaceApi(
      target.api,
    ).exportComplianceAudit(organizationId: await target.organization()),
  ),
  Operation(
    cliPath: 'audit verdict',
    mcpName: 'restage_audit_verdict',
    description: 'Show the surface audit chain verdict.',
    mcpDescription:
        "The verdict on the organization's surface audit chain, the same as "
        '`restage audit verdict`: whether every row verifies, and where it '
        'breaks when one does not.',
    scope: OperationScope.organization,
    toJson: (value) => (value! as SurfaceChainVerdictResult).toJson(),
    render: (out, value, _, _) =>
        writeVerdictText(out, value! as SurfaceChainVerdictResult),
    call: (target, _) async => SurfaceApi(
      target.api,
    ).surfaceChainVerdict(organizationId: await target.organization()),
  ),
  Operation(
    cliPath: 'surface audit',
    mcpName: 'restage_surface_audit',
    description:
        "Show one surface's audit timeline in an environment: pushes, "
        'publishes, rollbacks, kills, and freezes, newest first.',
    mcpDescription:
        'The audit timeline for one surface in an environment: pushes, '
        'publishes, rollbacks, kills, and freezes, newest first, each with '
        'its actor, outcome, and reason. '
        'Each row carries `chain`: pending (not yet in the tamper-evident '
        'chain), chained (in the chain; the periodic verification has not '
        'reached it yet), or verified. restage_audit_verdict says whether '
        'the chain as a whole verifies.',
    scope: OperationScope.target,
    surface: true,
    readsSurface: true,
    params: const [
      OperationParam(
        'contractVersion',
        cli: 'contract-version',
        type: ParamType.integer,
        help:
            'Positive standalone-screen contract version. Omit for the '
            'non-versioned flow or paywall lineage.',
      ),
    ],
    resultKey: 'events',
    toJson: _auditRowsJson,
    render: (out, value, _, _) =>
        writeAuditLogTable(out, value! as List<SurfaceAuditLogEntry>),
    call: (target, args) => SurfaceApi(target.api).listSurfaceHistory(
      project: target.project!,
      app: target.app!,
      surfaceType: target.identity!.surface,
      surfaceSlug: target.identity!.slug,
      environment: target.environment!,
      environmentTargetId: target.environmentTargetId,
      runtimePlane: target.runtimePlane,
      organizationId: target.organizationId,
      contractVersion: args.optInt('contractVersion'),
    ),
  ),
  Operation(
    cliPath: 'surface draft pull',
    mcpName: 'restage_pull_surface_draft',
    description: "Download a surface's saved draft, for backup or inspection.",
    mcpDescription:
        "Download a surface's saved dashboard draft as base64, for backup or "
        'inspection. The draft is compiled binary and not editable here.',
    scope: OperationScope.app,
    surface: true,
    readsSurface: true,
    params: const [
      OperationParam(
        'out',
        cli: 'out',
        cliOnly: true,
        help:
            'Write the draft bytes to this file. Prints base64 when left out.',
      ),
    ],
    render: (out, value, args, _) async {
      final draft = value! as Map<String, Object?>;
      final encoded = draft['draftBase64']! as String;
      final path = args.optStr('out');
      if (path == null) {
        out.writeln(encoded);
        return;
      }
      await File(path).writeAsBytes(base64Decode(encoded));
      out.writeln('Wrote ${draft['byteLength']} bytes to $path.');
    },
    call: (target, _) async {
      final bytes = await SurfaceApi(target.api).load(
        project: target.project!,
        app: target.app!,
        surfaceType: target.identity!.surface,
        surfaceSlug: target.identity!.slug,
        organizationId: target.organizationId,
        appId: target.appId,
      );
      return <String, Object?>{
        'surfaceSlug': target.identity!.slug,
        'byteLength': bytes.length,
        'draftBase64': base64Encode(bytes),
      };
    },
  ),
  Operation(
    cliPath: 'surface draft push',
    mcpName: 'restage_push_surface_draft',
    description:
        "Push a surface's saved draft to an environment as a new revision "
        '(admin). It is not live until published.',
    mcpDescription:
        "Push a surface's saved dashboard draft to an environment as a new "
        'revision, the same as `restage surface draft push`. Returns the '
        'revision. It is not live until restage_publish_surface publishes '
        'it. Requires an admin role.',
    scope: OperationScope.target,
    surface: true,
    render: (out, value, _, target) {
      final pushed = value! as Map<String, Object?>;
      final slug = target.identity!.slug;
      final revision = pushed['revision'];
      final publish = target.syntax.command(
        FollowUp('surface publish', 'restage_publish_surface', [
          FollowUpArg('surfaceSlug', slug),
          FollowUpArg(
            'surfaceType',
            target.identity!.surface.wireName,
            flag: 'type',
          ),
          FollowUpArg('revision', '$revision', flag: 'revision'),
          ...planeArgs(target.runtimePlane!, implicit: target.planeIsImplicit),
        ]),
      );
      out.writeln(
        'Pushed the draft of "$slug" to ${target.environment} as r$revision. '
        'Not live yet. ${target.syntax.run} $publish to publish it.',
      );
      if (pushed['buildNotice'] case final String notice) out.writeln(notice);
    },
    call: (target, _) async {
      final identity = target.identity!;
      final revision = await SurfaceApi(target.api).publish(
        project: target.project!,
        app: target.app!,
        surfaceType: identity.surface,
        surfaceSlug: identity.slug,
        environment: target.environment!,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
      );
      final notice = await draftCoverageNotice(
        api: target.api,
        project: target.project!,
        app: target.app!,
        surfaceType: identity.surface,
        surfaceSlug: identity.slug,
        environment: target.environment!,
        environmentTargetId: target.environmentTargetId,
        runtimePlane: target.runtimePlane,
        organizationId: target.organizationId,
      );
      return <String, Object?>{'revision': revision, 'buildNotice': ?notice};
    },
  ),
];

/// The active keys whose prefix matches [key], each with the organization,
/// project, app and environment target it belongs to. [key] never leaves
/// this process.
@visibleForTesting
Future<List<Map<String, Object?>>> resolveApiKey(
  RestageApi api,
  String key, {
  int? organizationId,
  String? organizationSlug,
}) async {
  final discovery = DiscoveryApi(api);
  final admin = AppAdminApi(api);
  final plane = RegExp(r'^rs_(?:pk|sk)_(sandbox|live)_').firstMatch(key);
  final runtimePlane = plane == null
      ? null
      : RuntimePlane.fromWireName(plane.group(1)!);
  final organizations = [
    for (final organization in await discovery.listOrganizations())
      if ((organizationId == null ||
              organization.organizationId == organizationId) &&
          (organizationSlug == null || organization.slug == organizationSlug))
        organization,
  ];
  if (organizations.isEmpty) {
    throw const TargetSelectionException('No organization of yours matches.');
  }
  final matches = <Map<String, Object?>>[];
  for (final organization in organizations) {
    final id = organization.organizationId;
    for (final project in await discovery.listProjects(id)) {
      final apps = await discovery.listApps(
        organizationId: id,
        projectSlug: project.slug,
      );
      for (final app in apps) {
        final targets = await discovery.listEnvironmentTargets(
          organizationId: id,
          projectSlug: project.slug,
          appSlug: app.slug,
          appId: app.appId,
          runtimePlane: runtimePlane,
        );
        for (final environment in targets) {
          final keys = await admin.listApiKeys(
            project: project.slug,
            app: app.slug,
            environment: environment.environmentSlug,
            environmentTargetId: environment.environmentTargetId,
            runtimePlane: environment.runtimePlane,
            organizationId: id,
          );
          for (final row in keys) {
            final prefix = row['keyPrefix'] as String? ?? '';
            final stem = prefix.endsWith('...')
                ? prefix.substring(0, prefix.length - 3)
                : prefix;
            if (stem.isEmpty ||
                !(key.startsWith(stem) || stem.startsWith(key))) {
              continue;
            }
            matches.add({
              'organizationId': id,
              'organizationSlug': organization.slug,
              'projectSlug': project.slug,
              'appSlug': app.slug,
              'appId': app.appId,
              'environmentSlug': environment.environmentSlug,
              'runtimePlane': environment.runtimePlane.wireName,
              'environmentTargetId': environment.environmentTargetId,
              'apiKeyId': row['id'],
              'kind': row['kind'],
              'keyPrefix': prefix,
            });
          }
        }
      }
    }
  }
  if (matches.isEmpty) {
    throw TargetSelectionException(
      'No active API key in ${organizations.map((o) => o.slug).join(', ')} '
      'matches that key. A revoked key does not match.',
    );
  }
  return matches;
}

/// The shared operation [mcpName] names.
@experimental
Operation sharedOperation(String mcpName) =>
    sharedOperations.singleWhere((operation) => operation.mcpName == mcpName);

Object? _auditRowsJson(Object? value) => [
  for (final row in value! as List<SurfaceAuditLogEntry>) row.toJson(),
];

const _appConfigColumns = <OperationColumn>[
  (header: 'ID', key: 'id'),
  (header: 'SLUG', key: 'slug'),
  (header: 'NAME', key: 'name'),
  (header: 'IOS BUNDLE ID', key: 'iosBundleId'),
  (header: 'ANDROID PACKAGE', key: 'androidPackage'),
  (header: 'WEB DOMAIN', key: 'webDomain'),
];

const _productColumns = <OperationColumn>[
  (header: 'STORE', key: 'store'),
  (header: 'PRODUCT ID', key: 'storeProductId'),
  (header: 'NAME', key: 'displayName'),
  (header: 'PRICE', key: 'priceMicros'),
  (header: 'CURRENCY', key: 'currency'),
  (header: 'SLOT', key: 'productSlotId'),
];

const _slotColumns = <OperationColumn>[
  (header: 'ID', key: 'id'),
  (header: 'NAME', key: 'name'),
  (header: 'ENTITLEMENT', key: 'entitlement'),
];

Future<List<Map<String, Object?>>> _rows(
  RestageApi api,
  String endpoint,
  String method,
  Map<String, dynamic> args,
) async {
  final raw = await api.call(endpoint, method, args);
  return [
    for (final row in raw as List<dynamic>)
      (row! as Map).cast<String, Object?>(),
  ];
}

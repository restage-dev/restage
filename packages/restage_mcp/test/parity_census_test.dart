import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:restage_cli/src/tui/console_models.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Every CLI command and the MCP tools that do the same thing: the shared
/// operation table, plus the commands implemented on each side.
final _cliToMcp = <String, Set<String>>{
  for (final operation in sharedOperations)
    operation.cliPath: {operation.mcpName},
  for (final operation in deliveryOperations.values)
    operation.cliPath: {operation.mcpName},
  'login': {'restage_login'},
  'logout': {'restage_logout'},
  'whoami': {'restage_whoami'},
  'status': {'restage_status'},
  'init': {'restage_init'},
  'doctor': {'restage_doctor'},
  'catalog push': {'restage_push_catalog'},
  'build list': {'restage_list_builds'},
  'build push': {'restage_push_build'},
  'surface list': {'restage_list_surfaces'},
  'surface push': {'restage_push_surface'},
  'surface publish': {'restage_publish_surface'},
  'surface status': {'restage_surface_status'},
  'surface history': {'restage_surface_history'},
  'analytics overview': {'restage_read_analytics_overview'},
  'analytics explore': {'restage_read_explore'},
  'analytics surface': {'restage_read_surface_analytics'},
  'analytics taps': {'restage_read_surface_taps'},
  'analytics health': {'restage_read_data_health'},
  'delivery map': {'restage_read_delivery_map'},
  'where': {'restage_where'},
  'surface results': {'restage_read_surface_funnel'},
  'surface check-libraries': {'restage_check_libraries'},
  'surface rollback': {
    'restage_rollback_surface',
    'restage_rollback_preflight',
  },
  'surface kill': {'restage_kill_surface'},
  'surface freeze': {'restage_freeze_surface'},
  'surface unfreeze': {'restage_unfreeze_surface'},
  'surface routing audience-usage': {'restage_routing_audience_usage'},
  'surface routing delivery-diagnostics': {'restage_read_delivery_diagnostics'},
  'surface routing delivery-flow': {'restage_read_delivery_flow'},
  'surface routing list-audiences': {'restage_list_routing_audiences'},
  'surface routing preview': {'restage_preview_routing'},
  'surface routing review': {'restage_review_routing'},
  'surface routing review-rollback': {'restage_review_route_rollback'},
  'surface routing publish': {'restage_publish_routing'},
  'surface routing read': {'restage_read_routing'},
  'surface routing read-revision': {'restage_read_routing_revision'},
  'surface routing rollback': {'restage_rollback_route'},
  // The paywall group names the surface commands for one fixed type.
  'paywall list': {'restage_list_paywalls'},
  'paywall push': {'restage_push_surface'},
  'paywall publish': {'restage_publish_surface'},
  'paywall status': {'restage_surface_status'},
  'paywall history': {'restage_surface_history'},
  'paywall rollback': {
    'restage_rollback_surface',
    'restage_rollback_preflight',
  },
  'paywall kill': {'restage_kill_surface'},
  'paywall freeze': {'restage_freeze_surface'},
  'paywall unfreeze': {'restage_unfreeze_surface'},
  // Every experiment operation is one operation of the apply tool.
  'experiment activate': {'restage_experiment_apply'},
  'experiment archive': {'restage_experiment_apply'},
  'experiment conclude': {'restage_experiment_apply'},
  'experiment copy': {'restage_experiment_apply'},
  'experiment create': {'restage_experiment_apply'},
  'experiment delete-draft': {'restage_experiment_apply'},
  'experiment delivery-options': {'restage_experiment_apply'},
  'experiment discover': {'restage_experiment_apply'},
  'experiment list': {'restage_read_experiments'},
  'experiment pause': {'restage_experiment_apply'},
  'experiment read': {'restage_experiment_apply'},
  'experiment read-draft': {'restage_experiment_apply'},
  'experiment readiness': {'restage_experiment_apply'},
  'experiment register-build': {'restage_experiment_apply'},
  'experiment resolve-draft': {'restage_experiment_apply'},
  'experiment results': {'restage_read_experiment'},
  'experiment resume': {'restage_experiment_apply'},
  'experiment review': {'restage_experiment_apply'},
  'experiment save': {'restage_experiment_apply'},
  'experiment validate': {'restage_experiment_apply'},
  'experiment rebuild-serving-records': {'restage_rebuild_serving_records'},
  'mutation': {'restage_apply_canonical_mutation'},
  'experiment-activation': {'restage_activate_experiment'},
};

/// CLI commands with no MCP tool, and why.
const _cliOnly = <String, String>{
  'console':
      'Opens the full-screen terminal console; an MCP host has no terminal '
      'to draw it in.',
  'preview':
      'Hidden until the desktop preview app ships; a tool would advertise a '
      'command that cannot run yet.',
};

/// Tools that guard some calls and not others: one tool serves several CLI
/// commands, and only the ones that change live state ask.
const _guardedPerCall = {
  'restage_experiment_apply',
  'restage_rebuild_serving_records',
};

/// CLI commands the console's command line does not run, and why. Every
/// other command runs there as `restage <command>`.
const _consoleExcluded = {'console', 'login'};

Map<String, Command<int>> _leafCommands(
  Map<String, Command<int>> commands, [
  String? at,
]) {
  final leaves = <String, Command<int>>{};
  for (final command in commands.values.toSet()) {
    if (command.name == 'help') continue;
    final path = at == null ? command.name : '$at ${command.name}';
    if (command.subcommands.isEmpty) {
      leaves[path] = command;
    } else {
      leaves.addAll(_leafCommands(command.subcommands, path));
    }
  }
  return leaves;
}

void main() {
  late Map<String, Command<int>> cliLeaves;
  late List<String> cliCommands;
  late Set<String> mcpTools;
  late Set<String> guardedTools;
  late Map<String, Tool> toolDefinitions;

  setUpAll(() async {
    final activation = ExperimentActivationApi(
      transport: (bytes) async => bytes,
    );
    cliLeaves = _leafCommands(
      RestageCli(
        hasTerminal: () => false,
        experimentActivationApi: activation,
        environment: const {'RESTAGE_EXPERIMENTAL': '1'},
      ).commandRunner().commands,
    );
    cliCommands = cliLeaves.keys.toList();
    final directory = await Directory.systemTemp.createTemp('parity-census-');
    addTearDown(() => directory.delete(recursive: true));
    final connection = await connectServer(
      store: FileCredentialStore('${directory.path}/credentials'),
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      experimentActivationApi: activation,
      environment: const {'RESTAGE_EXPERIMENTAL': '1'},
    );
    final tools = (await connection.listTools(ListToolsRequest())).tools;
    toolDefinitions = {for (final tool in tools) tool.name: tool};
    mcpTools = {for (final tool in tools) tool.name};
    guardedTools = {
      for (final tool in tools)
        if (tool.inputSchema.properties?.containsKey('confirmLive') ?? false)
          tool.name,
    };
  });

  test('every CLI command has an MCP tool or a stated reason not to', () {
    final unmapped = [
      for (final command in cliCommands)
        if (!_cliToMcp.containsKey(command) && !_cliOnly.containsKey(command))
          command,
    ];
    expect(unmapped, isEmpty, reason: 'CLI commands with no MCP counterpart');
    final stale = [
      for (final command in [..._cliToMcp.keys, ..._cliOnly.keys])
        if (!cliCommands.contains(command)) command,
    ];
    expect(stale, isEmpty, reason: 'census names commands that do not exist');
  });

  test('every mapped MCP tool exists, and every MCP tool has a CLI '
      'command', () {
    final mapped = {for (final tools in _cliToMcp.values) ...tools};
    expect(mapped.difference(mcpTools), isEmpty, reason: 'missing MCP tools');
    expect(
      mcpTools.difference(mapped),
      isEmpty,
      reason: 'MCP tools with no CLI counterpart',
    );
  });

  test(
    'existing surface lifecycle paths expose complete review and exact proceed controls',
    () {
      for (final (command, tool) in [
        ('publish', 'restage_publish_surface'),
        ('rollback', 'restage_rollback_surface'),
        ('kill', 'restage_kill_surface'),
        ('freeze', 'restage_freeze_surface'),
        ('unfreeze', 'restage_unfreeze_surface'),
      ]) {
        for (final group in ['surface', 'paywall']) {
          final leaf = cliLeaves['$group $command']!;
          expect(
            leaf.argParser.options.keys,
            containsAll([
              'review-measurement',
              'reviewed-digest',
              'operation-id',
            ]),
          );
          expect(_cliToMcp['$group $command'], contains(tool));
        }
        expect(
          toolDefinitions[tool]!.inputSchema.properties!.keys,
          containsAll([
            'reviewOnly',
            'reviewedDigest',
            'operationId',
            'confirmLive',
          ]),
        );
      }
      final archive = cliLeaves['surface archive']!;
      expect(
        archive.argParser.options.keys,
        containsAll(['review-measurement', 'reviewed-digest', 'operation-id']),
      );
      expect(
        toolDefinitions['restage_archive_surface']!
            .inputSchema
            .properties!
            .keys,
        containsAll([
          'reviewOnly',
          'reviewedDigest',
          'operationId',
          'confirmLive',
        ]),
      );
    },
  );

  test('a CLI command that asks before a live change maps to a tool that '
      'needs confirmLive, and back', () {
    final guardedCommands = {
      for (final MapEntry(:key, :value) in cliLeaves.entries)
        if (value is LiveGuardedCommand) key,
    };
    expect(guardedCommands, isNotEmpty);
    expect(guardedTools, containsAll(_guardedPerCall));
    for (final command in guardedCommands) {
      expect(
        _cliToMcp[command]!.intersection(guardedTools),
        isNotEmpty,
        reason: '$command asks first; its MCP tool must too',
      );
    }
    for (final MapEntry(key: command, value: tools) in _cliToMcp.entries) {
      final wholeToolGuards = tools.where(
        (tool) =>
            guardedTools.contains(tool) && !_guardedPerCall.contains(tool),
      );
      if (wholeToolGuards.isNotEmpty) {
        expect(
          guardedCommands,
          contains(command),
          reason: '$command maps to a guarded tool; the CLI must ask too',
        );
      }
    }
  });

  test('the console runs every CLI command but the stated exceptions', () {
    expect(consoleExcludedCommands.keys.toSet(), _consoleExcluded);
    for (final command in cliCommands) {
      final first = command.split(' ').first;
      if (_consoleExcluded.contains(first)) continue;
      expect(
        consoleCommandArguments('restage $command'),
        command.split(' '),
        reason: command,
      );
    }
  });
}

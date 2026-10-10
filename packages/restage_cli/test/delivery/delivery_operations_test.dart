import 'package:args/command_runner.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:test/test.dart';

const deliveryOperationIds = {
  'placementList',
  'placementRead',
  'placementObservedHistory',
  'placementSimulate',
  'deliveryPolicyRead',
  'deliveryPolicyTimeline',
  'deliveryPolicyHistory',
  'deliveryPolicyFit',
  'deliveryPolicySimulate',
  'deliveryPolicyReview',
  'deliveryPolicyPublish',
  'deliveryPolicyUndoReview',
  'placementSampleImport',
  'placementSamplePrepare',
  'placementSampleStore',
  'placementSampleBind',
  'placementSampleRead',
  'placementSampleReadImage',
  'placementSampleDelete',
};

Map<String, Command<int>> leaves(
  Map<String, Command<int>> commands, [
  String at = '',
]) => {
  for (final command in commands.values.toSet())
    if (command.name != 'help')
      if (command.subcommands.isEmpty)
        '${at.isEmpty ? '' : '$at '}${command.name}': command
      else
        ...leaves(
          command.subcommands,
          '${at.isEmpty ? '' : '$at '}${command.name}',
        ),
};

void main() {
  test(
    'closed delivery census reaches actual CLI commands and mutation guards',
    () {
      final commands = leaves(
        RestageCli(hasTerminal: () => false).commandRunner().commands,
      );
      expect(deliveryOperations.keys.toSet(), deliveryOperationIds);
      expect(
        deliveryOperations.values.map((op) => op.mcpName).toSet(),
        hasLength(19),
      );
      expect(
        deliveryOperations.values.where((op) => op.rpcOwner != null),
        hasLength(18),
      );
      expect(
        deliveryOperations.values.where((op) => op.rpcOwner == null).single,
        DeliveryOperation.placementSampleImport,
      );
      for (final operation in deliveryOperations.values) {
        expect(commands, contains(operation.cliPath));
        expect(
          commands[operation.cliPath] is LiveGuardedCommand,
          operation.liveGuarded,
          reason: operation.cliPath,
        );
      }
      expect(
        commands['delivery plan publish']!.argParser.options,
        isNot(contains('plan')),
      );
    },
  );

  test('each RPC owner has its exact released public methods', () {
    final rpc = <String, Set<String>>{};
    for (final operation in deliveryOperations.values) {
      if (operation.rpcOwner case final owner?) {
        rpc.putIfAbsent(owner, () => {}).add(operation.rpcMethod!);
      }
    }
    expect(rpc, {
      'placementDirectory': {
        'readPage',
        'readPlacement',
        'readObservedHistory',
        'simulatePage',
      },
      'deliveryPolicy': {
        'readPolicy',
        'readTimeline',
        'readHistory',
        'readFit',
        'simulate',
        'review',
        'publish',
        'undoReview',
      },
      'placementSample': {
        'prepare',
        'store',
        'bind',
        'read',
        'readImage',
        'delete',
      },
    });
  });
}

import 'package:restage_cli/src/cli.dart';
import 'package:test/test.dart';

void main() {
  test('every surface command that takes a surface names it in its usage', () {
    final surface = RestageCli(
      hasTerminal: () => false,
    ).commandRunner().commands['surface']!;
    for (final name in const [
      'archive',
      'audit',
      'delete',
      'freeze',
      'history',
      'kill',
      'publish',
      'rename-version',
      'restore',
      'rollback',
      'status',
      'unfreeze',
    ]) {
      expect(
        surface.subcommands[name]!.invocation,
        'restage surface $name <id> [arguments]',
        reason: name,
      );
    }
  });
}

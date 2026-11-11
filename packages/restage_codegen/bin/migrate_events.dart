// Migrates the removed top-level event helpers to `context.surfaceEvent`.
//
//   dart run restage_codegen:migrate_events [paths...]
import 'dart:io';

import 'package:restage_codegen/src/migrate_events.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  final roots = args.isEmpty ? ['lib'] : args;
  final files = <File>[];
  for (final root in roots) {
    final type = FileSystemEntity.typeSync(root);
    if (type == FileSystemEntityType.file) {
      if (root.endsWith('.dart')) files.add(File(root));
    } else if (type == FileSystemEntityType.directory) {
      files.addAll(
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .where((file) => !file.path.contains('restage.generated')),
      );
    } else {
      stderr.writeln('$root: no such file or directory.');
      exitCode = 64;
      return;
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));

  var changed = 0;
  var refused = 0;
  for (final file in files) {
    final result = migrateEvents(file.readAsStringSync());
    if (result.changed) {
      file.writeAsStringSync(result.source);
      changed++;
      final declared = result.declared.isEmpty
          ? ''
          : ', declared ${result.declared.join(', ')}';
      stdout.writeln(
        '${file.path}: rewrote ${result.rewritten} '
        'call${result.rewritten == 1 ? '' : 's'}$declared',
      );
    }
    for (final note in result.notes) {
      stdout.writeln(
        '${file.path}:${note.line}:${note.column}: ${note.message}',
      );
    }
    for (final refusal in result.refusals) {
      refused++;
      stdout.writeln(
        '${file.path}:${refusal.line}:${refusal.column}: ${refusal.message}',
      );
    }
  }

  stdout
    ..writeln()
    ..writeln(
      changed == 0 && refused == 0
          ? 'Nothing to migrate.'
          : 'Migrated $changed file${changed == 1 ? '' : 's'}; '
                '$refused call${refused == 1 ? '' : 's'} left to change by '
                'hand.',
    );
  if (changed > 0) {
    stdout.writeln(
      'The migration keeps every event an event. A tap that only runs your '
      "app's code is simpler as a plain Flutter callback, such as "
      '`onPressed: onClose`; review each event and decide which it is.',
    );
  }
  if (refused > 0) exitCode = 1;
}

const _usage = '''
Rewrites `surfaceEvent`, `onboardingEvent`, `surfaceEventWithContext` and
`paywallEvent` calls to `context.surfaceEvent(...)`.

Usage: dart run restage_codegen:migrate_events [paths...]

Paths are Dart files or directories; the default is `lib`. Running it again
changes nothing.''';

import 'dart:io';

import 'package:restage_cli/src/cli.dart';

Future<void> main(List<String> args) async {
  final exitCode = await RestageCli(stdout: stdout, stderr: stderr).run(args);
  await stdout.flush();
  await stderr.flush();
  exit(exitCode);
}

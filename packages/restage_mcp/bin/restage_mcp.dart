import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:restage_mcp/restage_mcp.dart';

/// Entry point for the `restage_mcp` executable.
///
/// Speaks MCP over stdio: the MCP host launches this as a subprocess and
/// exchanges JSON-RPC messages over standard input/output. Nothing is written
/// to stdout except protocol frames.
void main() {
  RestageMcpServer.fromStreamChannel(
    stdioChannel(input: io.stdin, output: io.stdout),
  );
}

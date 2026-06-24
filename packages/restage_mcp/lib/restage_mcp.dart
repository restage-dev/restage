/// The Restage MCP server.
///
/// Library entry for embedding the server; most users launch the `restage_mcp`
/// executable directly and let their MCP host talk to it over stdio.
library;

export 'src/auth.dart' show NotSignedInException;
export 'src/server.dart' show RestageMcpServer, restageMcpVersion;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'watch_socket_stub.dart' if (dart.library.io) 'watch_socket_io.dart'
    as implementation;

/// Opens a watch socket that pings every [pingInterval] where the platform
/// can, and closes when a ping goes unanswered.
WebSocketChannel connectWatchSocket(Uri uri, Duration pingInterval) =>
    implementation.connectWatchSocket(uri, pingInterval);

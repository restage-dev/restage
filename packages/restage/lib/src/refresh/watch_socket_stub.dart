import 'package:web_socket_channel/web_socket_channel.dart';

/// Connects without pings; [pingInterval] is not used on the web.
WebSocketChannel connectWatchSocket(Uri uri, Duration pingInterval) =>
    WebSocketChannel.connect(uri);

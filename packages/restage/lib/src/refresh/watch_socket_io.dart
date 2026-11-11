import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A socket that pings, so a connection the network dropped closes.
WebSocketChannel connectWatchSocket(Uri uri, Duration pingInterval) =>
    IOWebSocketChannel.connect(uri, pingInterval: pingInterval);

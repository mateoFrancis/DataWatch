// lib/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  SocketService._privateConstructor();
  static final SocketService _instance = SocketService._privateConstructor();
  factory SocketService() => _instance;

  late IO.Socket socket;
  bool _initialized = false;

  /// Initialize the socket connection. Call once (e.g., at app start).
  /// serverUrl example: 'http://192.168.1.100:5000' or 'https://example.com'
  void init(String serverUrl, {String? token}) {
    if (_initialized) return;

    final options = <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    };

    if (token != null) {
      // If your server reads Authorization header on connect, include it here.
      options['extraHeaders'] = {'Authorization': 'Bearer $token'};
    }

    socket = IO.io(serverUrl, options);

    socket.on('connect', (_) => print('Socket connected: ${socket.id}'));
    socket.on('disconnect', (_) => print('Socket disconnected'));
    socket.on('connect_error', (err) => print('Socket connect_error: $err'));
    socket.on('error', (err) => print('Socket error: $err'));

    socket.connect();
    _initialized = true;
  }

  /// Re-init with token (if you need to reconnect with auth header)
  void reinitWithToken(String serverUrl, String token) {
    try {
      socket.dispose();
    } catch (_) {}
    _initialized = false;
    init(serverUrl, token: token);
  }

  void dispose() {
    try {
      socket.dispose();
    } catch (_) {}
    _initialized = false;
  }
}

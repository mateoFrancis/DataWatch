// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'home_page.dart';
import 'about_page.dart';
import 'socket_service.dart';

const String PREFS_LOGGED_IN = 'loggedIn';
const String PREFS_AUTH_TOKEN = 'authToken';

// Replace with your running Flask-SocketIO server
const String SERVER_URL = 'http://127.0.0.1:5000';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize socket service without token for now; it will persist until you reinit with token if needed.
  SocketService().init(SERVER_URL);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PREFS_LOGGED_IN) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DataWatch',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FutureBuilder<bool>(
        future: _checkLoggedIn(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final loggedIn = snapshot.data ?? false;
          return loggedIn ? const HomePage() : const LoginPage();
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showAboutInline = false;
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter username and password')));
      return;
    }

    setState(() => _isLoggingIn = true);

    final socket = SocketService().socket;

    final completer = Completer<Map<String, dynamic>>();
    void handler(dynamic payload) {
      if (!completer.isCompleted) {
        if (payload is Map) {
          completer.complete(Map<String, dynamic>.from(payload as Map));
        } else {
          completer.complete({'ok': false, 'message': 'Invalid server response'});
        }
      }
    }

    // Use once so the handler is removed after first call
    socket.once('login_result', handler);

    // Emit the login event
    try {
      socket.emit('login', {'username': username, 'password': password});
    } catch (e) {
      socket.off('login_result', handler);
      setState(() => _isLoggingIn = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Socket error: $e')));
      return;
    }

    try {
      final result = await completer.future.timeout(const Duration(seconds: 8));
      final ok = result['ok'] == true;
      final message = result['message'] as String? ?? '';
      final token = result['token'] as String?;

      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PREFS_LOGGED_IN, true);
        if (token != null) {
          await prefs.setString(PREFS_AUTH_TOKEN, token);
          // Re-init socket with auth header if your server expects it on connect
          SocketService().reinitWithToken(SERVER_URL, token);
        }

        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login timed out')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      socket.off('login_result', handler);
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                const Text('Welcome', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Sign In to continue', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 20),
                TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoggingIn ? null : _login,
                    child: _isLoggingIn ? const CircularProgressIndicator(color: Colors.white) : const Text('Login'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showAboutInline = !_showAboutInline;
                    });
                  },
                  child: const Text('About Us'),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: const AboutInline(),
                  crossFadeState: _showAboutInline ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
                  child: const Text('Open About Page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline small About used on login screen
class AboutInline extends StatelessWidget {
  const AboutInline({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About DataWatch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(
            'DataWatch is a monitoring platform that tracks and visualizes data source connectivity and reporting performance in real time. '
            'It helps teams detect system issues early, analyze logs, and maintain operational transparency across distributed systems.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          SizedBox(height: 10),
          Text('Version 1.0.0 — Developed 2025', style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

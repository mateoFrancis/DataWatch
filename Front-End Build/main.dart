// main.dart — DataWatch login with Flask auth, register flow, and offline fallback
// -----------------------------------------------------------------------------
// Sections:
// 1) Imports
// 2) App root (MyApp + login state check)
// 3) LoginPage stateful widget
//    3.1) Controllers, flags, and lifecycle
//    3.2) Server calls (login/register)
//    3.3) Actions (login/register handlers)
//    3.4) UI layout (logo, about inline, form, buttons)
// 4) Inline About section
// -----------------------------------------------------------------------------

// 1) Imports
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'home_page.dart';
import 'about_page.dart';

// 2) App root (MyApp + login state check)
void main() {
  runApp(const MyApp());
}

// Root widget for the app
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Checks persisted login state
  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('loggedIn') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DataWatch',
      theme: ThemeData(primarySwatch: Colors.blue),
      // Decide whether to show HomePage or LoginPage based on login state
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
      debugShowCheckedModeBanner: false,
    );
  }
}

// 3) LoginPage stateful widget
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

// 3.1) Controllers, flags, and lifecycle
class _LoginPageState extends State<LoginPage> {
  // Form controllers
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // UI state flags
  bool _showAboutInline = false; // toggles the inline About content
  bool _isLoading = false;       // shows progress indicator on actions
  String? _errorMessage;         // displays errors above the form
  bool _isRegisterMode = false;  // toggles between Login and Create Account

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // 3.2) Server calls (login/register)
  // Configure endpoints for test vs production
  static const bool _isTestMode = false; // set false for production builds
  String get _loginEndpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/login' : 'https://datawatchapp.com/login';
  String get _registerEndpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/register' : 'https://datawatchapp.com/register';

  // Try to authenticate with Flask server
  Future<Map<String, dynamic>> _authenticateWithServer(
    String username,
    String password,
  ) async {
    final url = Uri.parse(_loginEndpoint);

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Login successful',
          // Only rely on username; fallback to the input if backend omits it
          'username': data['username'] ?? username,
        };
      } else {
        // Parse server error body when available
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {}
        return {
          'success': false,
          'message': data?['message'] ?? 'Login failed',
        };
      }
    } catch (_) {
      // Server unreachable or timeout
      return {'success': null, 'message': 'Server unreachable'};
    }
  }

  // Call Flask register endpoint to create account
  Future<Map<String, dynamic>> _registerWithServer(
    String username,
    String password,
  ) async {
    final url = Uri.parse(_registerEndpoint);

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Account created',
        };
      } else {
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {}
        return {
          'success': false,
          'message': data?['message'] ?? 'Registration failed',
        };
      }
    } catch (_) {
      // Server unreachable or timeout
      return {'success': null, 'message': 'Server unreachable'};
    }
  }

  // 3.3) Actions (login/register handlers)

  // Handle login with server, with offline blank-credentials fallback
  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Offline fallback: allow blank username/password to enter app locally
    if (username.isEmpty && password.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      await prefs.setString('username', 'local'); // mark as local session
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
      return;
    }

    // Online path: authenticate against Flask
    final result = await _authenticateWithServer(username, password);

    if (!mounted) return;

    if (result['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      await prefs.setString('username', result['username']);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } else if (result['success'] == null) {
      // Server unreachable
      setState(() {
        _errorMessage = 'Server unreachable. Account login requires server; use blank username/password to log in locally.';
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Login failed';
        _isLoading = false;
      });
    }
  }

  // Create account: requires confirm password match, server availability
  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    // Validate password confirmation before calling server
    if (password != confirm) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }
    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a username';
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a password';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Call Flask register endpoint
    final result = await _registerWithServer(username, password);

    if (!mounted) return;

    if (result['success'] == true) {
      // Inform user and return to login mode
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
      setState(() {
        _isRegisterMode = false;
        _isLoading = false;
      });
    } else if (result['success'] == null) {
      // Server unreachable: account creation disabled
      setState(() {
        _errorMessage = 'Account creation is unavailable at the moment (server unreachable). Please try again later.';
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Registration failed';
        _isLoading = false;
      });
    }
  }

  // 3.4) UI layout (logo, about inline, form, buttons)
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
                // Logo above Welcome, tappable to AboutPage
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()));
                  },
                  child: Image.asset(
                    'assets/main_logo.png',
                    width: MediaQuery.of(context).size.width * 0.5,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),

                // Title + subtitle depending on mode
                Text(
                  _isRegisterMode ? 'Create Account' : 'Welcome',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRegisterMode ? 'Fill in details to register' : 'Sign In to continue',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),

                // Error message display
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
                        ),
                      ],
                    ),
                  ),

                // Username
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                // Password
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true,
                ),
                const SizedBox(height: 12),

                // Confirm Password (only in register mode)
                if (_isRegisterMode)
                  TextField(
                    controller: _confirmController,
                    decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder()),
                    obscureText: true,
                  ),

                const SizedBox(height: 12),

                // Primary action: Login or Create Account
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : _isRegisterMode
                            ? _register
                            : _login,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(_isRegisterMode ? 'Create Account' : 'Login'),
                  ),
                ),
                const SizedBox(height: 12),

                // Toggle register/login mode
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isRegisterMode = !_isRegisterMode;
                            _errorMessage = null; // clear error on toggle
                          });
                        },
                  child: Text(_isRegisterMode ? 'Back to Login' : 'Create Account'),
                ),
                const SizedBox(height: 12),

                // About Us inline toggle
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 4) Inline About section
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



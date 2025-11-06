import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_page.dart';
import 'about_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('loggedIn') ?? false;
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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username == "" && password == "") {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Incorrect username and/or password. Please try again.")),
      );
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
                SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _login, child: const Text('Login'))),
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


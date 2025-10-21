import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'about_page.dart'; // small About reuse from a separate file

const String PREFS_OLD_SNAPSHOT = 'oldSnapshot';
const String PREFS_ERROR_LOG = 'errorLog';
const String PREFS_DAILY_LOG = 'dailyLog';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Random _rng = Random();

  List<Map<String, dynamic>> sources = [];
  Map<String, dynamic>? oldSnapshot;
  Timer? _refreshTimer;

  final List<Map<String, String>> _errorLog = [];
  final List<Map<String, String>> _dailyLog = [];

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initEverything() async {
    await _loadPersistedState();
    _generateMockData();
    await _evaluateAndPersistChanges();
    _startTimer();
    setState(() {});
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedSnap = prefs.getString(PREFS_OLD_SNAPSHOT);
    if (storedSnap != null) {
      try {
        oldSnapshot = jsonDecode(storedSnap) as Map<String, dynamic>;
      } catch (_) {
        oldSnapshot = null;
      }
    }

    final storedErrors = prefs.getString(PREFS_ERROR_LOG);
    if (storedErrors != null) {
      try {
        final list = jsonDecode(storedErrors) as List<dynamic>;
        _errorLog.clear();
        for (var e in list) {
          _errorLog.add(Map<String, String>.from(e as Map));
        }
      } catch (_) {}
    }

    final storedDaily = prefs.getString(PREFS_DAILY_LOG);
    if (storedDaily != null) {
      try {
        final list = jsonDecode(storedDaily) as List<dynamic>;
        _dailyLog.clear();
        for (var e in list) {
          _dailyLog.add(Map<String, String>.from(e as Map));
        }
      } catch (_) {}
    }
  }

  Future<void> _savePersistedLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREFS_ERROR_LOG, jsonEncode(_errorLog));
    await prefs.setString(PREFS_DAILY_LOG, jsonEncode(_dailyLog));
  }

  Future<void> _saveOldSnapshot(Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREFS_OLD_SNAPSHOT, jsonEncode(snapshot));
    oldSnapshot = snapshot;
  }

  Future<void> _clearPersistedAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREFS_OLD_SNAPSHOT);
    await prefs.remove(PREFS_ERROR_LOG);
    await prefs.remove(PREFS_DAILY_LOG);
    oldSnapshot = null;
    _errorLog.clear();
    _dailyLog.clear();
    setState(() {});
  }

  void _startTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _onRefreshCycle();
    });
  }

  Future<void> _onRefreshCycle() async {
    _generateMockData();
    await _evaluateAndPersistChanges();
    setState(() {});
  }

  Map<String, dynamic> _buildSnapshotFromSources() {
    final map = <String, dynamic>{};
    for (var s in sources) {
      final name = s['name'] as String;
      map[name] = {
        'connection': s['connectionKey'],
        'report': s['reportKey'],
        'connectionDetails': s['connectionDetails'],
        'reportDetails': s['reportDetails'],
      };
    }
    return map;
  }

  Future<void> _evaluateAndPersistChanges() async {
    final snapshot = _buildSnapshotFromSources();
    final changed = jsonEncode(snapshot) != jsonEncode(oldSnapshot ?? {});
    if (changed) {
      _appendLogsFromSnapshot(snapshot);
      await _saveOldSnapshot(snapshot);
      await _savePersistedLogs();
    }
  }

  void _appendLogsFromSnapshot(Map<String, dynamic> snapshot) {
    final now = DateTime.now().toIso8601String();

    snapshot.forEach((name, value) {
      final entry = value as Map<String, dynamic>;
      final conn = entry['connection'] as String? ?? 'unknown';
      final rep = entry['report'] as String? ?? 'unknown';
      final connDetails = entry['connectionDetails'] as String? ?? '';
      final repDetails = entry['reportDetails'] as String? ?? '';

      if (conn == 'error' || conn == 'down') {
        _errorLog.insert(0, {'time': now, 'description': '$name connection: $connDetails', 'status': conn.toUpperCase()});
      }

      if ((rep == 'error' || rep == 'down')) {
        if (!(conn == 'ok' || conn == 'stale')) {
          _errorLog.insert(0, {'time': now, 'description': '$name report: $repDetails', 'status': rep.toUpperCase()});
        }
      }

      _dailyLog.insert(0, {'time': now, 'description': '$name update - conn:$conn rep:$rep', 'status': 'INFO'});

      if (_errorLog.length > 1000) _errorLog.removeRange(1000, _errorLog.length);
      if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length);
    });
  }

  // --- mock data helpers (pick keys, messages, icons, colors) ---
  String _pickConnKey() {
    final r = _rng.nextDouble();
    if (r < 0.10) return 'down';
    if (r < 0.30) return 'warning';
    return 'ok';
  }

  String _pickRepKey() {
    final r = _rng.nextDouble();
    if (r < 0.10) return 'down';
    if (r < 0.25) return 'warning';
    return 'ok';
  }

  String _messageFor(String key, String kind, String name, DateTime ts) {
    switch (key) {
      case 'ok':
        return '$kind OK: ${kind == 'connection' ? "Connected" : "Report received"} at ${ts.toIso8601String()}';
      case 'stale':
        return '$kind Stale: New data matches previous snapshot, no new updates';
      case 'down':
        return '$kind Down: No response from the source';
      case 'warning':
        return '$kind Warning: Partial data or late arrival';
      case 'error':
        return '$kind Error: Failed to process incoming data';
      default:
        return '$kind Unknown state';
    }
  }

  IconData _iconForKey(String k) {
    switch (k) {
      case 'ok':
        return Icons.check;
      case 'error':
        return Icons.close;
      case 'warning':
        return Icons.warning;
      case 'stale':
        return Icons.more_horiz;
      case 'down':
        return Icons.cloud_off;
      default:
        return Icons.help_outline;
    }
  }

  Color _colorForKey(String k) {
    switch (k) {
      case 'ok':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'stale':
        return Colors.grey;
      case 'down':
        return Colors.purple;
      default:
        return Colors.black;
    }
  }

  List<Map<String, String>> _currentErrorsFromSources() {
    final List<Map<String, String>> list = [];
    final now = DateTime.now().toIso8601String();

    for (var s in sources) {
      final name = s['name'] as String;
      final connKey = s['connectionKey'] as String;
      final repKey = s['reportKey'] as String;
      final connDetails = s['connectionDetails'] as String;
      final repDetails = s['reportDetails'] as String;

      if (connKey == 'error' || connKey == 'down') {
        list.add({'time': now, 'description': '$name connection: $connDetails', 'status': connKey.toUpperCase()});
      }
      if ((repKey == 'error' || repKey == 'down') && !(connKey == 'ok' || connKey == 'stale')) {
        list.add({'time': now, 'description': '$name report: $repDetails', 'status': repKey.toUpperCase()});
      }
    }

    return list;
  }

  List<Map<String, String>> _currentLogFromSources() {
    final List<Map<String, String>> list = [];
    final now = DateTime.now().toIso8601String();

    for (var s in sources) {
      final name = s['name'] as String;
      final connKey = s['connectionKey'] as String;
      final repKey = s['reportKey'] as String;
      list.add({'time': now, 'description': '$name - conn:$connKey rep:$repKey', 'status': 'VIEW'});
    }
    return list;
  }

  void _generateMockData() {
    final int sourceCount = 6;
    final now = DateTime.now();
    final previous = oldSnapshot ?? {};

    List<Map<String, dynamic>> newSources = [];

    for (var i = 0; i < sourceCount; i++) {
      final name = 'Source ${String.fromCharCode(65 + i)}';

      String connKey = _pickConnKey();
      String repKey = _pickRepKey();

      if (_rng.nextDouble() < 0.05) connKey = 'error';
      if (_rng.nextDouble() < 0.05) repKey = 'error';

      DateTime connTs = now.subtract(Duration(minutes: i * 2 + _rng.nextInt(5)));
      DateTime repTs = now.subtract(Duration(minutes: i * 3 + _rng.nextInt(7)));

      String connDetails = _messageFor(connKey, 'connection', name, connTs);
      String repDetails = _messageFor(repKey, 'report', name, repTs);

      String connKeyForCompare = connKey;
      String repKeyForCompare = repKey;

      if (previous.containsKey(name)) {
        final prev = previous[name] as Map<String, dynamic>;
        final prevConnKey = prev['connection'] as String?;
        final prevConnDetails = prev['connectionDetails'] as String?;
        final prevRepKey = prev['report'] as String?;
        final prevRepDetails = prev['reportDetails'] as String?;

        if (_rng.nextDouble() < 0.18) {
          connDetails = prevConnDetails ?? connDetails;
          connKeyForCompare = prevConnKey ?? connKeyForCompare;
        }
        if (_rng.nextDouble() < 0.18) {
          repDetails = prevRepDetails ?? repDetails;
          repKeyForCompare = prevRepKey ?? repKeyForCompare;
        }

        if (prevConnKey != null && prevConnDetails != null && prevConnKey == connKeyForCompare && prevConnDetails == connDetails) {
          connKeyForCompare = 'stale';
          connDetails = _messageFor('stale', 'connection', name, connTs);
        }

        if (prevRepKey != null && prevRepDetails != null && prevRepKey == repKeyForCompare && prevRepDetails == repDetails) {
          if (connKeyForCompare == 'stale') {
            repKeyForCompare = 'stale';
            repDetails = _messageFor('stale', 'report', name, repTs);
          } else {
            repKeyForCompare = repKeyForCompare;
          }
        }

        if (connKeyForCompare == 'stale') {
          if (prevRepKey == repKeyForCompare && prevRepDetails == repDetails) {
            repKeyForCompare = 'stale';
            repDetails = _messageFor('stale', 'report', name, repTs);
          }
        }
      }

      if (repKeyForCompare == 'ok' && connKeyForCompare != 'ok') {
        if (connKeyForCompare == 'stale') {
          repKeyForCompare = 'stale';
          repDetails = _messageFor('stale', 'report', name, repTs);
        } else {
          repKeyForCompare = 'warning';
          repDetails = _messageFor('warning', 'report', name, repTs);
        }
      }

      if (repKeyForCompare == 'down' && connKeyForCompare != 'down') {
        if (connKeyForCompare == 'error') {
          repKeyForCompare = 'error';
          repDetails = _messageFor('error', 'report', name, repTs);
        } else {
          repKeyForCompare = 'warning';
          repDetails = _messageFor('warning', 'report', name, repTs);
        }
      }

      if (repKeyForCompare == 'stale' && connKeyForCompare != 'stale') {
        repKeyForCompare = 'warning';
        repDetails = _messageFor('warning', 'report', name, repTs);
      }

      if ((connKeyForCompare == 'ok' || connKeyForCompare == 'stale') && (repKeyForCompare == 'error' || repKeyForCompare == 'down')) {
        repKeyForCompare = 'warning';
        repDetails = _messageFor('warning', 'report', name, repTs);
      }

      newSources.add({
        'name': name,
        'connectionKey': connKeyForCompare,
        'reportKey': repKeyForCompare,
        'connectionIcon': _iconForKey(connKeyForCompare),
        'reportIcon': _iconForKey(repKeyForCompare),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
      });
    }

    sources = newSources;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Data Watch'),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage()));
              },
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        actions: [
          TextButton(
            onPressed: () {
              final errors = _currentErrorsFromSources();
              Navigator.push(context, MaterialPageRoute(builder: (_) => ErrorPage(entries: errors, persistedErrors: _errorLog)));
            },
            child: const Text('Errors', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              final logs = _currentLogFromSources();
              Navigator.push(context, MaterialPageRoute(builder: (_) => LogPage(entries: logs, persistedLogs: _dailyLog)));
            },
            child: const Text('Log', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            onPressed: () async {
              await _clearPersistedAll();
            },
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            tooltip: 'Clear persisted snapshot and logs',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('Data Source Status', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Column(children: [
                Row(children: const [
                  SizedBox(width: 140, child: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(child: Center(child: Text('Connection', style: TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(child: Center(child: Text('Report', style: TextStyle(fontWeight: FontWeight.bold)))),
                ]),
                const Divider(color: Colors.black),
                Expanded(
                  child: ListView.separated(
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: sources.length,
                    itemBuilder: (context, idx) {
                      final s = sources[idx];
                      final name = s['name'] as String;
                      final connKey = s['connectionKey'] as String;
                      final repKey = s['reportKey'] as String;
                      final connIcon = s['connectionIcon'] as IconData;
                      final repIcon = s['reportIcon'] as IconData;
                      final connDetails = s['connectionDetails'] as String;
                      final repDetails = s['reportDetails'] as String;

                      return Column(children: [
                        Row(children: [
                          SizedBox(width: 140, child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: Colors.black45),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () {
                                _showDetailsDialog(context, '$name - Connection', connDetails, connKey);
                              },
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(connIcon, color: _colorForKey(connKey)),
                                const SizedBox(width: 8),
                                Text(connKey.toUpperCase(), style: TextStyle(color: _colorForKey(connKey))),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: Colors.black45),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () {
                                _showDetailsDialog(context, '$name - Report', repDetails, repKey);
                              },
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(repIcon, color: _colorForKey(repKey)),
                                const SizedBox(width: 8),
                                Text(repKey.toUpperCase(), style: TextStyle(color: _colorForKey(repKey))),
                              ]),
                            ),
                          ),
                        ]),
                      ]);
                    },
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _buildLegend(),
        ]),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.2),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _legendItem(Icons.check, 'OK', Colors.green),
        _legendItem(Icons.more_horiz, 'Stale', Colors.grey),
        _legendItem(Icons.cloud_off, 'Down', Colors.purple),
        _legendItem(Icons.warning, 'Warning', Colors.orange),
        _legendItem(Icons.close, 'Error', Colors.red),
      ]),
    );
  }

  Widget _legendItem(IconData icon, String label, Color color) {
    return Row(children: [Icon(icon, color: color), const SizedBox(width: 6), Text(label)]);
  }

  void _showDetailsDialog(BuildContext context, String title, String content, String key) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [Text(title), const Spacer(), Icon(_iconForKey(key), color: _colorForKey(key))]),
        content: Text(content),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }
}

// Error and LogPage
class ErrorPage extends StatelessWidget {
  final List<Map<String, String>> entries;
  final List<Map<String, String>> persistedErrors;

  const ErrorPage({super.key, required this.entries, required this.persistedErrors});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Errors'),
          backgroundColor: Colors.blue,
          bottom: const TabBar(tabs: [Tab(text: 'Current View'), Tab(text: 'History')]),
        ),
        body: TabBarView(
          children: [
            entries.isEmpty
                ? const Center(child: Text('No errors on current view', style: TextStyle(fontSize: 16)))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.error, color: Colors.red),
                          title: Text(e['description'] ?? ''),
                          subtitle: Text('Time: ${e['time']}\nStatus: ${e['status']}', style: const TextStyle(fontSize: 13)),
                        ),
                      );
                    },
                  ),
            persistedErrors.isEmpty
                ? const Center(child: Text('No persisted errors', style: TextStyle(fontSize: 16)))
                : ListView.builder(
                    itemCount: persistedErrors.length,
                    itemBuilder: (context, index) {
                      final e = persistedErrors[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.history, color: Colors.redAccent),
                          title: Text(e['description'] ?? ''),
                          subtitle: Text('Time: ${e['time']}\nStatus: ${e['status']}', style: const TextStyle(fontSize: 13)),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class LogPage extends StatelessWidget {
  final List<Map<String, String>> entries;
  final List<Map<String, String>> persistedLogs;

  const LogPage({super.key, required this.entries, required this.persistedLogs});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Log'),
          backgroundColor: Colors.blue,
          bottom: const TabBar(tabs: [Tab(text: 'Current View'), Tab(text: 'History')]),
        ),
        body: TabBarView(children: [
          entries.isEmpty
              ? const Center(child: Text('No entries on current view', style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.article, color: Colors.blueGrey),
                        title: Text(e['description'] ?? ''),
                        subtitle: Text('Time: ${e['time']}\nStatus: ${e['status']}', style: const TextStyle(fontSize: 13)),
                      ),
                    );
                  },
                ),
          persistedLogs.isEmpty
              ? const Center(child: Text('No persisted logs', style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  itemCount: persistedLogs.length,
                  itemBuilder: (context, index) {
                    final e = persistedLogs[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.history, color: Colors.blueGrey),
                        title: Text(e['description'] ?? ''),
                        subtitle: Text('Time: ${e['time']}\nStatus: ${e['status']}', style: const TextStyle(fontSize: 13)),
                      ),
                    );
                  },
                ),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sections with citations:
//  1) Imports and persisted keys
//     - Flutter Material library: https://api.flutter.dev/flutter/material/material-library.html
//     - Shared preferences: https://pub.dev/packages/shared_preferences
//     - Dart async (Timer/Future): https://api.dart.dev/stable/dart-async/dart-async-library.html
//     - Dart convert (JSON): https://api.dart.dev/stable/dart-convert/dart-convert-library.html
//
//  2) Defaults and enums
//     - Dart language (enums): https://dart.dev/language/enums
//
//  3) HomePage widget and lifecycle
//     - Stateful and stateless widgets: https://docs.flutter.dev/development/ui/interactive#stateful-and-stateless-widgets
//
//  4) Persistence helpers
//     - Shared preferences: https://pub.dev/packages/shared_preferences
//
//  5) Updates (periodic polling)
//     - Dart Timer: https://api.dart.dev/stable/dart-async/Timer-class.html
//
//  6) Socket.IO helpers and JSON probing (socket-only build)
//     - socket_io_client package: https://pub.dev/packages/socket_io_client
//     - Dart JSON decoding: https://api.dart.dev/stable/dart-convert/dart-convert-library.html
//
//  7) Data generation for sources (A/B backend via socket, C/D simulated via socket)
//     - Dart math (Random): https://api.dart.dev/stable/dart-math/dart-math-library.html
//
//  8) Status aggregation and formatting helpers
//     - Icon widget: https://api.flutter.dev/flutter/widgets/Icon-class.html
//     - Material Icons: https://fonts.google.com/icons
//
//  9) UI building (AppBar, list, dialogs)
//     - Material library (AppBar, ListView, etc.): https://api.flutter.dev/flutter/material/material-library.html
//     - Flutter layout: https://docs.flutter.dev/development/ui/layout
//     - AlertDialog: https://api.flutter.dev/flutter/material/AlertDialog-class.html
//
// 10) Settings dialogs (per-source + global)
//     - Flutter dialogs (cookbook): https://docs.flutter.dev/cookbook/design/dialogs
//     - StatefulBuilder: https://api.flutter.dev/flutter/widgets/StatefulBuilder-class.html
//
// 11) Error and Log helpers and pages
//     - TabBar: https://api.flutter.dev/flutter/material/TabBar-class.html
//     - TabBarView: https://api.flutter.dev/flutter/material/TabBarView-class.html
//
// 12) Logout handling
//     - Socket-based logout or server-side session handling (adapt as needed)
//
// 13) Color palettes and filters
//     - ColorFilter: https://api.flutter.dev/flutter/dart-ui/ColorFilter-class.html
//     - Accessibility overview: https://docs.flutter.dev/development/accessibility-and-localization/accessibility
//
// 14) Utility functions
//     - Dart DateTime: https://api.dart.dev/stable/dart-core/DateTime-class.html
//     - Dart convert (JSON formatting): https://api.dart.dev/stable/dart-convert/dart-convert-library.html
// -----------------------------------------------------------------------------


import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard support
import 'package:shared_preferences/shared_preferences.dart';

// --- Socket.IO client import (socket-only build) ---
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'about_page.dart';
import 'main.dart';

// -----------------------
// 1) Imports and persisted keys
// -----------------------
const String PREFS_OLD_SNAPSHOT = 'oldSnapshot';
const String PREFS_ERROR_LOG = 'errorLog';
const String PREFS_DAILY_LOG = 'dailyLog';
const String PREFS_REFRESH_INTERVAL = 'refreshIntervalSeconds';
const String PREFS_SOURCE_SETTINGS = 'sourceSettings';
const String PREFS_COLOR_MODE = 'colorVisionMode';
const String PREFS_LAST_COMBINED_REPORT = 'lastCombinedReport';
const String PREFS_LAST_EXPORT_TXT = 'lastExportTxt';

// -----------------------
// 2) Defaults and enums
// -----------------------
const int DEFAULT_REFRESH_SECONDS = 60;
const int DEFAULT_STALE_MINUTES_CONN = 5;
const int DEFAULT_STALE_MINUTES_REP = 5;
const double DEFAULT_VARIANCE_PERCENT = 10.0;
const int PROGRESS_ANIMATION_SECONDS = 10;

enum ColorVisionMode {
  Original,
  Protanomaly,
  Deuteranomaly,
  Protanopia,
  Deuteranopia,
  Tritanomaly,
  Tritanopia,
  Achromatopsia,
}

// -----------------------
// 3) HomePage widget and lifecycle
// -----------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final Random _rng = Random();

  // Sources list: each entry contains name, C1/C2/C3, R1/R2/R3, keys and details.
  List<Map<String, dynamic>> sources = [];

  Map<String, dynamic>? oldSnapshot;
  final List<Map<String, String>> _errorLog = [];
  final List<Map<String, String>> _dailyLog = [];

  Timer? _refreshTimer;
  int _refreshSeconds = DEFAULT_REFRESH_SECONDS;

  Map<String, Map<String, dynamic>> _sourceSettings = {};
  final Map<String, DateTime> _progressStart = {};
  Map<String, dynamic>? _lastCombinedReport;

  // Set _isTestMode to false for production builds; true for local testing.
  static const bool _isTestMode = false; // set false for production builds

  // Endpoints (kept for reference; socket-only build uses same logical endpoints via socket events)
  String get _c1Endpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/C1' : 'https://datawatchapp.com/api/C1';
  String get _c2Endpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/C2' : 'https://datawatchapp.com/api/C2';
  String get _c3Endpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/C3' : 'https://datawatchapp.com/api/C3';
  String get _r1Endpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/R1' : 'https://datawatchapp.com/api/R1';
  String get _r2Endpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/R2' : 'https://datawatchapp.com/api/R2';

  String get _logoutEndpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/logout' : 'https://datawatchapp.com/logout';

  ColorVisionMode _colorMode = ColorVisionMode.Original;

  // Socket.IO client instance and latest socket payloads store
  IO.Socket? _socket;
  // _latestSocket stores either event-level payloads or event+source payloads.
  // Keys used:
  //   'c1' -> latest c1 payload (no source)
  //   'c2_weather' -> latest c2 payload for source "weather"
  //   'c2_earthquake' -> latest c2 payload for source "earthquake"
  //   similarly for c3 if server includes source
  final Map<String, Map<String, dynamic>> _latestSocket = {};

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    try {
      _socket?.disconnect();
      _socket?.destroy();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initEverything() async {
    await _loadPersistedState();
    await _loadLastCombinedReport();

    // Setup socket listeners before generating data so incoming events are captured
    _setupSocketListeners();

    await _generateData();
    await _evaluateAndPersistChanges();
    _startUpdates(); // periodic UI refresh to reflect socket updates
    setState(() {});
  }

  // -----------------------
  // 4) Persistence helpers
  // -----------------------
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
        for (var e in list) _errorLog.add(Map<String, String>.from(e as Map));
      } catch (_) {}
    }

    final storedDaily = prefs.getString(PREFS_DAILY_LOG);
    if (storedDaily != null) {
      try {
        final list = jsonDecode(storedDaily) as List<dynamic>;
        _dailyLog.clear();
        for (var e in list) _dailyLog.add(Map<String, String>.from(e as Map));
      } catch (_) {}
    }

    final storedInterval = prefs.getInt(PREFS_REFRESH_INTERVAL);
    _refreshSeconds = storedInterval ?? DEFAULT_REFRESH_SECONDS;

    final storedSourceSettings = prefs.getString(PREFS_SOURCE_SETTINGS);
    if (storedSourceSettings != null) {
      try {
        final decoded = jsonDecode(storedSourceSettings) as Map<String, dynamic>;
        _sourceSettings =
            decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
      } catch (_) {
        _sourceSettings = {};
      }
    }

    final storedColorMode = prefs.getString(PREFS_COLOR_MODE);
    if (storedColorMode != null) {
      try {
        _colorMode = ColorVisionMode.values.firstWhere((e) => e.toString() == storedColorMode);
      } catch (_) {
        _colorMode = ColorVisionMode.Original;
      }
    }
  }

  Future<void> _loadLastCombinedReport() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(PREFS_LAST_COMBINED_REPORT);
    if (stored != null) {
      try {
        _lastCombinedReport = jsonDecode(stored) as Map<String, dynamic>;
      } catch (_) {
        _lastCombinedReport = null;
      }
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

  Future<void> _saveSettingsPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PREFS_REFRESH_INTERVAL, _refreshSeconds);
    await prefs.setString(PREFS_SOURCE_SETTINGS, jsonEncode(_sourceSettings));
    await prefs.setString(PREFS_COLOR_MODE, _colorMode.toString());
  }

  Future<void> _saveLastCombinedReport(Map<String, dynamic> report) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREFS_LAST_COMBINED_REPORT, jsonEncode(report));
    _lastCombinedReport = report;
  }

  Future<void> _clearPersistedAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREFS_OLD_SNAPSHOT);
    await prefs.remove(PREFS_ERROR_LOG);
    await prefs.remove(PREFS_DAILY_LOG);
    await prefs.remove(PREFS_REFRESH_INTERVAL);
    await prefs.remove(PREFS_SOURCE_SETTINGS);
    await prefs.remove(PREFS_COLOR_MODE);
    await prefs.remove(PREFS_LAST_COMBINED_REPORT);
    oldSnapshot = null;
    _errorLog.clear();
    _dailyLog.clear();
    _sourceSettings.clear();
    _colorMode = ColorVisionMode.Original;
    _lastCombinedReport = null;
    setState(() {});
  }

  // -----------------------
  // 5) Updates (periodic UI refresh)
  // -----------------------
  void _startUpdates() {
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshSeconds), (timer) async {
      // No HTTP polling; timer triggers UI refresh to reflect latest socket data
      await _generateData();
      await _evaluateAndPersistChanges();
      if (mounted) setState(() {});
    });
  }

  Future<void> _onRefreshCycle() async {
    await _generateData();
    await _evaluateAndPersistChanges();
    if (mounted) setState(() {});
  }

  // -----------------------
  // 6) Socket.IO helpers and JSON probing (socket-only)
  // -----------------------
  // Helper to map display name to server source key
  // Server uses "weather" for Source A and "earthquake" for Source B.
  // We also map Source C -> 'weather' and Source D -> 'earthquake' for test parity.
  String? _serverSourceKeyForDisplayName(String displayName) {
    final lower = displayName.toLowerCase();
    if (lower.contains('source a') || lower.contains('weather')) return 'weather';
    if (lower.contains('source b') || lower.contains('earthquake')) return 'earthquake';
    if (lower.contains('source c')) return 'weather'; // test source C behaves like A by default mapping
    if (lower.contains('source d')) return 'earthquake'; // test source D behaves like B by default mapping
    // If user renamed the source in settings, try to match by configured canonical key:
    if (_sourceSettings.containsKey('Source A') && (_sourceSettings['Source A']?['displayName'] ?? 'Source A') == displayName) return 'weather';
    if (_sourceSettings.containsKey('Source B') && (_sourceSettings['Source B']?['displayName'] ?? 'Source B') == displayName) return 'earthquake';
    if (_sourceSettings.containsKey('Source C') && (_sourceSettings['Source C']?['displayName'] ?? 'Source C') == displayName) return 'weather';
    if (_sourceSettings.containsKey('Source D') && (_sourceSettings['Source D']?['displayName'] ?? 'Source D') == displayName) return 'earthquake';
    return null;
  }

  // Helper to fetch latest socket payload for an event and optional source
  Map<String, dynamic>? _latestSocketPayload(String event, [String? sourceKey]) {
    if (sourceKey != null) {
      final key = '${event}_$sourceKey';
      if (_latestSocket.containsKey(key)) return _latestSocket[key];
    }
    if (_latestSocket.containsKey(event)) return _latestSocket[event];
    return null;
  }

  // Setup socket listeners (adds listeners for c1, c2, c3)
  void _setupSocketListeners() {
    try {
      final base = _isTestMode ? 'http://127.0.0.1:5000' : 'https://datawatchapp.com';
      // Use websocket transport for web compatibility
      _socket = IO.io(base, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket?.on('connect', (_) {
        // Connected
      });

      // c1: connection health (no source)
      _socket?.on('c1', (data) {
        try {
          if (data is Map) {
            _latestSocket['c1'] = Map<String, dynamic>.from(data as Map);
          } else if (data is String) {
            final parsed = jsonDecode(data);
            if (parsed is Map) _latestSocket['c1'] = Map<String, dynamic>.from(parsed);
          }
        } catch (_) {}
        if (mounted) setState(() {});
      });

      // c2: includes "source" field (e.g., "weather" or "earthquake")
      _socket?.on('c2', (data) {
        try {
          Map<String, dynamic>? payload;
          if (data is Map) payload = Map<String, dynamic>.from(data as Map);
          else if (data is String) {
            final parsed = jsonDecode(data);
            if (parsed is Map) payload = Map<String, dynamic>.from(parsed);
          }
          if (payload != null) {
            final src = (payload['source'] ?? '').toString();
            if (src.isNotEmpty) {
              _latestSocket['c2_$src'] = payload;
            } else {
              _latestSocket['c2'] = payload;
            }
          }
        } catch (_) {}
        if (mounted) setState(() {});
      });

      // c3: may include source similarly; handle generically
      _socket?.on('c3', (data) {
        try {
          Map<String, dynamic>? payload;
          if (data is Map) payload = Map<String, dynamic>.from(data as Map);
          else if (data is String) {
            final parsed = jsonDecode(data);
            if (parsed is Map) payload = Map<String, dynamic>.from(parsed);
          }
          if (payload != null) {
            final src = (payload['source'] ?? '').toString();
            if (src.isNotEmpty) {
              _latestSocket['c3_$src'] = payload;
            } else {
              _latestSocket['c3'] = payload;
            }
          }
        } catch (_) {}
        if (mounted) setState(() {});
      });

      _socket?.on('disconnect', (_) {
        // Disconnected
      });

      // Connect
      _socket?.connect();
    } catch (e) {
      // If socket setup fails, we silently continue; UI will show 'down' until socket data arrives.
    }
  }

  // -----------------------
  // 7) Data generation for sources (A/B backend via socket, C/D simulated via socket)
  // -----------------------
  String _normalizeStatus(dynamic s) {
    if (s == null) return 'down';
    final str = s.toString().toLowerCase();
    if (str.contains('ok')) return 'ok';
    if (str.contains('stale')) return 'stale';
    if (str.contains('warn')) return 'warning';
    if (str.contains('error')) return 'error';
    if (str.contains('down')) return 'down';
    return 'warning';
  }

  // R1: translate C1 into human sentences and a status
  Map<String, dynamic> _formatR1FromC1(String sourceName, Map<String, dynamic>? c1Json) {
    // Default
    final Map<String, String> c1 = {
      'database': _normalizeStatus(c1Json?['database']),
      'api': _normalizeStatus(c1Json?['api']),
      'socket': _normalizeStatus(c1Json?['socket']),
    };

    final List<String> lines = [];
    if (c1['database'] == 'ok') lines.add('Database connection for $sourceName is healthy.');
    if (c1['database'] == 'warning') lines.add('Database connection for $sourceName shows intermittent issues.');
    if (c1['database'] == 'error') lines.add('Database connection for $sourceName returned errors.');
    if (c1['database'] == 'down') lines.add('Database connection for $sourceName is down.');

    if (c1['api'] == 'ok') lines.add('API endpoint for $sourceName is responding normally.');
    if (c1['api'] == 'warning') lines.add('API endpoint for $sourceName is slow or returning warnings.');
    if (c1['api'] == 'error') lines.add('API endpoint for $sourceName returned errors.');
    if (c1['api'] == 'down') lines.add('API endpoint for $sourceName is unreachable.');

    if (c1['socket'] == 'ok') lines.add('Socket connection for $sourceName is active.');
    if (c1['socket'] == 'stale') lines.add('Socket connection for $sourceName appears stale.');
    if (c1['socket'] == 'warning') lines.add('Socket connection for $sourceName shows warnings.');
    if (c1['socket'] == 'down') lines.add('Socket connection for $sourceName is down.');

    final String combined = lines.isEmpty ? 'No connection issues detected for $sourceName.' : lines.join('\n');
    final String status = _mirrorFromC1(c1);
    return {'status': status, 'text': combined};
  }

  // R2: translate C2 and C3 into human sentences and a status (source-aware)
  Map<String, dynamic> _formatR2FromC2C3(String sourceName, Map<String, dynamic>? c2Json, Map<String, dynamic>? c3Json) {
    final List<String> lines = [];
    String status = 'ok';

    // Interpret C2 (CRUD/movement)
    if (c2Json != null) {
      // If server sends 'status' use it; otherwise infer from fields
      String raw = '';
      if (c2Json.containsKey('status')) raw = c2Json['status'].toString();
      else if (c2Json.containsKey('success')) raw = (c2Json['success'] is num && (c2Json['success'] as num) > 0) ? 'ok' : 'warning';
      else if (c2Json.containsKey('read') || c2Json.containsKey('create')) raw = 'ok';
      else raw = 'warning';

      final s = _normalizeStatus(raw);
      if (s == 'ok') lines.add('Data movement (CRUD) for $sourceName is operating normally.');
      if (s == 'warning') lines.add('Data movement (CRUD) for $sourceName shows partial success or warnings.');
      if (s == 'error') lines.add('Data movement (CRUD) for $sourceName encountered errors.');
      if (s == 'down') lines.add('Data movement (CRUD) for $sourceName is down.');
      if (s == 'down' || s == 'error') status = s;
      if (s == 'warning' && status != 'error' && status != 'down') status = 'warning';
    } else {
      lines.add('No data movement (C2) information available for $sourceName.');
      status = 'down';
    }

    // Interpret C3 (validation / data)
    if (c3Json != null) {
      final dataStatus = _normalizeStatus(c3Json['data']);
      final varianceStatus = _normalizeStatus(c3Json['variance']);

      if (dataStatus == 'ok') {
        // Try to extract a value for a more informative sentence
        if (c3Json.containsKey('value') && (c3Json['value'] is num)) {
          lines.add('Latest reported value for $sourceName is ${c3Json['value']}.');
        } else if (c3Json.containsKey('magnitude') && (c3Json['magnitude'] is num)) {
          lines.add('Latest magnitude for $sourceName is ${c3Json['magnitude']}.');
        } else if (c3Json.containsKey('temperature') && (c3Json['temperature'] is num)) {
          lines.add('Latest temperature for $sourceName is ${c3Json['temperature']}°.');
        } else {
          lines.add('Data validation for $sourceName indicates data is present and valid.');
        }
      } else if (dataStatus == 'warning') {
        lines.add('Data for $sourceName is present but shows potential issues.');
      } else if (dataStatus == 'down') {
        lines.add('No recent data available for $sourceName.');
      }

      if (varianceStatus == 'warning') {
        lines.add('Data variance for $sourceName exceeds configured thresholds.');
        if (status != 'error' && status != 'down') status = 'warning';
      }
      if (varianceStatus == 'error' || varianceStatus == 'down') status = varianceStatus;
    } else {
      lines.add('No data validation (C3) information available for $sourceName.');
      if (status != 'error') status = 'warning';
    }

    final String combined = lines.join('\n');
    return {'status': status, 'text': combined};
  }

  // R3: combine R1 and R2
  Map<String, dynamic> _combineReports(Map<String, dynamic> r1, Map<String, dynamic> r2) {
    final String status = _combineReportStatus(r1['status'] as String? ?? 'down', r2['status'] as String? ?? 'down');
    final String text = 'R1 (Connections):\n${r1['text']}\n\nR2 (CRUD + Validation):\n${r2['text']}\n\nCombined status: ${status.toUpperCase()}';
    return {'status': status, 'text': text};
  }

  Future<void> _generateData() async {
    final now = DateTime.now();
    final prev = oldSnapshot ?? {};
    List<Map<String, dynamic>> newSources = [];

    void _markProgressStart(String name) {
      _progressStart[name] = DateTime.now();
      Future.delayed(const Duration(seconds: PROGRESS_ANIMATION_SECONDS + 1), () {
        if (mounted) setState(() {});
      });
    }

    // Source A (backend) - prefer socket payloads
    {
      final name = _sourceSettings.containsKey('Source A') && _sourceSettings['Source A']!.containsKey('displayName')
          ? _sourceSettings['Source A']!['displayName'] as String
          : 'Source A';

      final serverKeyA = _serverSourceKeyForDisplayName(name); // 'weather' expected
      final c1Json = _latestSocketPayload('c1'); // c1 is global
      final c2Json = serverKeyA != null ? _latestSocketPayload('c2', serverKeyA) : _latestSocketPayload('c2');
      final c3Json = serverKeyA != null ? _latestSocketPayload('c3', serverKeyA) : _latestSocketPayload('c3');

      final c1 = {
        'database': _normalizeStatus(c1Json?['database']),
        'api': _normalizeStatus(c1Json?['api']),
        'socket': _normalizeStatus(c1Json?['socket']),
      };

      // Map c2 to a simple status for UI
      String c2StatusRaw = 'down';
      if (c2Json != null) {
        if (c2Json.containsKey('status')) c2StatusRaw = c2Json['status'].toString();
        else if (c2Json.containsKey('success') && (c2Json['success'] is num || c2Json['success'] is String)) {
          final val = c2Json['success'];
          if ((val is num && val > 0) || (val is String && val.toLowerCase() == 'true')) c2StatusRaw = 'ok';
          else c2StatusRaw = 'warning';
        } else if (c2Json.containsKey('read') || c2Json.containsKey('create')) {
          c2StatusRaw = 'ok';
        } else {
          c2StatusRaw = 'warning';
        }
      }
      final c2 = {'status': _normalizeStatus(c2StatusRaw)};

      final c3 = {
        'data': _normalizeStatus(c3Json?['data']),
        'variance': _normalizeStatus(c3Json?['variance']),
      };

      // Build R1 and R2 from socket-derived C1/C2/C3
      final r1 = _formatR1FromC1(name, c1Json);
      final r2 = _formatR2FromC2C3(name, c2Json, c3Json);
      final r3 = _combineReports(r1, r2);

      final connKey = _aggregateConnectionButtonStatus(c1, c2, c3);
      final repKey = r3['status'] as String;

      final connDetails = _humanCDetails(c1, c2, c3);
      final repDetails = r3['text'] as String;

      final tsIso = now.toIso8601String();
      _markProgressStart(name);

      newSources.add({
        'name': name,
        'connectionKey': connKey,
        'reportKey': repKey,
        'connectionIcon': _iconForKey(connKey),
        'reportIcon': _iconForKey(repKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': tsIso,
        'lastRepUpdated': tsIso,
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': _sourceSettings['Source A']?['staleMinutesConn'] ?? DEFAULT_STALE_MINUTES_CONN,
        'staleMinutesRep': _sourceSettings['Source A']?['staleMinutesRep'] ?? DEFAULT_STALE_MINUTES_REP,
        'variancePercent': _sourceSettings['Source A']?['variancePercent'] ?? DEFAULT_VARIANCE_PERCENT,
        'reportDueHour': _sourceSettings['Source A']?['reportDueHour'] ?? 0,
        'reportDueMinute': _sourceSettings['Source A']?['reportDueMinute'] ?? 0,
        'reportValue': c3Json?['value'] ?? c3Json?['temperature'] ?? null,
        'C1': c1,
        'C2': c2,
        'C3': c3,
        'R1': {'status': r1['status'], 'details': r1['text']},
        'R2': {'status': r2['status'], 'details': r2['text']},
        'R3': {'status': r3['status'], 'generatedAt': tsIso, 'details': r3['text']},
      });
    }

    // Source B (backend) - prefer socket payloads
    {
      final name = _sourceSettings.containsKey('Source B') && _sourceSettings['Source B']!.containsKey('displayName')
          ? _sourceSettings['Source B']!['displayName'] as String
          : 'Source B';

      final serverKeyB = _serverSourceKeyForDisplayName(name); // 'earthquake' expected
      final c1Json = _latestSocketPayload('c1'); // c1 is global
      final c2Json = serverKeyB != null ? _latestSocketPayload('c2', serverKeyB) : _latestSocketPayload('c2');
      final c3Json = serverKeyB != null ? _latestSocketPayload('c3', serverKeyB) : _latestSocketPayload('c3');

      final c1 = {
        'database': _normalizeStatus(c1Json?['database']),
        'api': _normalizeStatus(c1Json?['api']),
        'socket': _normalizeStatus(c1Json?['socket']),
      };

      String c2StatusRaw = 'down';
      if (c2Json != null) {
        if (c2Json.containsKey('status')) c2StatusRaw = c2Json['status'].toString();
        else if (c2Json.containsKey('success') && (c2Json['success'] is num || c2Json['success'] is String)) {
          final val = c2Json['success'];
          if ((val is num && val > 0) || (val is String && val.toLowerCase() == 'true')) c2StatusRaw = 'ok';
          else c2StatusRaw = 'warning';
        } else if (c2Json.containsKey('read') || c2Json.containsKey('create')) {
          c2StatusRaw = 'ok';
        } else {
          c2StatusRaw = 'warning';
        }
      }
      final c2 = {'status': _normalizeStatus(c2StatusRaw)};

      final c3 = {
        'data': _normalizeStatus(c3Json?['data']),
        'variance': _normalizeStatus(c3Json?['variance']),
      };

      final r1 = _formatR1FromC1(name, c1Json);
      final r2 = _formatR2FromC2C3(name, c2Json, c3Json);
      final r3 = _combineReports(r1, r2);

      final connKey = _aggregateConnectionButtonStatus(c1, c2, c3);
      final repKey = r3['status'] as String;

      final connDetails = _humanCDetails(c1, c2, c3);
      final repDetails = r3['text'] as String;

      final tsIso = now.toIso8601String();
      _markProgressStart(name);

      newSources.add({
        'name': name,
        'connectionKey': connKey,
        'reportKey': repKey,
        'connectionIcon': _iconForKey(connKey),
        'reportIcon': _iconForKey(repKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': tsIso,
        'lastRepUpdated': tsIso,
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': _sourceSettings['Source B']?['staleMinutesConn'] ?? DEFAULT_STALE_MINUTES_CONN,
        'staleMinutesRep': _sourceSettings['Source B']?['staleMinutesRep'] ?? DEFAULT_STALE_MINUTES_REP,
        'variancePercent': _sourceSettings['Source B']?['variancePercent'] ?? DEFAULT_VARIANCE_PERCENT,
        'reportDueHour': _sourceSettings['Source B']?['reportDueHour'] ?? 0,
        'reportDueMinute': _sourceSettings['Source B']?['reportDueMinute'] ?? 0,
        'reportValue': c3Json?['value'] ?? c3Json?['magnitude'] ?? null,
        'C1': c1,
        'C2': c2,
        'C3': c3,
        'R1': {'status': r1['status'], 'details': r1['text']},
        'R2': {'status': r2['status'], 'details': r2['text']},
        'R3': {'status': r3['status'], 'generatedAt': tsIso, 'details': r3['text']},
      });
    }

    // Source C (Open-Meteo simulation) - simulate normal flow with occasional anomalies
    {
      final name = _sourceSettings.containsKey('Source C') && _sourceSettings['Source C']!.containsKey('displayName')
          ? _sourceSettings['Source C']!['displayName'] as String
          : 'Source C';

      // Try to use socket payload if present for weather, but primary behavior is simulated
      final socketC2 = _latestSocketPayload('c2', 'weather');
      final socketC3 = _latestSocketPayload('c3', 'weather');

      // Base simulated temperature (Celsius) and small random walk
      double baseTemp = 18.0 + (_rng.nextDouble() * 10.0); // 18..28 typical
      // If previous snapshot had a value, nudge from it to make smooth transitions
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null;
      if (prevValue != null) {
        // small step toward baseTemp
        baseTemp = prevValue + (_rng.nextDouble() - 0.5) * 1.5;
      }

      // Occasionally inject anomalies: low probability for error/down/warning
      final anomalyRoll = _rng.nextDouble();
      String dataStatus = 'ok';
      String varianceStatus = 'ok';
      double? reportedTemp = double.parse(baseTemp.toStringAsFixed(1));

      if (anomalyRoll < 0.02) {
        // 2% chance of down (no data)
        dataStatus = 'down';
        reportedTemp = null;
      } else if (anomalyRoll < 0.08) {
        // 6% chance of warning (high variance or odd reading)
        dataStatus = 'warning';
        // produce an outlier
        reportedTemp = double.parse((baseTemp + (_rng.nextBool() ? 8.0 : -8.0)).toStringAsFixed(1));
        varianceStatus = 'warning';
      } else if (anomalyRoll < 0.12) {
        // 4% chance of error (bad payload)
        dataStatus = 'error';
        reportedTemp = null;
      } else {
        // Normal flow: small jitter
        reportedTemp = double.parse((baseTemp + (_rng.nextDouble() - 0.5) * 0.8).toStringAsFixed(1));
        // small chance of variance warning if change from prev is large
        if (prevValue != null) {
          final diff = (reportedTemp - prevValue).abs();
          if (prevValue != 0 && (diff / prevValue * 100.0) > (_sourceSettings['Source C']?['variancePercent'] ?? DEFAULT_VARIANCE_PERCENT)) {
            varianceStatus = 'warning';
          }
        }
      }

      // Build C1: simulate connection health; prefer global c1 if present
      final globalC1 = _latestSocketPayload('c1');
      String dbStatus = 'ok';
      String apiStatus = 'ok';
      String socketStatus = 'ok';
      if (globalC1 != null) {
        dbStatus = _normalizeStatus(globalC1['database']);
        apiStatus = _normalizeStatus(globalC1['api']);
        socketStatus = _normalizeStatus(globalC1['socket']);
      } else {
        // simulate occasional connection blips
        final connRoll = _rng.nextDouble();
        if (connRoll < 0.01) {
          dbStatus = 'down';
          apiStatus = 'down';
          socketStatus = 'down';
        } else if (connRoll < 0.05) {
          apiStatus = 'warning';
          socketStatus = 'stale';
        }
      }

      final c1 = {'database': dbStatus, 'api': apiStatus, 'socket': socketStatus};
      final c2 = {
        // c2 for Open-Meteo is movement/CRUD; simulate reads/creates
        'status': dataStatus == 'ok' ? (_rng.nextDouble() < 0.95 ? 'ok' : 'warning') : dataStatus,
        'read': socketC2?['read'] ?? (10 + _rng.nextInt(5)),
        'create': socketC2?['create'] ?? (1 + _rng.nextInt(3)),
        'success': socketC2?['success'] ?? (1 + _rng.nextInt(3)),
      };
      final c3 = {'data': dataStatus, 'variance': varianceStatus, 'temperature': reportedTemp, 'value': reportedTemp};

      final r1 = _formatR1FromC1(name, c1);
      final r2 = _formatR2FromC2C3(name, c2, c3);
      final r3 = _combineReports(r1, r2);

      final connKey = _aggregateConnectionButtonStatus(Map<String, String>.from(c1), {'status': c2['status']}, Map<String, String>.from({'data': c3['data'], 'variance': c3['variance']}));
      final repKey = r3['status'] as String;

      final connDetails = _humanCDetails(Map<String, String>.from(c1), Map<String, String>.from({'status': c2['status']}), Map<String, String>.from({'data': c3['data'], 'variance': c3['variance']}));
      final repDetails = r3['text'] as String;

      final tsIso = now.toIso8601String();
      _markProgressStart(name);

      newSources.add({
        'name': name,
        'connectionKey': connKey,
        'reportKey': repKey,
        'connectionIcon': _iconForKey(connKey),
        'reportIcon': _iconForKey(repKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': tsIso,
        'lastRepUpdated': tsIso,
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': _sourceSettings['Source C']?['staleMinutesConn'] ?? DEFAULT_STALE_MINUTES_CONN,
        'staleMinutesRep': _sourceSettings['Source C']?['staleMinutesRep'] ?? DEFAULT_STALE_MINUTES_REP,
        'variancePercent': _sourceSettings['Source C']?['variancePercent'] ?? DEFAULT_VARIANCE_PERCENT,
        'reportDueHour': _sourceSettings['Source C']?['reportDueHour'] ?? 0,
        'reportDueMinute': _sourceSettings['Source C']?['reportDueMinute'] ?? 0,
        'reportValue': c3['value'],
        'C1': c1,
        'C2': {'status': c2['status']},
        'C3': {'data': c3['data'], 'variance': c3['variance']},
        'R1': {'status': r1['status'], 'details': r1['text']},
        'R2': {'status': r2['status'], 'details': r2['text']},
        'R3': {'status': r3['status'], 'generatedAt': tsIso, 'details': r3['text']},
      });
    }

    // Source D (USGS simulation) - simulate earthquake feed with occasional events and sensible statuses
    {
      final name = _sourceSettings.containsKey('Source D') && _sourceSettings['Source D']!.containsKey('displayName')
          ? _sourceSettings['Source D']!['displayName'] as String
          : 'Source D';

      // Try to use socket payload if present for earthquake, but primary behavior is simulated
      final socketD2 = _latestSocketPayload('c2', 'earthquake');
      final socketD3 = _latestSocketPayload('c3', 'earthquake');

      // Simulate typical small magnitudes most of the time, occasional larger events
      double magnitude;
      final eventRoll = _rng.nextDouble();
      if (eventRoll < 0.01) {
        // rare larger quake
        magnitude = double.parse((4.0 + _rng.nextDouble() * 3.0).toStringAsFixed(1)); // 4.0 - 7.0
      } else if (eventRoll < 0.08) {
        // small but noticeable
        magnitude = double.parse((2.5 + _rng.nextDouble() * 1.5).toStringAsFixed(1)); // 2.5 - 4.0
      } else {
        // background microquakes
        magnitude = double.parse((0.5 + _rng.nextDouble() * 1.5).toStringAsFixed(1)); // 0.5 - 2.0
      }

      // Occasionally simulate missing data or errors
      final anomalyRoll = _rng.nextDouble();
      String dataStatus = 'ok';
      String varianceStatus = 'ok';
      double? reportedMag = magnitude;
      if (anomalyRoll < 0.03) {
        // 3% chance of down
        dataStatus = 'down';
        reportedMag = null;
      } else if (anomalyRoll < 0.09) {
        // 6% chance of warning (inconsistent readings)
        dataStatus = 'warning';
        varianceStatus = 'warning';
        // jitter magnitude
        reportedMag = double.parse((magnitude + (_rng.nextDouble() - 0.5) * 1.5).toStringAsFixed(1));
      } else if (anomalyRoll < 0.12) {
        // 3% chance of error
        dataStatus = 'error';
        reportedMag = null;
      }

      // Build C1: prefer global c1 if present
      final globalC1 = _latestSocketPayload('c1');
      String dbStatus = 'ok';
      String apiStatus = 'ok';
      String socketStatus = 'ok';
      if (globalC1 != null) {
        dbStatus = _normalizeStatus(globalC1['database']);
        apiStatus = _normalizeStatus(globalC1['api']);
        socketStatus = _normalizeStatus(globalC1['socket']);
      } else {
        final connRoll = _rng.nextDouble();
        if (connRoll < 0.02) {
          dbStatus = 'down';
          apiStatus = 'down';
          socketStatus = 'down';
        } else if (connRoll < 0.06) {
          apiStatus = 'warning';
          socketStatus = 'stale';
        }
      }

      final c1 = {'database': dbStatus, 'api': apiStatus, 'socket': socketStatus};
      final c2 = {
        'status': dataStatus == 'ok' ? (_rng.nextDouble() < 0.9 ? 'ok' : 'warning') : dataStatus,
        'read': socketD2?['read'] ?? (5 + _rng.nextInt(8)),
        'create': socketD2?['create'] ?? (0 + _rng.nextInt(2)),
        'success': socketD2?['success'] ?? (1 + _rng.nextInt(2)),
      };
      final c3 = {'data': dataStatus, 'variance': varianceStatus, 'magnitude': reportedMag, 'value': reportedMag};

      final r1 = _formatR1FromC1(name, c1);
      final r2 = _formatR2FromC2C3(name, c2, c3);
      final r3 = _combineReports(r1, r2);

      final connKey = _aggregateConnectionButtonStatus(Map<String, String>.from(c1), {'status': c2['status']}, Map<String, String>.from({'data': c3['data'], 'variance': c3['variance']}));
      final repKey = r3['status'] as String;

      final connDetails = _humanCDetails(Map<String, String>.from(c1), Map<String, String>.from({'status': c2['status']}), Map<String, String>.from({'data': c3['data'], 'variance': c3['variance']}));
      final repDetails = r3['text'] as String;

      final tsIso = now.toIso8601String();
      _markProgressStart(name);

      newSources.add({
        'name': name,
        'connectionKey': connKey,
        'reportKey': repKey,
        'connectionIcon': _iconForKey(connKey),
        'reportIcon': _iconForKey(repKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': tsIso,
        'lastRepUpdated': tsIso,
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': _sourceSettings['Source D']?['staleMinutesConn'] ?? DEFAULT_STALE_MINUTES_CONN,
        'staleMinutesRep': _sourceSettings['Source D']?['staleMinutesRep'] ?? DEFAULT_STALE_MINUTES_REP,
        'variancePercent': _sourceSettings['Source D']?['variancePercent'] ?? DEFAULT_VARIANCE_PERCENT,
        'reportDueHour': _sourceSettings['Source D']?['reportDueHour'] ?? 0,
        'reportDueMinute': _sourceSettings['Source D']?['reportDueMinute'] ?? 0,
        'reportValue': c3['value'],
        'C1': c1,
        'C2': {'status': c2['status']},
        'C3': {'data': c3['data'], 'variance': c3['variance']},
        'R1': {'status': r1['status'], 'details': r1['text']},
        'R2': {'status': r2['status'], 'details': r2['text']},
        'R3': {'status': r3['status'], 'generatedAt': tsIso, 'details': r3['text']},
      });
    }

    sources = newSources;
  }

  // -----------------------
  // 8) Status aggregation and formatting helpers
  // -----------------------
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
    final palette = _paletteForMode(_colorMode);
    final hex = palette[k] ?? palette['ok']!;
    return Color(int.parse(hex.replaceFirst('#', '0xff')));
  }

  String _prettyJson(Object? jsonObj) {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      if (jsonObj is String) {
        final decoded = jsonDecode(jsonObj);
        return encoder.convert(decoded);
      } else {
        return encoder.convert(jsonObj ?? {});
      }
    } catch (_) {
      return jsonObj?.toString() ?? '';
    }
  }

  double _computeProgressToStale(String? lastIso, int staleMinutes, String name) {
    final now = DateTime.now();
    double animationPart = 0.0;
    if (_progressStart.containsKey(name)) {
      final start = _progressStart[name]!;
      final elapsedAnim = now.difference(start).inSeconds;
      animationPart = (elapsedAnim / PROGRESS_ANIMATION_SECONDS).clamp(0.0, 1.0);
    }
    double agingPart = 1.0;
    if (lastIso != null) {
      final dt = DateTime.tryParse(lastIso);
      if (dt != null) {
        final elapsed = now.difference(dt).inSeconds;
        final cap = max(1, staleMinutes * 60);
        agingPart = (elapsed / cap).clamp(0.0, 1.0);
      }
    }
    if (animationPart < 1.0) {
      return (0.7 * animationPart + 0.3 * agingPart).clamp(0.0, 1.0);
    } else {
      return agingPart;
    }
  }

  String _aggregateConnectionButtonStatus(Map<String, String> c1, Map<String, String> c2, Map<String, String> c3) {
    final statuses = <String>{
      c1['database'] ?? 'down',
      c1['api'] ?? 'down',
      c1['socket'] ?? 'down',
      c2['status'] ?? 'down',
      c3['data'] ?? 'down',
      c3['variance'] ?? 'down',
    };
    if ((c3['data'] == 'stale') || (c3['variance'] == 'stale')) return 'stale';
    if (statuses.length == 1) return statuses.first;
    return 'warning';
  }

  String _mirrorFromC1(Map<String, String> c1) {
    final set = {c1['database'], c1['api'], c1['socket']};
    if (set.contains('down')) return 'down';
    if (set.contains('error')) return 'error';
    if (set.contains('warning')) return 'warning';
    if (set.contains('stale')) return 'stale';
    return 'ok';
  }

  String _mirrorFromC2(Map<String, String> c2) => c2['status'] ?? 'down';

  String _combineReportStatus(String r1, String r2) {
    if (r1 == 'down' || r2 == 'down') return 'down';
    if (r1 == 'error' || r2 == 'error') return 'error';
    if (r1 == 'warning' || r2 == 'warning') return 'warning';
    if (r1 == 'stale' || r2 == 'stale') return 'stale';
    return 'ok';
  }

  String _humanCDetails(Map<String, String> c1, Map<String, String> c2, Map<String, String> c3) {
    final b1 = 'C1 (Connections)\n  Database: ${c1['database']}\n  API: ${c1['api']}\n  Socket: ${c1['socket']}';
    final b2 = 'C2 (Movement/CRUD)\n  Status: ${c2['status']}';
    final b3 = 'C3 (Validation)\n  Data: ${c3['data']}\n  Variance: ${c3['variance']}';
    return '$b1\n$b2\n$b3';
  }

  String _buildR1Details(String sourceName, Map<String, String> c1) {
    final lines = <String>[];
    if (c1['database'] == 'down') lines.add('Database connection for $sourceName is down.');
    if (c1['database'] == 'error') lines.add('Database connection for $sourceName returned an error.');
    if (c1['api'] == 'down') lines.add('API connection for $sourceName is down.');
    if (c1['api'] == 'error') lines.add('API connection for $sourceName returned an error.');
    if (c1['socket'] == 'down') lines.add('Socket connection for $sourceName is down.');
    if (c1['socket'] == 'error') lines.add('Socket connection for $sourceName returned an error.');
    if (lines.isEmpty) lines.add('Connections healthy for $sourceName.');
    return lines.join('\n');
  }

  String _buildR2Details(String sourceName, Map<String, String> c2) {
    final s = c2['status'];
    if (s == 'down') return 'Data movement (CRUD) for $sourceName is down.';
    if (s == 'error') return 'Data movement (CRUD) for $sourceName encountered an error.';
    if (s == 'warning') return 'Data movement (CRUD) for $sourceName shows partial success.';
    if (s == 'stale') return 'Data movement (CRUD) for $sourceName appears stale.';
    return 'Data movement (CRUD) healthy for $sourceName.';
  }

  String _humanRDetails(String r1Details, String r2Details, String r3Status) {
    return 'R1 (Connections Report)\n  ${r1Details.replaceAll('\n', '\n  ')}\n'
           'R2 (Movement Report)\n  ${r2Details}\n'
           'R3 (Combined)\n  Status: $r3Status';
  }

  // -----------------------
  // 9) UI building (AppBar, list, dialogs)
  // -----------------------
  Widget _buildLogoBrandButton() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isPhone = screenWidth <= 600.0;

    final double containerHeight = isPhone ? 32 : 48;
    final double logoSize = isPhone ? 56 : 72;

    final palette = _paletteForMode(_colorMode);
    final navBorderHex = palette['navBorder'] ?? '#000000';
    final navBarBorderColor = Color(int.parse(navBorderHex.replaceFirst('#', '0xff')));

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()));
      },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        height: containerHeight,
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: navBarBorderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: logoSize,
              width: logoSize,
              child: ColorFiltered(
                colorFilter: _colorFilterForMode(_colorMode),
                child: Image.asset(
                  'assets/nav_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, size: 32),
                ),
              ),
            ),
            if (!isPhone) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Data Watch',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(int.parse((_paletteForMode(_colorMode)['text'] ?? '#000000').replaceFirst('#', '0xff'))),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Implement build(BuildContext) to satisfy abstract State requirement
    final palette = _paletteForMode(_colorMode);
    final navHex = palette['nav'] ?? '#1976d2';
    final navColor = Color(int.parse(navHex.replaceFirst('#', '0xff')));

    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        leadingWidth: 56,
        toolbarHeight: 56,
        title: _buildLogoBrandButton(),
        backgroundColor: navColor,
        actions: [
          LayoutBuilder(
            builder: (context, constraints) {
              final double screenWidth = MediaQuery.of(context).size.width;
              final bool isPhone = screenWidth <= 600.0;
              const topRightColor = Colors.white;

              if (!isPhone && constraints.maxWidth > 700) {
                return Row(children: [
                  TextButton(
                    onPressed: () {
                      final errors = _currentErrorsFromSources();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ErrorPage(entries: errors, persistedErrors: _errorLog)));
                    },
                    child: const Text('Errors', style: TextStyle(color: topRightColor)),
                  ),
                  TextButton(
                    onPressed: () {
                      final logs = _currentLogFromSources();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => LogPage(entries: logs, persistedLogs: _dailyLog)));
                    },
                    child: const Text('Log', style: TextStyle(color: topRightColor)),
                  ),
                  IconButton(icon: const Icon(Icons.settings, color: topRightColor), tooltip: 'Settings', onPressed: () => _openGlobalSettings(context)),
                  IconButton(onPressed: () async => await _clearPersistedAll(), icon: const Icon(Icons.delete_sweep, color: topRightColor), tooltip: 'Clear persisted snapshot and logs'),
                  IconButton(onPressed: _logout, icon: const Icon(Icons.logout, color: topRightColor), tooltip: 'Logout'),
                ]);
              } else {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: topRightColor),
                  onSelected: (value) async {
                    if (value == 'Errors') {
                      final errors = _currentErrorsFromSources();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ErrorPage(entries: errors, persistedErrors: _errorLog)));
                    } else if (value == 'Log') {
                      final logs = _currentLogFromSources();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => LogPage(entries: logs, persistedLogs: _dailyLog)));
                    } else if (value == 'Settings') {
                      _openGlobalSettings(context);
                    } else if (value == 'Clear') {
                      await _clearPersistedAll();
                    } else if (value == 'Logout') {
                      await _logout();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'Errors', child: Text('Errors')),
                    PopupMenuItem(value: 'Log', child: Text('Log')),
                    PopupMenuItem(value: 'Settings', child: Text('Settings')),
                    PopupMenuItem(value: 'Clear', child: Text('Clear Data')),
                    PopupMenuItem(value: 'Logout', child: Text('Logout')),
                  ],
                );
              }
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth >= 800;
          final double widthFactor = isWide ? 0.75 : 0.95;

          return Center(
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('Data Source Status', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Color(int.parse((palette['navBorder'] ?? '#000000').replaceFirst('#', '0xff'))), width: 1.2),
                        borderRadius: BorderRadius.circular(8),
                        color: Color(int.parse((palette['bg'] ?? '#ffffff').replaceFirst('#', '0xff'))),
                      ),
                      child: Column(children: [
                        // Top labels row: empty left column, Connection, Report
                        Row(children: [
                          SizedBox(width: 140, child: Text('', style: TextStyle(fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff')))))),
                          Expanded(child: Center(child: Text('Connection', style: TextStyle(fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))))),
                          Expanded(child: Center(child: Text('Report', style: TextStyle(fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))))),
                        ]),
                        // Sub-labels row that maps the three small bars to C1/C2/C3 and R1/R2/R3
                        const SizedBox(height: 6),
                        Row(children: [
                          SizedBox(width: 140, child: Text('', style: labelStyle)),
                          // Connection labels (C1 C2 C3)
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(child: Center(child: Text('C1', style: labelStyle))),
                                const SizedBox(width: 4),
                                Expanded(child: Center(child: Text('C2', style: labelStyle))),
                                const SizedBox(width: 4),
                                Expanded(child: Center(child: Text('C3', style: labelStyle))),
                              ],
                            ),
                          ),
                          // Report labels (R1 R2 R3)
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(child: Center(child: Text('R1', style: labelStyle))),
                                const SizedBox(width: 4),
                                Expanded(child: Center(child: Text('R2', style: labelStyle))),
                                const SizedBox(width: 4),
                                Expanded(child: Center(child: Text('R3', style: labelStyle))),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
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
                              final lastConn = s['lastConnUpdated'] as String?;
                              final lastRep = s['lastRepUpdated'] as String?;
                              final isUpdConn = s['isUpdatingConn'] as bool? ?? false;
                              final isUpdRep = s['isUpdatingRep'] as bool? ?? false;

                              final c1 = Map<String, String>.from((s['C1'] as Map));
                              final c2 = Map<String, String>.from((s['C2'] as Map));
                              final c3 = Map<String, String>.from((s['C3'] as Map));
                              final r1 = Map<String, dynamic>.from((s['R1'] as Map));
                              final r2 = Map<String, dynamic>.from((s['R2'] as Map));
                              final r3 = Map<String, dynamic>.from((s['R3'] as Map));

                              final r1Status = (r1['status'] ?? repKey).toString();
                              final r2Status = (r2['status'] ?? repKey).toString();
                              final r3Status = (r3['status'] ?? repKey).toString();

                              double pickOpacity(String key) {
                                if (key == 'ok' || key == 'warning' || key == 'stale') return 1.0;
                                return 0.25;
                              }

                              Widget _buildThreeBarsForButton(String a, String b, String c) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: _colorForKey(a).withOpacity(pickOpacity(a)),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: _colorForKey(b).withOpacity(pickOpacity(b)),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: _colorForKey(c).withOpacity(pickOpacity(c)),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(children: [
                                Row(children: [
                                  SizedBox(
                                    width: 140,
                                    child: Row(children: [
                                      Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff')))))),
                                      IconButton(
                                        icon: Icon(Icons.settings, size: 18, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff')))),
                                        tooltip: 'Source settings',
                                        onPressed: () => _openPerSourceSettings(context, name),
                                      ),
                                    ]),
                                  ),

                                  // Connection column
                                  Expanded(
                                    child: Column(children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: _buildThreeBarsForButton(
                                          c1['database'] ?? connKey,
                                          c1['api'] ?? connKey,
                                          c1['socket'] ?? connKey,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(int.parse((palette['bgButton'] ?? '#ffffff').replaceFirst('#', '0xff'))),
                                          foregroundColor: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))),
                                          side: BorderSide(color: Color(int.parse((palette['buttonBorder'] ?? '#000000').replaceFirst('#', '0xff')))),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                        onPressed: () {
                                          final pretty = _humanCDetails(c1, c2, c3);
                                          _showDetailsDialog(context, '$name - Connection', pretty, connKey, lastConn, isUpdConn);
                                        },
                                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Icon(connIcon, color: _colorForKey(connKey)),
                                          const SizedBox(width: 8),
                                          Text(connKey.toUpperCase(), style: TextStyle(color: _colorForKey(connKey), fontSize: MediaQuery.of(context).size.width <= 600 ? 11 : 14)),
                                        ]),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${_formatTime(lastConn)} ${isUpdConn ? " • Updating..." : ""}', style: TextStyle(fontSize: 12, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))),
                                    ]),
                                  ),

                                  const SizedBox(width: 8),

                                  // Report column
                                  Expanded(
                                    child: Column(children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: _buildThreeBarsForButton(r1Status, r2Status, r3Status),
                                      ),
                                      const SizedBox(height: 6),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(int.parse((palette['bgButton'] ?? '#ffffff').replaceFirst('#', '0xff'))),
                                          foregroundColor: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))),
                                          side: BorderSide(color: Color(int.parse((palette['buttonBorder'] ?? '#000000').replaceFirst('#', '0xff')))),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                        onPressed: () {
                                          // Show selection dialog to pick R1, R2, or R3
                                          _showReportSelection(
                                            context,
                                            name,
                                            (s['R1'] as Map)['details']?.toString() ?? '',
                                            (s['R2'] as Map)['details']?.toString() ?? '',
                                            (s['R3'] as Map)['details']?.toString() ?? '',
                                            (s['R1'] as Map)['status']?.toString() ?? 'down',
                                            (s['R2'] as Map)['status']?.toString() ?? 'down',
                                            (s['R3'] as Map)['status']?.toString() ?? 'down',
                                          );
                                        },
                                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Icon(repIcon, color: _colorForKey(repKey)),
                                          const SizedBox(width: 8),
                                          Text(repKey.toUpperCase(), style: TextStyle(color: _colorForKey(repKey), fontSize: MediaQuery.of(context).size.width <= 600 ? 11 : 14)),
                                        ]),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${_formatTime(lastRep)} ${isUpdRep ? " • Updating..." : ""}', style: TextStyle(fontSize: 12, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))),
                                    ]),
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
            ),
          );
        },
      ),
    );
  }

  // NEW: Report selection dialog and display
  void _showReportSelection(BuildContext context, String sourceName, String r1Text, String r2Text, String r3Text, String r1Status, String r2Status, String r3Status) {
    showDialog(
      context: context,
      builder: (_) {
        return SimpleDialog(
          title: Text('$sourceName - Choose report'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                _showSingleReport(context, '$sourceName - R1 (Connections)', r1Text, r1Status);
              },
              child: const Text('R1 — Connections'),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                _showSingleReport(context, '$sourceName - R2 (CRUD + Validation)', r2Text, r2Status);
              },
              child: const Text('R2 — CRUD + Data Validation'),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                _showSingleReport(context, '$sourceName - R3 (Combined)', r3Text, r3Status);
              },
              child: const Text('R3 — Combined Report'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showSingleReport(BuildContext context, String title, String content, String status) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [Text(title), const Spacer(), Text(status.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(content, minLines: 6),
            const SizedBox(height: 12),
            const Text('You can copy the report text to your clipboard using the Copy button.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          TextButton(onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied to clipboard')));
          }, child: const Text('Copy')),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final palette = _paletteForMode(_colorMode);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Color(int.parse((palette['navBorder'] ?? '#000000').replaceFirst('#', '0xff'))), width: 1.2),
        borderRadius: BorderRadius.circular(8),
        color: Color(int.parse((palette['bg'] ?? '#ffffff').replaceFirst('#', '0xff'))),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _legendItem(Icons.check, 'OK', _colorForKey('ok')),
        _legendItem(Icons.more_horiz, 'Stale', _colorForKey('stale')),
        _legendItem(Icons.cloud_off, 'Down', _colorForKey('down')),
        _legendItem(Icons.warning, 'Warning', _colorForKey('warning')),
        _legendItem(Icons.close, 'Error', _colorForKey('error')),
      ]),
    );
  }

  Widget _legendItem(IconData icon, String label, Color color) {
    return Row(children: [Icon(icon, color: color), const SizedBox(width: 6), Text(label)]);
  }

  // Dialog showing connection details in readable form.
  void _showDetailsDialog(BuildContext context, String title, String content, String key, String? lastIso, bool isUpdating) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [Text(title), const Spacer(), Icon(_iconForKey(key), color: _colorForKey(key))]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(content),
            const SizedBox(height: 12),
            Text('Last update: ${_formatTime(lastIso)}'),
            if (isUpdating) ...[
              const SizedBox(height: 6),
              const Text('Status: Updating...', style: TextStyle(fontStyle: FontStyle.italic)),
            ]
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  // -----------------------
  // 10) Settings dialogs (per-source + global)
  // -----------------------
  void _openPerSourceSettings(BuildContext context, String currentDisplayName) {
    String canonicalKey = _sourceSettings.keys.firstWhere(
      (k) => (_sourceSettings[k]?['displayName'] ?? k) == currentDisplayName,
      orElse: () => currentDisplayName,
    );

    final existing = _sourceSettings[canonicalKey] ?? {};
    String displayName = existing['displayName'] as String? ?? currentDisplayName;
    int staleMinutesConn = existing['staleMinutesConn'] as int? ?? DEFAULT_STALE_MINUTES_CONN;
    int staleMinutesRep = existing['staleMinutesRep'] as int? ?? DEFAULT_STALE_MINUTES_REP;
    double variancePercent = (existing['variancePercent'] as num?)?.toDouble() ?? DEFAULT_VARIANCE_PERCENT;
    int dueHour = existing['reportDueHour'] as int? ?? 0;
    int dueMinute = existing['reportDueMinute'] as int? ?? 0;

    final displayNameCtrl = TextEditingController(text: displayName);
    final connTextCtrl = TextEditingController(text: staleMinutesConn.toString());
    final repTextCtrl = TextEditingController(text: staleMinutesRep.toString());
    final varTextCtrl = TextEditingController(text: variancePercent.toStringAsFixed(0));
    final dueHourCtrl = TextEditingController(text: dueHour.toString());
    final dueMinuteCtrl = TextEditingController(text: dueMinute.toString());

    void _parseAndClamp() {
      final c = int.tryParse(connTextCtrl.text);
      if (c != null) staleMinutesConn = c.clamp(1, 720);
      final r = int.tryParse(repTextCtrl.text);
      if (r != null) staleMinutesRep = r.clamp(1, 720);
      final v = double.tryParse(varTextCtrl.text);
      if (v != null) variancePercent = v.clamp(0, 200);
      final dh = int.tryParse(dueHourCtrl.text);
      if (dh != null) dueHour = dh.clamp(0, 23);
      final dm = int.tryParse(dueMinuteCtrl.text);
      if (dm != null) dueMinute = dm.clamp(0, 59);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Source Settings'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(alignment: Alignment.centerLeft, child: const Text('Display name', style: TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 6),
                TextField(
                  controller: displayNameCtrl,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Source display name'),
                  onChanged: (v) => setD(() => displayName = v),
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: const Text('Connection stale threshold (min)', style: TextStyle(fontWeight: FontWeight.bold))),
                Row(children: [
                  Expanded(
                    child: Slider(
                      value: staleMinutesConn.toDouble(),
                      min: 1,
                      max: 720,
                      divisions: 719,
                      label: '$staleMinutesConn',
                      onChanged: (v) {
                        setD(() {
                          staleMinutesConn = v.toInt();
                          connTextCtrl.text = staleMinutesConn.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: connTextCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => setD(_parseAndClamp),
                      onChanged: (_) => setD(_parseAndClamp),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: const Text('Report stale threshold (min)', style: TextStyle(fontWeight: FontWeight.bold))),
                Row(children: [
                  Expanded(
                    child: Slider(
                      value: staleMinutesRep.toDouble(),
                      min: 1,
                      max: 720,
                      divisions: 719,
                      label: '$staleMinutesRep',
                      onChanged: (v) {
                        setD(() {
                          staleMinutesRep = v.toInt();
                          repTextCtrl.text = staleMinutesRep.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: repTextCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => setD(_parseAndClamp),
                      onChanged: (_) => setD(_parseAndClamp),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: const Text('Variance warning threshold (%)', style: TextStyle(fontWeight: FontWeight.bold))),
                Row(children: [
                  Expanded(
                    child: Slider(
                      value: variancePercent,
                      min: 0,
                      max: 200,
                      divisions: 200,
                      label: '${variancePercent.toStringAsFixed(0)}%',
                      onChanged: (v) {
                        setD(() {
                          variancePercent = v;
                          varTextCtrl.text = variancePercent.toStringAsFixed(0);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: varTextCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => setD(_parseAndClamp),
                      onChanged: (_) => setD(_parseAndClamp),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: const Text('Report due time (local)', style: TextStyle(fontWeight: FontWeight.bold))),
                Row(children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: dueHourCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Hour'),
                      onSubmitted: (_) => setD(_parseAndClamp),
                      onChanged: (_) => setD(_parseAndClamp),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: dueMinuteCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Min'),
                      onSubmitted: (_) => setD(_parseAndClamp),
                      onChanged: (_) => setD(_parseAndClamp),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              TextButton(onPressed: () async {
                _parseAndClamp();

                _sourceSettings[canonicalKey] = {
                  'displayName': displayNameCtrl.text.trim().isEmpty ? canonicalKey : displayNameCtrl.text.trim(),
                  'staleMinutesConn': staleMinutesConn,
                  'staleMinutesRep': staleMinutesRep,
                  'variancePercent': variancePercent,
                  'reportDueHour': dueHour,
                  'reportDueMinute': dueMinute,
                };

                final newDisplay = _sourceSettings[canonicalKey]!['displayName'] as String;
                for (int i = 0; i < sources.length; i++) {
                  if (sources[i]['name'] == currentDisplayName) {
                    final s = Map<String, dynamic>.from(sources[i]);
                    s['name'] = newDisplay;
                    if (s.containsKey('C1')) {
                      final c1 = Map<String, String>.from(s['C1'] as Map);
                      final oldStatus = (s['R1'] as Map?)?['status'] ?? 'ok';
                      s['R1'] = {'status': oldStatus, 'details': _buildR1Details(newDisplay, c1)};
                    }
                    if (s.containsKey('C2')) {
                      final c2 = Map<String, String>.from(s['C2'] as Map);
                      final oldStatus = (s['R2'] as Map?)?['status'] ?? 'ok';
                      s['R2'] = {'status': oldStatus, 'details': _buildR2Details(newDisplay, c2)};
                    }
                    sources[i] = s;
                  }
                }

                await _saveSettingsPrefs();
                Navigator.of(ctx).pop();
                setState(() {});
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }

  void _openGlobalSettings(BuildContext context) {
    int refreshSeconds = _refreshSeconds;
    final refreshCtrl = TextEditingController(text: refreshSeconds.toString());

    ColorVisionMode selectedMode = _colorMode;

    void _parseRefresh() {
      final r = int.tryParse(refreshCtrl.text);
      if (r != null) refreshSeconds = r.clamp(5, 3600);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Global Settings'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('Refresh interval (sec): '),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: refreshSeconds.toDouble(),
                    min: 5,
                    max: 3600,
                    divisions: 119,
                    label: '$refreshSeconds',
                    onChanged: (v) {
                      setD(() {
                        refreshSeconds = v.toInt();
                        refreshCtrl.text = refreshSeconds.toString();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: refreshCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onSubmitted: (_) => setD(_parseRefresh),
                    onChanged: (_) => setD(_parseRefresh),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: const Text('Color Vision Mode', style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 6),
              DropdownButton<ColorVisionMode>(
                value: selectedMode,
                isExpanded: true,
                items: ColorVisionMode.values.map((m) => DropdownMenuItem(value: m, child: Text(m.toString().split('.').last))).toList(),
                onChanged: (v) {
                  setD(() {
                    selectedMode = v ?? ColorVisionMode.Original;
                    _colorMode = selectedMode;
                    _saveSettingsPrefs();
                  });
                },
              ),
              const SizedBox(height: 8),
              const Text('Updates: socket-driven updates are used for this build.', style: TextStyle(fontSize: 12)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              TextButton(onPressed: () async {
                _parseRefresh();
                _refreshSeconds = refreshSeconds;
                _colorMode = selectedMode;
                await _saveSettingsPrefs();
                _startTimer();
                Navigator.of(ctx).pop();
                setState(() {});
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }

  // -----------------------
  // 11) Error and Log helpers and pages
  // -----------------------
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

  // -----------------------
  // 12) Logout handling
  // -----------------------
  Future<void> _logout() async {
    // Socket-only build: attempt to emit a logout event, then clear local state.
    try {
      _socket?.emit('logout', {});
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', false);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (Route<dynamic> route) => false);
  }

  // -----------------------
  // 13) Color palettes and filters
  // -----------------------
  Map<String, String> _paletteForMode(ColorVisionMode mode) {
    switch (mode) {
      case ColorVisionMode.Protanopia:
        return {
          'ok': '#2b83ba',
          'warning': '#fdae61',
          'error': '#000000',
          'stale': '#9e9e9e',
          'down': '#5e4fa2',
          'nav': '#1f78b4',
          'navBorder': '#174e74',
          'bg': '#ffffff',
          'text': '#0b1720',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
      case ColorVisionMode.Deuteranopia:
        return {
          'ok': '#377eb8',
          'warning': '#ff7f00',
          'error': '#000000',
          'stale': '#9e9e9e',
          'down': '#984ea3',
          'nav': '#256aa8',
          'navBorder': '#1f527f',
          'bg': '#ffffff',
          'text': '#07121a',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
      case ColorVisionMode.Tritanopia:
        return {
          'ok': '#0072b2',
          'warning': '#fdc086',
          'error': '#000000',
          'stale': '#9e9e9e',
          'down': '#7f7f7f',
          'nav': '#0b5f8a',
          'navBorder': '#083e57',
          'bg': '#ffffff',
          'text': '#07121a',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
      case ColorVisionMode.Protanomaly:
        return {
          'ok': '#2f78b4',
          'warning': '#f6a254',
          'error': '#6f1f1f',
          'stale': '#9e9e9e',
          'down': '#6a52a3',
          'nav': '#2a5e92',
          'navBorder': '#1f425f',
          'bg': '#ffffff',
          'text': '#0b1720',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
      case ColorVisionMode.Deuteranomaly:
        return {
          'ok': '#2f78b4',
          'warning': '#f6a254',
          'error': '#5a1d1d',
          'stale': '#9e9e9e',
          'down': '#6a52a3',
          'nav': '#2a5e92',
          'navBorder': '#1f425f',
          'bg': '#ffffff',
          'text': '#0b1720',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
      case ColorVisionMode.Tritanomaly:
        return {
          'ok': '#2b7fb8',
          'warning': '#f7c77c',
          'error': '#5b2727',
          'stale': '#9e9e9e',
          'down': '#6b6b6b',
          'nav': '#25678f',
          'navBorder': '#183f57',
          'bg': '#ffffff',
          'text': '#07121a',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
      case ColorVisionMode.Achromatopsia:
        return {
          'ok': '#4f4f4f',
          'warning': '#8a8a8a',
          'error': '#1f1f1f',
          'stale': '#bdbdbd',
          'down': '#6b6b6b',
          'nav': '#2f2f2f',
          'navBorder': '#1f1f1f',
          'bg': '#ffffff',
          'text': '#000000',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfcfcf',
        };
      case ColorVisionMode.Original:
      default:
        return {
          'ok': '#2e7d32',
          'warning': '#ff9800',
          'error': '#d32f2f',
          'stale': '#9e9e9e',
          'down': '#6a1b9a',
          'nav': '#1976d2',
          'navBorder': '#145ea8',
          'bg': '#ffffff',
          'text': '#000000',
          'bgButton': '#ffffff',
          'buttonBorder': '#cfd8dc',
        };
    }
  }

  ColorFilter _colorFilterForMode(ColorVisionMode mode) {
    const identity = <double>[
      1, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ];
    const blueBoost = <double>[
      0.7, 0.1, 0.2, 0, 0,
      0.1, 0.8, 0.1, 0, 0,
      0.05, 0.05, 0.9, 0, 0,
      0, 0, 0, 1, 0,
    ];
    const desaturate = <double>[
      0.6, 0.25, 0.15, 0, 0,
      0.2, 0.6, 0.2, 0, 0,
      0.15, 0.25, 0.6, 0, 0,
      0, 0, 0, 1, 0,
    ];
    const greyscale = <double>[
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0, 0, 0, 1, 0,
    ];

    switch (mode) {
      case ColorVisionMode.Protanopia:
      case ColorVisionMode.Deuteranopia:
        return const ColorFilter.matrix(blueBoost);
      case ColorVisionMode.Protanomaly:
      case ColorVisionMode.Deuteranomaly:
      case ColorVisionMode.Tritanomaly:
        return const ColorFilter.matrix(desaturate);
      case ColorVisionMode.Tritanopia:
        return const ColorFilter.matrix(blueBoost);
      case ColorVisionMode.Achromatopsia:
        return const ColorFilter.matrix(greyscale);
      case ColorVisionMode.Original:
      default:
        return const ColorFilter.matrix(identity);
    }
  }

  // -----------------------
  // 14) Utility functions
  // -----------------------
  String _formatTime(String? iso) {
    if (iso == null) return 'never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'unknown';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // -----------------------
  // Evaluate and persist changes
  // -----------------------
  Future<void> _evaluateAndPersistChanges() async {
    try {
      // Build a lightweight snapshot keyed by source name
      final Map<String, dynamic> snapshot = {
        for (var s in sources)
          s['name']: {
            'connectionKey': s['connectionKey'],
            'reportKey': s['reportKey'],
            'reportValue': s['reportValue'],
          }
      };

      // Append a daily log entry for visibility
      _dailyLog.add({
        'time': DateTime.now().toIso8601String(),
        'description': 'Updated ${sources.length} sources',
        'status': 'UPDATE',
      });

      // If snapshot changed, persist it and the logs
      final String prevJson = jsonEncode(oldSnapshot ?? {});
      final String currentJson = jsonEncode(snapshot);
      if (prevJson != currentJson) {
        await _saveOldSnapshot(snapshot);
      }
      await _savePersistedLogs();
    } catch (_) {
      // swallow errors to avoid UI disruption
    }
  }
}

// -----------------------
// Error and Log pages
// -----------------------
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


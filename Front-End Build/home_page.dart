// Full updated HomePage.dart (color-vision palettes improved; AppBar/nav uses palette 'nav')
// -----------------------------------------------------------------------------
// Section table
// 1) Imports and persisted keys
// 2) Defaults and external info
// 3) HomePage widget + state lifecycle, init, dispose
// 4) Persistence helpers (load/save/clear)
// 5) Timer and refresh cycle
// 6) HTTP probe helpers and mapping
// 7) Data generation for sources (A,B mock; C Open‑Meteo; D USGS)
// 8) Utility helpers (icons, messages, progress, formatting)
// 9) UI: AppBar, source table, dialogs
// 10) Settings dialogs (per-source + global) — global includes color-vision selector
// 11) Compute helpers (three-checks)
// 12) Error and Log pages
// 13) Logout handling (added) — calls backend /logout then performs local logout
// 14) Color vision / palette helpers (improved; includes 'nav' entry and safer error colors)
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'about_page.dart'; // small About reuse from a separate file
import 'main.dart'; // for LoginPage navigation on logout

// Persisted keys
const String PREFS_OLD_SNAPSHOT = 'oldSnapshot';
const String PREFS_ERROR_LOG = 'errorLog';
const String PREFS_DAILY_LOG = 'dailyLog';
const String PREFS_REFRESH_INTERVAL = 'refreshIntervalSeconds';
const String PREFS_SOURCE_SETTINGS = 'sourceSettings';
const String PREFS_COLOR_MODE = 'colorVisionMode'; // persisted color-vision selection

// Defaults
const int DEFAULT_REFRESH_SECONDS = 60; // default refresh every 60 seconds
const int DEFAULT_STALE_MINUTES_CONN = 5; // connection considered stale after this many minutes
const int DEFAULT_STALE_MINUTES_REP = 5; // report considered stale after this many minutes
const double DEFAULT_VARIANCE_PERCENT = 10.0; // percent change threshold to mark a warning
const int PROGRESS_ANIMATION_SECONDS = 10; // how long the "recent update" animation should run

// Color vision modes supported by the UI (persisted)
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final Random _rng = Random();

  List<Map<String, dynamic>> sources = [];
  Map<String, dynamic>? oldSnapshot;
  Timer? _refreshTimer;

  final List<Map<String, String>> _errorLog = [];
  final List<Map<String, String>> _dailyLog = [];

  int _refreshSeconds = DEFAULT_REFRESH_SECONDS;
  Map<String, Map<String, dynamic>> _sourceSettings = {};

  // track per-source progress start times (used for the progress indicator)
  final Map<String, DateTime> _progressStart = {};

  // Logout backend endpoint config used by _logout()
  // Set to false for production deployments
  static const bool _isTestMode = false;
  String get _logoutEndpoint =>
      _isTestMode ? 'http://127.0.0.1:5000/logout' : 'https://datawatchapp.com/logout';

  // Color vision state (default Original). Persisted in prefs.
  ColorVisionMode _colorMode = ColorVisionMode.Original;

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

  // Initialize persisted state, generate initial data and start the periodic refresh timer.
  Future<void> _initEverything() async {
    await _loadPersistedState(); // load prefs and logs (including color mode)
    await _generateMockData(); // generate initial set of source states
    await _evaluateAndPersistChanges(); // compare and persist snapshot/logs if changed
    _startTimer(); // start periodic refreshes
    setState(() {});
  }

  // Load persisted snapshot, logs and settings from shared preferences.
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

    // load color mode (if saved)
    final storedColorMode = prefs.getString(PREFS_COLOR_MODE);
    if (storedColorMode != null) {
      try {
        _colorMode = ColorVisionMode.values.firstWhere((e) => e.toString() == storedColorMode);
      } catch (_) {
        _colorMode = ColorVisionMode.Original;
      }
    }
  }

  // Save logs to preferences.
  Future<void> _savePersistedLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREFS_ERROR_LOG, jsonEncode(_errorLog));
    await prefs.setString(PREFS_DAILY_LOG, jsonEncode(_dailyLog));
  }

  // Save snapshot to preferences and keep a reference in memory.
  Future<void> _saveOldSnapshot(Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREFS_OLD_SNAPSHOT, jsonEncode(snapshot));
    oldSnapshot = snapshot;
  }

  // Save settings to preferences.
  // Updated: also persist color-mode.
  Future<void> _saveSettingsPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PREFS_REFRESH_INTERVAL, _refreshSeconds);
    await prefs.setString(PREFS_SOURCE_SETTINGS, jsonEncode(_sourceSettings));
    await prefs.setString(PREFS_COLOR_MODE, _colorMode.toString());
  }

  // Clear all persisted data (snapshot, logs, settings).
  Future<void> _clearPersistedAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREFS_OLD_SNAPSHOT);
    await prefs.remove(PREFS_ERROR_LOG);
    await prefs.remove(PREFS_DAILY_LOG);
    await prefs.remove(PREFS_REFRESH_INTERVAL);
    await prefs.remove(PREFS_SOURCE_SETTINGS);
    await prefs.remove(PREFS_COLOR_MODE);
    oldSnapshot = null;
    _errorLog.clear();
    _dailyLog.clear();
    _sourceSettings.clear();
    _colorMode = ColorVisionMode.Original;
    setState(() {});
  }

  // Start the periodic refresh timer.
  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshSeconds), (timer) async {
      await _onRefreshCycle();
    });
  }

  // Called on each refresh cycle: regenerate data and persist differences.
  Future<void> _onRefreshCycle() async {
    await _generateMockData();
    await _evaluateAndPersistChanges();
    setState(() {});
  }

  // Build a lightweight snapshot map of the current sources to compare and persist.
  Map<String, dynamic> _buildSnapshotFromSources() {
    final map = <String, dynamic>{};
    for (var s in sources) {
      final name = s['name'] as String;
      map[name] = {
        'connection': s['connectionKey'],
        'report': s['reportKey'],
        'connectionDetails': s['connectionDetails'],
        'reportDetails': s['reportDetails'],
        'lastConn': s['lastConnUpdated'],
        'lastRep': s['lastRepUpdated'],
        'reportValue': s['reportValue'],
      };
    }
    return map;
  }

  // Compare snapshot to previously saved snapshot and append logs if changed.
  Future<void> _evaluateAndPersistChanges() async {
    final snapshot = _buildSnapshotFromSources();
    final changed = jsonEncode(snapshot) != jsonEncode(oldSnapshot ?? {});
    if (changed) {
      _appendLogsFromSnapshot(snapshot);
      await _saveOldSnapshot(snapshot);
      await _savePersistedLogs();
    }
  }

  // Append error/daily entries based on the snapshot.
  void _appendLogsFromSnapshot(Map<String, dynamic> snapshot) {
    final now = DateTime.now().toIso8601String();

    snapshot.forEach((name, value) {
      final entry = value as Map<String, dynamic>;
      final conn = entry['connection'] as String? ?? 'unknown';
      final rep = entry['report'] as String? ?? 'unknown';
      final connDetails = entry['connectionDetails'] as String? ?? '';
      final repDetails = entry['reportDetails'] as String? ?? '';

      if (conn == 'error' || conn == 'down') {
        _errorLog.insert(
            0, {'time': now, 'description': '$name connection: $connDetails', 'status': conn.toUpperCase()});
      }

      if ((rep == 'error' || rep == 'down')) {
        if (!(conn == 'ok' || conn == 'stale')) {
          _errorLog.insert(
              0, {'time': now, 'description': '$name report: $repDetails', 'status': rep.toUpperCase()});
        }
      }

      _dailyLog.insert(0, {'time': now, 'description': '$name update - conn:$conn rep:$rep', 'status': 'INFO'});

      if (_errorLog.length > 1000) _errorLog.removeRange(1000, _errorLog.length);
      if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length);
    });
  }

  // -----------------------
  // HTTP probe helpers
  // -----------------------

  // Probe a URL and return a small map with status, latency and parsed JSON body if available.
  Future<Map<String, dynamic>> _probeUrl(String url, {Duration timeout = const Duration(seconds: 5)}) async {
    final result = {'status': 'down', 'latencyMs': 9999, 'body': null};
    try {
      final swStart = DateTime.now();
      final resp = await http.get(Uri.parse(url)).timeout(timeout);
      final latency = DateTime.now().difference(swStart).inMilliseconds;
      result['latencyMs'] = latency;
      if (resp.statusCode == 200) {
        try {
          final body = jsonDecode(resp.body);
          result['body'] = body;
          if (latency < 800) {
            result['status'] = 'ok';
          } else {
            result['status'] = 'warning';
          }
        } catch (e) {
          result['status'] = 'error';
        }
      } else {
        result['status'] = 'down';
      }
    } on TimeoutException {
      result['status'] = 'down';
    } catch (e) {
      result['status'] = 'down';
    }
    return result;
  }

  // Map the probe result to our standardized keys and optionally extract a numeric value.
  Map<String, dynamic> _mapProbeToKeysAndValue(
      String sourceName, Map<String, dynamic>? probeBody, String probeStatus) {
    final connKey = probeStatus;
    String repKey = probeStatus;
    double? reportValue;
    try {
      if (sourceName.contains('Source C')) {
        // Open-Meteo: current_weather.temperature => numeric value used for variance checks.
        if (probeBody != null &&
            probeBody['current_weather'] != null &&
            probeBody['current_weather']['temperature'] != null) {
          repKey = 'ok';
          final tmp = probeBody['current_weather']['temperature'];
          if (tmp is num) reportValue = tmp.toDouble();
        } else {
          repKey = 'warning';
        }
      } else if (sourceName.contains('Source D')) {
        // USGS: features[0].properties.mag => numeric magnitude.
        if (probeBody != null && probeBody['features'] is List && (probeBody['features'] as List).isNotEmpty) {
          final f = (probeBody['features'] as List).first;
          if (f is Map && f['properties'] is Map && f['properties']['mag'] != null) {
            repKey = 'ok';
            final m = f['properties']['mag'];
            if (m is num) reportValue = m.toDouble();
          } else {
            repKey = 'warning';
          }
        } else {
          repKey = 'warning';
        }
      }
    } catch (_) {
      repKey = 'error';
    }
    return {'connection': connKey, 'report': repKey, 'value': reportValue};
  }

  // -----------------------
  // Data generation (4 sources: A,B mock; C Open-Meteo; D USGS)
  // -----------------------

  // Generate the sources list: two mock sources and two real API probes.
  Future<void> _generateMockData() async {
    final now = DateTime.now();
    final prev = oldSnapshot ?? {};
    List<Map<String, dynamic>> newSources = [];

    // Mark progress start for the "recent update" animation.
    void _markProgressStart(String name) {
      _progressStart[name] = DateTime.now();
      Future.delayed(const Duration(seconds: PROGRESS_ANIMATION_SECONDS + 1), () {
        if (mounted) setState(() {});
      });
    }

    // --- Source A (mock) ---
    {
      final name = 'Source A';
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null;

      String connKey = _pickConnKey(); // simulated connectivity state
      String repKey = _pickRepKey(); // simulated report state

      double reportValue = 15.0 + _rng.nextDouble() * 10.0; // simulated metric
      if (_rng.nextDouble() < 0.24 && prevValue != null) {
        reportValue = prevValue; // sometimes repeat previous to avoid variance
      }
      if (_rng.nextDouble() < 0.06) {
        reportValue += (_rng.nextBool() ? 1 : -1) * (5 + _rng.nextDouble() * 10); // occasional spike
      }

      DateTime connTs = now.subtract(Duration(minutes: _rng.nextInt(3)));
      DateTime repTs = now.subtract(Duration(minutes: _rng.nextInt(4)));

      String connDetails = _messageFor(connKey, 'connection', name, connTs);
      String repDetails = 'value: ${reportValue.toStringAsFixed(2)} at ${repTs.toIso8601String()}';

      final settings = _sourceSettings[name];
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int
          ? settings['staleMinutesConn'] as int
          : DEFAULT_STALE_MINUTES_CONN;
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int
          ? settings['staleMinutesRep'] as int
          : DEFAULT_STALE_MINUTES_REP;
      final variancePercent = settings != null && settings['variancePercent'] is num
          ? (settings['variancePercent'] as num).toDouble()
          : DEFAULT_VARIANCE_PERCENT;
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0;
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0;

      if (DateTime.now().difference(connTs).inMinutes >= staleMinutesConn &&
          connKey != 'down' &&
          connKey != 'error') {
        final treatConn = settings != null && settings['treatStaleAsConn'] is String
            ? settings['treatStaleAsConn'] as String
            : 'stale';
        connKey = treatConn;
        connDetails = _messageFor(treatConn, 'connection', name, connTs);
      }

      String finalRepKey = repKey;
      if (prevValue != null) {
        final diff = (reportValue - prevValue).abs();
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0);
        if (pct >= variancePercent) {
          finalRepKey = 'warning';
        }
      }

      final dueToday = DateTime(now.year, now.month, now.day, dueHour, dueMinute);
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30));
      final hasRecentReport = repTs.isAfter(dueWindowStart);
      if (now.isBefore(dueToday)) {
        // before due: nothing additional
      } else {
        if (!hasRecentReport) {
          finalRepKey = 'error';
        } else {
          if (repTs.isAfter(dueToday)) {
            _dailyLog.insert(0, {
              'time': DateTime.now().toIso8601String(),
              'description': '$name late report submitted at ${repTs.toIso8601String()}',
              'status': 'LATE'
            });
            if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length);
          }
        }
      }

      if (now.isAfter(dueWindowStart) && now.isBefore(dueToday)) {
        if (!hasRecentReport) {
          finalRepKey = 'warning';
        }
      }

      repDetails = 'value: ${reportValue.toStringAsFixed(2)} at ${repTs.toIso8601String()}';
      _markProgressStart(name);

      newSources.add({
        'name': name,
        'connectionKey': connKey,
        'reportKey': finalRepKey,
        'connectionIcon': _iconForKey(connKey),
        'reportIcon': _iconForKey(finalRepKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': connTs.toIso8601String(),
        'lastRepUpdated': repTs.toIso8601String(),
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': staleMinutesConn,
        'staleMinutesRep': staleMinutesRep,
        'variancePercent': variancePercent,
        'reportDueHour': dueHour,
        'reportDueMinute': dueMinute,
        'reportValue': reportValue,
      });
    }

    // --- Source B (mock) ---
    {
      final name = 'Source B';
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null;

      String connKey = _pickConnKey();
      String repKey = _pickRepKey();

      double reportValue = 100.0 * (0.5 + _rng.nextDouble());
      if (_rng.nextDouble() < 0.2 && prevValue != null) reportValue = prevValue;
      if (_rng.nextDouble() < 0.05) reportValue += (_rng.nextBool() ? 1 : -1) * (_rng.nextDouble() * 30);

      DateTime connTs = now.subtract(Duration(minutes: 1 + _rng.nextInt(4)));
      DateTime repTs = now.subtract(Duration(minutes: 2 + _rng.nextInt(6)));

      String connDetails = _messageFor(connKey, 'connection', name, connTs);
      String repDetails = 'value: ${reportValue.toStringAsFixed(2)} at ${repTs.toIso8601String()}';

      final settings = _sourceSettings[name];
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int
          ? settings['staleMinutesConn'] as int
          : DEFAULT_STALE_MINUTES_CONN;
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int
          ? settings['staleMinutesRep'] as int
          : DEFAULT_STALE_MINUTES_REP;
      final variancePercent = settings != null && settings['variancePercent'] is num
          ? (settings['variancePercent'] as num).toDouble()
          : DEFAULT_VARIANCE_PERCENT;
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0;
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0;

      if (DateTime.now().difference(connTs).inMinutes >= staleMinutesConn &&
          connKey != 'down' &&
          connKey != 'error') {
        final treatConn = settings != null && settings['treatStaleAsConn'] is String
            ? settings['treatStaleAsConn'] as String
            : 'stale';
        connKey = treatConn;
        connDetails = _messageFor(treatConn, 'connection', name, connTs);
      }

      String finalRepKey = repKey;
      if (prevValue != null) {
        final diff = (reportValue - prevValue).abs();
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0);
        if (pct >= variancePercent) finalRepKey = 'warning';
      }

      final dueToday = DateTime(now.year, now.month, now.day, dueHour, dueMinute);
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30));
      final hasRecentReport = repTs.isAfter(dueWindowStart);

      if (now.isBefore(dueToday)) {
      } else {
        if (!hasRecentReport) {
          finalRepKey = 'error';
        } else {
          if (repTs.isAfter(dueToday)) {
            _dailyLog.insert(0, {
              'time': DateTime.now().toIso8601String(),
              'description': '$name late report submitted at ${repTs.toIso8601String()}',
              'status': 'LATE'
            });
            if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length);
          }
        }
      }

      if (now.isAfter(dueWindowStart) && now.isBefore(dueToday)) {
        if (!hasRecentReport) {
          finalRepKey = 'warning';
        }
      }

      repDetails = 'value: ${reportValue.toStringAsFixed(2)} at ${repTs.toIso8601String()}';
      _markProgressStart(name);

      newSources.add({
        'name': name,
        'connectionKey': connKey,
        'reportKey': finalRepKey,
        'connectionIcon': _iconForKey(connKey),
        'reportIcon': _iconForKey(finalRepKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': connTs.toIso8601String(),
        'lastRepUpdated': repTs.toIso8601String(),
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': staleMinutesConn,
        'staleMinutesRep': staleMinutesRep,
        'variancePercent': variancePercent,
        'reportDueHour': dueHour,
        'reportDueMinute': dueMinute,
        'reportValue': reportValue,
      });
    }

    // -----------------------
    // Source C (Open-Meteo: weather)
    // -----------------------
    {
      final name = 'Source C'; // define source name
      final url =
          'https://api.open-meteo.com/v1/forecast?latitude=35.3733&longitude=-119.0187&current_weather=true'; // Open-Meteo URL
      // call the API and get probe map
      final probe = await _probeUrl(url, timeout: const Duration(seconds: 5)); // call the API and get probe map
      final latency = probe['latencyMs'] as int? ?? 9999; // read latency from probe
      final pbody = probe['body'] as Map<String, dynamic>?; // read parsed JSON body if any
      final pstatus = probe['status'] as String; // get normalized status string

      final mapped =
          _mapProbeToKeysAndValue(name, pbody, pstatus); // map probe body + status to our standardized keys
      String connKeyForCompare = mapped['connection'] ?? 'down'; // pick connection key or default to 'down'
      String repKeyForCompare = mapped['report'] ?? 'warning'; // pick report key or default to 'warning'
      final double? reportValue =
          mapped['value'] as double?; // numeric value extracted if mapping found one

      final nowTs = DateTime.now(); // timestamp used for last update fields
      final connDetails =
          'connection ${connKeyForCompare.toUpperCase()}: ${latency}ms to Open-Meteo'; // readable connection detail
      final repDetails = reportValue != null ? 'value: ${reportValue.toStringAsFixed(2)}' : 'no value'; // readable report detail

      final settings = _sourceSettings[name]; // attempt to load per-source settings
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int
          ? settings['staleMinutesConn'] as int
          : DEFAULT_STALE_MINUTES_CONN; // connection staleness threshold
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int
          ? settings['staleMinutesRep'] as int
          : DEFAULT_STALE_MINUTES_REP; // report staleness threshold
      final variancePercent = settings != null && settings['variancePercent'] is num
          ? (settings['variancePercent'] as num).toDouble()
          : DEFAULT_VARIANCE_PERCENT; // variance percent threshold
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0; // report due hour
      final dueMinute =
          settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0; // report due minute

      if (pstatus == 'ok' && latency > 1500) connKeyForCompare = 'warning'; // mark connection warning on high latency

      final prevValue =
          prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null; // previous numeric value
      String finalRepKey = repKeyForCompare; // start final report key from mapped result
      if (reportValue != null && prevValue != null) {
        final diff = (reportValue - prevValue).abs(); // absolute difference
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0); // percent change
        if (pct >= variancePercent) finalRepKey = 'warning'; // flag warning if change >= threshold
      }

      final dueToday = DateTime(nowTs.year, nowTs.month, nowTs.day, dueHour, dueMinute); // today at due time
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30)); // begin of recent window
      final repTs = nowTs; // treat probe time as report time
      final hasRecentReport = repTs.isAfter(dueWindowStart); // whether report is recent

      if (nowTs.isBefore(dueToday)) {
        // before due: ok/warning by variance (no action)
      } else {
        if (!hasRecentReport) {
          finalRepKey = 'error'; // past due + no recent -> error
        } else {
          if (repTs.isAfter(dueToday)) {
            _dailyLog.insert(0, {
              'time': DateTime.now().toIso8601String(),
              'description': '$name late report submitted at ${repTs.toIso8601String()}',
              'status': 'LATE'
            }); // if report after due -> log LATE
            if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length); // cap daily log size
          }
        }
      }

      _markProgressStart(name); // mark progress start for UI animation

      newSources.add({
        'name': name,
        'connectionKey': connKeyForCompare,
        'reportKey': finalRepKey,
        'connectionIcon': _iconForKey(connKeyForCompare),
        'reportIcon': _iconForKey(finalRepKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': nowTs.toIso8601String(),
        'lastRepUpdated': nowTs.toIso8601String(),
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': staleMinutesConn,
        'staleMinutesRep': staleMinutesRep,
        'variancePercent': variancePercent,
        'reportDueHour': dueHour,
        'reportDueMinute': dueMinute,
        'reportValue': reportValue,
      });
    }

    // -----------------------
    // Source D (USGS)
    // -----------------------
    {
      final name = 'Source D'; // set source name
      final startIso = DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(); // start time param
      final url =
          'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&limit=1&starttime=$startIso'; // build USGS query URL
      // call the probe helper to GET the URL and measure latency/status
      final probe = await _probeUrl(url, timeout: const Duration(seconds: 5));
      final latency = probe['latencyMs'] as int? ?? 9999; // read latency from probe result
      final pbody = probe['body'] as Map<String, dynamic>?; // parsed JSON body from the probe, or null
      final pstatus = probe['status'] as String; // normalized probe status string

      final mapped =
          _mapProbeToKeysAndValue(name, pbody, pstatus); // map probe body/status into standardized keys + value
      String connKeyForCompare = mapped['connection'] ?? 'down'; // connection key fallback
      String repKeyForCompare = mapped['report'] ?? 'warning'; // report key fallback
      final double? reportValue = mapped['value'] as double?; // numeric metric (e.g., magnitude)

      final nowTs = DateTime.now(); // store the current timestamp
      final connDetails = 'connection ${connKeyForCompare.toUpperCase()}: ${latency}ms to USGS'; // connection detail string
      final repDetails = reportValue != null ? 'magnitude: ${reportValue.toStringAsFixed(2)}' : 'no events'; // report detail string

      final settings = _sourceSettings[name]; // per-source settings map
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int
          ? settings['staleMinutesConn'] as int
          : DEFAULT_STALE_MINUTES_CONN; // connection stale threshold
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int
          ? settings['staleMinutesRep'] as int
          : DEFAULT_STALE_MINUTES_REP; // report stale threshold
      final variancePercent = settings != null && settings['variancePercent'] is num
          ? (settings['variancePercent'] as num).toDouble()
          : DEFAULT_VARIANCE_PERCENT; // variance percent threshold
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0; // due hour
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0; // due minute

      if (pstatus == 'ok' && latency > 1500) connKeyForCompare = 'warning'; // escalate to warning for high latency

      final prevValue =
          prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null; // fetch previous value if exists
      String finalRepKey = repKeyForCompare; // start final report key from mapped value
      if (reportValue != null && prevValue != null) {
        final diff = (reportValue - prevValue).abs(); // absolute difference
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0); // percent change
        if (pct >= variancePercent) finalRepKey = 'warning'; // mark warning on large percent change
      }

      final dueToday = DateTime(nowTs.year, nowTs.month, nowTs.day, dueHour, dueMinute); // build today's due time
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30)); // recent window start
      final repTs = nowTs; // use now as the report time for this probe
      final hasRecentReport = repTs.isAfter(dueWindowStart); // check recency

      if (nowTs.isBefore(dueToday)) {
        // before due -> nothing to change
      } else {
        if (!hasRecentReport) {
          finalRepKey = 'error'; // past due with no recent report -> error
        } else {
          if (repTs.isAfter(dueToday)) {
            _dailyLog.insert(0, {
              'time': DateTime.now().toIso8601String(),
              'description': '$name late report submitted at ${repTs.toIso8601String()}',
              'status': 'LATE'
            }); // log late submission
            if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length); // cap size
          }
        }
      }

      _markProgressStart(name); // mark the recent update animation start

      newSources.add({
        'name': name,
        'connectionKey': connKeyForCompare,
        'reportKey': finalRepKey,
        'connectionIcon': _iconForKey(connKeyForCompare),
        'reportIcon': _iconForKey(finalRepKey),
        'connectionDetails': connDetails,
        'reportDetails': repDetails,
        'lastConnUpdated': nowTs.toIso8601String(),
        'lastRepUpdated': nowTs.toIso8601String(),
        'isUpdatingConn': false,
        'isUpdatingRep': false,
        'staleMinutesConn': staleMinutesConn,
        'staleMinutesRep': staleMinutesRep,
        'variancePercent': variancePercent,
        'reportDueHour': dueHour,
        'reportDueMinute': dueMinute,
        'reportValue': reportValue,
      });
    }

    // assign built list to state variable
    sources = newSources;
  }

  // -----------------------
  // Utility helpers (icons, messages, progress)
  // -----------------------

  // Randomly pick a connection key for mock sources.
  String _pickConnKey() {
    final r = _rng.nextDouble();
    if (r < 0.10) return 'down';
    if (r < 0.30) return 'warning';
    return 'ok';
  }

  // Randomly pick a report key for mock sources.
  String _pickRepKey() {
    final r = _rng.nextDouble();
    if (r < 0.10) return 'down';
    if (r < 0.25) return 'warning';
    return 'ok';
  }

  // Build a short human message for connection/report details.
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

  // Pick an icon for a status key.
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

  // Pick a color for a status key using the active color-vision palette.
  Color _colorForKey(String k) {
    final palette = _paletteForMode(_colorMode); // get palette for current color mode
    final hex = palette[k] ?? palette['ok']!; // fallback to ok color
    return Color(int.parse(hex.replaceFirst('#', '0xff')));
  }

  // Build a list of current error entries from the sources list.
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

  // Build a list of current log entries from the sources list.
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

  // Compute a progress value 0..1 that blends recent "update" animation and aging toward staleness.
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

  // Format ISO string to HH:MM:SS for display.
  String _formatTime(String? iso) {
    if (iso == null) return 'never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'unknown';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // -----------------------
  // UI: build, dialogs, settings
  // -----------------------

  // Build the tappable logo and brand capsule used in the AppBar.
  // Logo is wrapped in a ColorFiltered widget that applies a filter appropriate to the selected color-vision mode.
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
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutPage()),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        height: containerHeight,
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: navBarBorderColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: logoSize,
              width: logoSize,
              child: ColorFiltered(
                colorFilter: _colorFilterForMode(_colorMode), // apply a color filter that adapts the logo colors for selected color vision mode
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
                    color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))),
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
    final palette = _paletteForMode(_colorMode);
    final navHex = palette['nav'] ?? '#1976d2'; // fallback blue
    final navColor = Color(int.parse(navHex.replaceFirst('#', '0xff')));

    return Scaffold(
      appBar: AppBar(
        // Ensure title has predictable spacing and doesn't get auto-centered/trimmed.
        titleSpacing: 0, // allow title to start near the left edge
        centerTitle: false, // left-align title (typical for large screens / Android)
        leadingWidth: 56, // reserve standard space for a potential leading widget
        toolbarHeight: 56, // consistent height for the AppBar
        title: _buildLogoBrandButton(),
        backgroundColor: navColor, // use palette nav color for AppBar background
        actions: [
          // Responsive: show full actions on wide screens, collapse to a menu on narrow screens
          LayoutBuilder(
            builder: (context, constraints) {
              final double screenWidth = MediaQuery.of(context).size.width;
              final bool isPhone = screenWidth <= 600.0;

              if (!isPhone && constraints.maxWidth > 700) {
                return Row(children: [
                  TextButton(
                    onPressed: () {
                      final errors = _currentErrorsFromSources();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ErrorPage(entries: errors, persistedErrors: _errorLog)));
                    },
                    child: Text('Errors', style: TextStyle(color: Color(int.parse((palette['text'] ?? '#ffffff').replaceFirst('#', '0xff'))))),
                  ),
                  TextButton(
                    onPressed: () {
                      final logs = _currentLogFromSources();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => LogPage(entries: logs, persistedLogs: _dailyLog)));
                    },
                    child: Text('Log', style: TextStyle(color: Color(int.parse((palette['text'] ?? '#ffffff').replaceFirst('#', '0xff'))))),
                  ),
                  IconButton(
                    icon: Icon(Icons.settings, color: Color(int.parse((palette['text'] ?? '#ffffff').replaceFirst('#', '0xff')))),
                    tooltip: 'Settings',
                    onPressed: () => _openGlobalSettings(context),
                  ),
                  IconButton(
                    onPressed: () async {
                      await _clearPersistedAll();
                    },
                    icon: Icon(Icons.delete_sweep, color: Color(int.parse((palette['text'] ?? '#ffffff').replaceFirst('#', '0xff')))),
                    tooltip: 'Clear persisted snapshot and logs',
                  ),
                  IconButton(
                    onPressed: _logout, // now calls centralized logout handler (calls backend then local logout)
                    icon: Icon(Icons.logout, color: Color(int.parse((palette['text'] ?? '#ffffff').replaceFirst('#', '0xff')))),
                    tooltip: 'Logout',
                  ),
                ]);
              } else {
                return PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Color(int.parse((palette['text'] ?? '#ffffff').replaceFirst('#', '0xff')))),
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
                      await _logout(); // centralized logout call
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
                        Row(children: [
                          SizedBox(width: 140, child: Text('', style: TextStyle(fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff')))))),
                          Expanded(child: Center(child: Text('Connection', style: TextStyle(fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))))),
                          Expanded(child: Center(child: Text('Report', style: TextStyle(fontWeight: FontWeight.bold, color: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))))))),
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
                              final lastConn = s['lastConnUpdated'] as String?;
                              final lastRep = s['lastRepUpdated'] as String?;
                              final isUpdConn = s['isUpdatingConn'] as bool? ?? false;
                              final isUpdRep = s['isUpdatingRep'] as bool? ?? false;
                              final staleMinutesConn =
                                  s['staleMinutesConn'] as int? ?? DEFAULT_STALE_MINUTES_CONN;
                              final staleMinutesRep =
                                  s['staleMinutesRep'] as int? ?? DEFAULT_STALE_MINUTES_REP;

                              final connProgress = _computeProgressToStale(lastConn, staleMinutesConn, name);
                              final repProgress = _computeProgressToStale(lastRep, staleMinutesRep, name);

                              // compute three checks for this source (conn / db / data)
                              final three = _computeThreeChecksForSource(s);
                              final connThree = three['conn']!;
                              final dbThree = three['db']!;
                              final dataThree = three['data']!;

                              double pickOpacity(String key) {
                                if (key == 'ok' || key == 'warning' || key == 'stale') return 1.0;
                                return 0.25;
                              }

                              // helper that builds three tiny bars that fit inside the button column width
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

                              // Now render the row with name, connection column and report column.
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

                                  // Connection column (three mini-bars above the button)
                                  Expanded(
                                    child: Column(children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: _buildThreeBarsForButton(connThree, dbThree, dataThree),
                                      ),
                                      const SizedBox(height: 6), // keep spacing where the progress bar was
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(int.parse((palette['bgButton'] ?? '#ffffff').replaceFirst('#', '0xff'))),
                                          foregroundColor: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))),
                                          side: BorderSide(color: Color(int.parse((palette['buttonBorder'] ?? '#000000').replaceFirst('#', '0xff')))),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                        onPressed: () {
                                          final List<String> failing = [];
                                          if (connThree != 'ok') failing.add('Connection: ${connThree.toUpperCase()}');
                                          if (dbThree != 'ok') failing.add('DB read: ${dbThree.toUpperCase()}');
                                          if (dataThree != 'ok') failing.add('Data quality: ${dataThree.toUpperCase()}');

                                          final info = failing.isEmpty ? connDetails : failing.join('\n');

                                          _showDetailsDialog(context, '$name - Connection', info, connKey, lastConn, isUpdConn);
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

                                  // Report column (three mini-bars above the button)
                                  Expanded(
                                    child: Column(children: [
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: _buildThreeBarsForButton(connThree, dbThree, dataThree),
                                      ),
                                      const SizedBox(height: 6), // keep spacing where the progress bar was
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(int.parse((palette['bgButton'] ?? '#ffffff').replaceFirst('#', '0xff'))),
                                          foregroundColor: Color(int.parse((palette['text'] ?? '#000000').replaceFirst('#', '0xff'))),
                                          side: BorderSide(color: Color(int.parse((palette['buttonBorder'] ?? '#000000').replaceFirst('#', '0xff')))),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                        onPressed: () {
                                          final List<String> failing = [];
                                          if (connThree != 'ok') failing.add('Connection: ${connThree.toUpperCase()}');
                                          if (dbThree != 'ok') failing.add('DB read: ${dbThree.toUpperCase()}');
                                          if (dataThree != 'ok') failing.add('Data quality: ${dataThree.toUpperCase()}');

                                          final info = failing.isEmpty ? repDetails : failing.join('\n');

                                          _showDetailsDialog(context, '$name - Report', info, repKey, lastRep, isUpdRep);
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

  // Legend explaining colors and icons.
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

  // Show a details dialog for connection/report with status and last update.
  void _showDetailsDialog(BuildContext context, String title, String content, String key, String? lastIso, bool isUpdating) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [Text(title), const Spacer(), Icon(_iconForKey(key), color: _colorForKey(key))]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(content),
          const SizedBox(height: 12),
          Text('Last update: ${_formatTime(lastIso)}'),
          if (isUpdating) ...[
            const SizedBox(height: 6),
            const Text('Status: Updating...', style: TextStyle(fontStyle: FontStyle.italic)),
          ]
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  // -----------------------
  // Settings dialogs (global + per source)
  // -----------------------

  // Per-source settings dialog: sliders + numeric input for thresholds and due time.
  void _openPerSourceSettings(BuildContext context, String sourceName) {
    final existing = _sourceSettings[sourceName];
    int staleMinutesConn = existing != null && existing['staleMinutesConn'] is int ? existing['staleMinutesConn'] as int : DEFAULT_STALE_MINUTES_CONN;
    int staleMinutesRep = existing != null && existing['staleMinutesRep'] is int ? existing['staleMinutesRep'] as int : DEFAULT_STALE_MINUTES_REP;
    double variancePercent = existing != null && existing['variancePercent'] is num ? (existing['variancePercent'] as num).toDouble() : DEFAULT_VARIANCE_PERCENT;
    int dueHour = existing != null && existing['reportDueHour'] is int ? existing['reportDueHour'] as int : 0;
    int dueMinute = existing != null && existing['reportDueMinute'] is int ? existing['reportDueMinute'] as int : 0;
    String treatStaleAsConn = existing != null && existing['treatStaleAsConn'] is String ? existing['treatStaleAsConn'] as String : 'stale';
    String treatStaleAsRep = existing != null && existing['treatStaleAsRep'] is String ? existing['treatStaleAsRep'] as String : 'stale';
    String treatMissing = existing != null && existing['treatMissingReportWhenConnOk'] is String ? existing['treatMissingReportWhenConnOk'] as String : 'warning';

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
            title: Text('$sourceName settings'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 4),
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
                Row(children: [
                  const Text('Treat stale as: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: treatStaleAsConn,
                    items: ['ok', 'stale', 'warning', 'error'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setD(() => treatStaleAsConn = v ?? 'stale'),
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
                  Expanded(
                    child: Row(children: [
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
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Missing report when conn OK: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: treatMissing,
                    items: ['ok', 'warning', 'error'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setD(() => treatMissing = v ?? 'warning'),
                  ),
                ]),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              TextButton(onPressed: () {
                _parseAndClamp();
                _sourceSettings[sourceName] = {
                  'staleMinutesConn': staleMinutesConn,
                  'staleMinutesRep': staleMinutesRep,
                  'variancePercent': variancePercent,
                  'reportDueHour': dueHour,
                  'reportDueMinute': dueMinute,
                  'treatStaleAsConn': treatStaleAsConn,
                  'treatStaleAsRep': treatStaleAsRep,
                  'treatMissingReportWhenConnOk': treatMissing,
                };
                _saveSettingsPrefs();
                Navigator.of(ctx).pop();
                setState(() {});
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }

  // Global settings dialog for refresh interval and color-vision selector.
  void _openGlobalSettings(BuildContext context) {
    int refreshSeconds = _refreshSeconds;
    final refreshCtrl = TextEditingController(text: refreshSeconds.toString());

    ColorVisionMode selectedMode = _colorMode; // local copy for dialog

    void _parseRefresh() {
      final r = int.tryParse(refreshCtrl.text);
      if (r != null) {
        refreshSeconds = r.clamp(5, 3600);
      }
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
              // Color-vision selector: changes the UI palette and logo filter
              Align(alignment: Alignment.centerLeft, child: const Text('Color Vision Mode', style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 6),
              DropdownButton<ColorVisionMode>(
                value: selectedMode,
                isExpanded: true,
                items: ColorVisionMode.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.toString().split('.').last)))
                    .toList(),
                onChanged: (v) {
                  setD(() {
                    selectedMode = v ?? ColorVisionMode.Original;
                    // update a preview: setState on outer to preview immediately
                    _colorMode = selectedMode;
                    _saveSettingsPrefs(); // persist selection as preview is immediate
                  });
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a color-vision mode to adapt the UI palette and logo so users with color deficiencies can better distinguish statuses.',
                style: TextStyle(fontSize: 12),
              ),
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
  // Compute three simplified checks for the UI: connection, db, and data-quality.
  // -----------------------
  Map<String, String> _computeThreeChecksForSource(Map<String, dynamic> s) {
    final name = s['name'] as String;
    final connKey = s['connectionKey'] as String? ?? 'down';
    final repKey = s['reportKey'] as String? ?? 'warning';
    final reportValue = s['reportValue'];

    String connCheck = connKey;
    String dbCheck = 'down';
    String dataCheck = repKey;

    if (name == 'Source A' || name == 'Source B') {
      // For mock sources: simulate DB check from connection/report keys.
      if (connCheck == 'down' || connCheck == 'error') {
        dbCheck = connCheck;
      } else {
        dbCheck = (repKey == 'error') ? 'error' : (repKey == 'warning' ? 'warning' : 'ok');
      }
    } else {
      // For Sources C/D use connection key as DB check placeholder.
      // Backend: replace this with a separate DB/read probe if available.
      dbCheck = connKey;
    }

    // Data quality check: if reportKey is ok but no numeric value, warn.
    if (repKey == 'ok') {
      dataCheck = (reportValue == null) ? 'warning' : 'ok';
    } else {
      dataCheck = repKey;
    }

    return {'conn': connCheck, 'db': dbCheck, 'data': dataCheck};
  }
}

// -----------------------
// Error and Log Pages
// -----------------------

// ErrorPage: shows current view and persisted history.
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

// LogPage: shows current and persisted logs.
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

// -----------------------
// Logout handling (added)
// -----------------------

// Centralized logout: try backend /logout then always perform local logout/navigation.
// This keeps app behaviour consistent and avoids duplicated inline logout logic.
extension on _HomePageState {
  Future<void> _logout() async {
    try {
      // Attempt to notify backend; failures/timeouts are ignored and local logout proceeds.
      await http.get(Uri.parse(_logoutEndpoint), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 6));
    } catch (_) {
      // swallow network errors/timeouts
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', false);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    }
  }
}

// -----------------------
// Color vision / palette helpers (improved)
// -----------------------

// Returns a palette mapping status keys to hex colors for a given color-vision mode.
// Palettes include 'nav' (AppBar), 'navBorder', 'bg', 'text', 'bgButton', 'buttonBorder', plus status colors.
Map<String, String> _paletteForMode(ColorVisionMode mode) {
  // Each palette defines: ok, warning, error, stale, down, nav, navBorder, bg, text, bgButton, buttonBorder
  // Colors chosen to be more distinguishable per accessible palettes and common recommendations.
  switch (mode) {
    case ColorVisionMode.Protanopia:
      return {
        'ok': '#2b83ba', // blue
        'warning': '#fdae61', // orange
        'error': '#000000', // choose black/dark for critical (safer)
        'stale': '#9e9e9e',
        'down': '#5e4fa2', // purple
        'nav': '#1f78b4',
        'navBorder': '#174e74',
        'bg': '#ffffff',
        'text': '#0b1720',
        'bgButton': '#ffffff',
        'buttonBorder': '#cfd8dc',
      };
    case ColorVisionMode.Deuteranopia:
      return {
        'ok': '#377eb8', // blue
        'warning': '#ff7f00', // orange
        'error': '#000000', // black for clarity
        'stale': '#9e9e9e',
        'down': '#984ea3', // purple
        'nav': '#256aa8',
        'navBorder': '#1f527f',
        'bg': '#ffffff',
        'text': '#07121a',
        'bgButton': '#ffffff',
        'buttonBorder': '#cfd8dc',
      };
    case ColorVisionMode.Tritanopia:
      return {
        'ok': '#0072b2', // deep blue
        'warning': '#fdc086', // tan/orange
        'error': '#000000', // black for clarity
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
        'ok': '#2f78b4', // slightly desaturated blue
        'warning': '#f6a254', // orange
        'error': '#6f1f1f', // dark maroon vs bright red for contrast
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
        'error': '#5a1d1d', // darker for visibility
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
      // Greyscale palette for complete color blindness
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
      // Original/default palette used previously
      return {
        'ok': '#2e7d32', // green
        'warning': '#ff9800', // orange
        'error': '#d32f2f', // red
        'stale': '#9e9e9e', // grey
        'down': '#6a1b9a', // purple
        'nav': '#1976d2', // original blue
        'navBorder': '#145ea8',
        'bg': '#ffffff',
        'text': '#000000',
        'bgButton': '#ffffff',
        'buttonBorder': '#cfd8dc',
      };
  }
}

// Build a ColorFilter matrix for the given ColorVisionMode suitable for ColorFiltered.
ColorFilter _colorFilterForMode(ColorVisionMode mode) {
  // Identity (no change)
  const identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  // Boost blue / reduce red to help protan/deutan users differentiate
  const blueBoost = <double>[
    0.7, 0.1, 0.2, 0, 0, //
    0.1, 0.8, 0.1, 0, 0, //
    0.05, 0.05, 0.9, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  // Mild desaturate and contrast (for anomalous types)
  const desaturate = <double>[
    0.6, 0.25, 0.15, 0, 0, //
    0.2, 0.6, 0.2, 0, 0, //
    0.15, 0.25, 0.6, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  // Greyscale matrix for achromatopsia
  const greyscale = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
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

// Helper: convert hex string like "#rrggbb" to Color
Color _hexToColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('ff$cleaned', radix: 16));
}
// Full updated HomePage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

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

// Defaults
const int DEFAULT_REFRESH_SECONDS = 60; // 1 minute default
const int DEFAULT_STALE_MINUTES_CONN = 5; // 5 minutes default for connection
const int DEFAULT_STALE_MINUTES_REP = 5; // 5 minutes default for report
const double DEFAULT_VARIANCE_PERCENT = 10.0; // 10% change -> warning
const int PROGRESS_ANIMATION_SECONDS = 10; // progress bar fill time

// External API citations (kept as comments for maintainers)
// Open-Meteo API (forecast/current_weather) — docs: https://open-meteo.com/
// USGS Earthquake API (FDSN Event query, GeoJSON) — docs: https://earthquake.usgs.gov/fdsnws/event/1/

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

  // track per-source progress start times to animate 10s fill
  final Map<String, DateTime> _progressStart = {};

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
    await _generateMockData();
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

    final storedInterval = prefs.getInt(PREFS_REFRESH_INTERVAL);
    _refreshSeconds = storedInterval ?? DEFAULT_REFRESH_SECONDS;

    final storedSourceSettings = prefs.getString(PREFS_SOURCE_SETTINGS);
    if (storedSourceSettings != null) {
      try {
        final decoded = jsonDecode(storedSourceSettings) as Map<String, dynamic>;
        _sourceSettings = decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
      } catch (_) {
        _sourceSettings = {};
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
  }

  Future<void> _clearPersistedAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PREFS_OLD_SNAPSHOT);
    await prefs.remove(PREFS_ERROR_LOG);
    await prefs.remove(PREFS_DAILY_LOG);
    await prefs.remove(PREFS_REFRESH_INTERVAL);
    await prefs.remove(PREFS_SOURCE_SETTINGS);
    oldSnapshot = null;
    _errorLog.clear();
    _dailyLog.clear();
    _sourceSettings.clear();
    setState(() {});
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshSeconds), (timer) async {
      await _onRefreshCycle();
    });
  }

  Future<void> _onRefreshCycle() async {
    await _generateMockData();
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
        'lastConn': s['lastConnUpdated'],
        'lastRep': s['lastRepUpdated'],
        'reportValue': s['reportValue'], // numeric or null
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

  // -----------------------
  // HTTP probe helpers
  // -----------------------

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

  // Map probe to keys and extract a numeric "reportValue" where available
  Map<String, dynamic> _mapProbeToKeysAndValue(String sourceName, Map<String, dynamic>? probeBody, String probeStatus) {
    final connKey = probeStatus;
    String repKey = probeStatus;
    double? reportValue;
    try {
      if (sourceName.contains('Source C')) {
        // Open-Meteo: use temperature in current_weather.temperature as numeric reportValue
        if (probeBody != null && probeBody['current_weather'] != null && probeBody['current_weather']['temperature'] != null) {
          repKey = 'ok';
          final tmp = probeBody['current_weather']['temperature'];
          if (tmp is num) reportValue = tmp.toDouble();
        } else {
          repKey = 'warning';
        }
      } else if (sourceName.contains('Source D')) {
        // USGS: use magnitude of first feature (properties.mag)
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

  Future<void> _generateMockData() async {
    final now = DateTime.now();
    final prev = oldSnapshot ?? {};
    List<Map<String, dynamic>> newSources = [];

    // Helper to mark progress start (for animation)
    void _markProgressStart(String name) {
      _progressStart[name] = DateTime.now();
      // schedule a setState after fill period to allow fading
      Future.delayed(const Duration(seconds: PROGRESS_ANIMATION_SECONDS + 1), () {
        if (mounted) setState(() {});
      });
    }

    // --- Source A (mock) ---
    {
      final name = 'Source A';
      // previous report value (if present)
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null;

      // simulate connection and report
      String connKey = _pickConnKey();
      String repKey = _pickRepKey();

      // simulated numeric report (e.g., a temperature-like number ~ 15-25)
      double reportValue = 15.0 + _rng.nextDouble() * 10.0;
      // introduce occasional repeats (so variance can be low)
      if (_rng.nextDouble() < 0.24 && prevValue != null) {
        reportValue = prevValue;
      }
      // introduce occasional big jumps
      if (_rng.nextDouble() < 0.06) {
        reportValue += (_rng.nextBool() ? 1 : -1) * (5 + _rng.nextDouble() * 10);
      }

      DateTime connTs = now.subtract(Duration(minutes: _rng.nextInt(3)));
      DateTime repTs = now.subtract(Duration(minutes: _rng.nextInt(4)));

      String connDetails = _messageFor(connKey, 'connection', name, connTs);
      String repDetails = 'value: ${reportValue.toStringAsFixed(2)} at ${repTs.toIso8601String()}';

      // read per-source settings
      final settings = _sourceSettings[name];
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int ? settings['staleMinutesConn'] as int : DEFAULT_STALE_MINUTES_CONN;
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int ? settings['staleMinutesRep'] as int : DEFAULT_STALE_MINUTES_REP;
      final variancePercent = settings != null && settings['variancePercent'] is num ? (settings['variancePercent'] as num).toDouble() : DEFAULT_VARIANCE_PERCENT;
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0;
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0;

      // connection staleness
      if (DateTime.now().difference(connTs).inMinutes >= staleMinutesConn && connKey != 'down' && connKey != 'error') {
        final treatConn = settings != null && settings['treatStaleAsConn'] is String ? settings['treatStaleAsConn'] as String : 'stale';
        connKey = treatConn;
        connDetails = _messageFor(treatConn, 'connection', name, connTs);
      }

      // determine report status using variance and due time logic
      String finalRepKey = repKey;
      // variance check
      if (prevValue != null) {
        final diff = (reportValue - prevValue).abs();
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0);
        if (pct >= variancePercent) {
          finalRepKey = 'warning';
        }
      }

      // due time logic
      final dueToday = DateTime(now.year, now.month, now.day, dueHour, dueMinute);
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30));
      final hasRecentReport = repTs.isAfter(dueWindowStart);
      if (now.isBefore(dueToday)) {
        // before due: report is acceptable (unless variance warning)
      } else {
        // now >= due time
        if (!hasRecentReport) {
          // no recent report around due: error
          finalRepKey = 'error';
        } else {
          // report exists but might be late; if repTs after due -> late submission
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
      // within 30 minutes before due but no recent report => warning
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

    // --- Source B (mock) similar to A but different seed ---
    {
      final name = 'Source B';
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null;

      String connKey = _pickConnKey();
      String repKey = _pickRepKey();

      double reportValue = 100.0 * (0.5 + _rng.nextDouble()); // some other metric
      if (_rng.nextDouble() < 0.2 && prevValue != null) reportValue = prevValue;
      if (_rng.nextDouble() < 0.05) reportValue += (_rng.nextBool() ? 1 : -1) * (_rng.nextDouble() * 30);

      DateTime connTs = now.subtract(Duration(minutes: 1 + _rng.nextInt(4)));
      DateTime repTs = now.subtract(Duration(minutes: 2 + _rng.nextInt(6)));

      String connDetails = _messageFor(connKey, 'connection', name, connTs);
      String repDetails = 'value: ${reportValue.toStringAsFixed(2)} at ${repTs.toIso8601String()}';

      final settings = _sourceSettings[name];
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int ? settings['staleMinutesConn'] as int : DEFAULT_STALE_MINUTES_CONN;
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int ? settings['staleMinutesRep'] as int : DEFAULT_STALE_MINUTES_REP;
      final variancePercent = settings != null && settings['variancePercent'] is num ? (settings['variancePercent'] as num).toDouble() : DEFAULT_VARIANCE_PERCENT;
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0;
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0;

      if (DateTime.now().difference(connTs).inMinutes >= staleMinutesConn && connKey != 'down' && connKey != 'error') {
        final treatConn = settings != null && settings['treatStaleAsConn'] is String ? settings['treatStaleAsConn'] as String : 'stale';
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
        // before due => ok/warning based on variance
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

    // --- Source C (Open-Meteo: weather)
    // BACKEND INTEGRATION GUIDE:
    // - Pattern: "HTTP probe → parse JSON → extract numeric 'reportValue' → apply status logic".
    // - Replace this entire block for your real Source C endpoint:
    //   1) Call your API URL (GET/POST as needed).
    //   2) Parse the JSON body.
    //   3) Choose a SINGLE numeric metric to act as 'reportValue' (double).
    //   4) Set 'repKey' to 'ok' if the metric is present/valid, otherwise 'warning' (or 'error' if parsing fails).
    //   5) Leave connection status based on HTTP response/latency; tweak rules as needed.
    // - Where to plug custom logic:
    //   * Extraction: see `_mapProbeToKeysAndValue(...)` for mapping body → report value.
    //   * Variance/due-time/staleness: applied below uniformly across sources.
    // - IMPORTANT: Ensure 'reportValue' is a double (num.toDouble()) and include timestamps to support "late submission" logs.
    {
      final name = 'Source C'; // declare the source name string
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=35.3733&longitude=-119.0187&current_weather=true'; // API URL used for this probe
      // citation: https://open-meteo.com/
      final probe = await _probeUrl(url, timeout: const Duration(seconds: 5)); // perform HTTP GET and measure latency/status
      final latency = probe['latencyMs'] as int? ?? 9999; // read latency from probe result, default large if missing
      final pbody = probe['body'] as Map<String, dynamic>?; // parse JSON body if any (may be null)
      final pstatus = probe['status'] as String; // normalized probe status ('ok', 'warning', 'down', 'error')

      // MAPPING: Take the API body and map into standardized keys + numeric value.
      // For your API, edit `_mapProbeToKeysAndValue` or replicate inline here.
      final mapped = _mapProbeToKeysAndValue(name, pbody, pstatus); // translate probe body/status to our internal keys and value
      String connKeyForCompare = mapped['connection'] ?? 'down'; // connection key to display (default to 'down' if missing)
      String repKeyForCompare = mapped['report'] ?? 'warning'; // report key to display (default 'warning')
      final double? reportValue = mapped['value'] as double?; // numeric report value extracted by mapping (nullable)

      final nowTs = DateTime.now(); // current timestamp used for last-updated fields
      final connDetails = 'connection ${connKeyForCompare.toUpperCase()}: ${latency}ms to Open-Meteo'; // user-facing connection details string
      final repDetails = reportValue != null ? 'value: ${reportValue.toStringAsFixed(2)}' : 'no value'; // user-facing report details string

      // READ SETTINGS: staleness thresholds, variance %, due-time window.
      final settings = _sourceSettings[name]; // per-source settings map if present
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int ? settings['staleMinutesConn'] as int : DEFAULT_STALE_MINUTES_CONN; // conn stale threshold
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int ? settings['staleMinutesRep'] as int : DEFAULT_STALE_MINUTES_REP; // report stale threshold
      final variancePercent = settings != null && settings['variancePercent'] is num ? (settings['variancePercent'] as num).toDouble() : DEFAULT_VARIANCE_PERCENT; // variance threshold
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0; // report due hour
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0; // report due minute

      // CONNECTION STATUS: Example rule — big latency becomes 'warning' even if HTTP 200.
      if (pstatus == 'ok' && latency > 1500) connKeyForCompare = 'warning'; // mark connection as warning if latency high

      // VARIANCE CHECK: Compare current value to previous to flag abnormal jumps/drifts.
      // For your API: pick a meaningful metric; avoid unit changes (e.g., ms→s) between reports.
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null; // previous numeric value if available
      String finalRepKey = repKeyForCompare; // start with mapped report key
      if (reportValue != null && prevValue != null) { // only compute variance if both current and previous available
        final diff = (reportValue - prevValue).abs(); // absolute difference
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0); // percent change vs previous
        if (pct >= variancePercent) finalRepKey = 'warning'; // flag as warning if percent change exceeds threshold
      }

      // DUE-TIME & LATE SUBMISSION:
      // - We treat the current probe time as the "report timestamp".
      // - If now is past the configured due time and no report in the last 30 minutes, mark 'error'.
      // - If a report arrives after due time, we mark status OK/WARNING but log a 'LATE' event.
      final dueToday = DateTime(nowTs.year, nowTs.month, nowTs.day, dueHour, dueMinute); // create today's due time
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30)); // window start to consider "recent"
      final repTs = nowTs; // use now as report timestamp for this probe
      final hasRecentReport = repTs.isAfter(dueWindowStart); // whether the report is recent relative to the due window

      if (nowTs.isBefore(dueToday)) {
        // before due: ok/warning by variance (no action)
      } else {
        if (!hasRecentReport) {
          finalRepKey = 'error'; // if past due and no recent report, mark error
        } else {
          if (repTs.isAfter(dueToday)) {
            _dailyLog.insert(0, {
              'time': DateTime.now().toIso8601String(),
              'description': '$name late report submitted at ${repTs.toIso8601String()}',
              'status': 'LATE'
            }); // log a late submission event in daily log
            if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length); // cap daily log size
          }
        }
      }

      _markProgressStart(name); // mark animation start for this source

      newSources.add({
        'name': name, // source name
        'connectionKey': connKeyForCompare, // final connection key to display
        'reportKey': finalRepKey, // final report key to display
        'connectionIcon': _iconForKey(connKeyForCompare), // icon derived from connection key
        'reportIcon': _iconForKey(finalRepKey), // icon derived from report key
        'connectionDetails': connDetails, // string shown in details dialog
        'reportDetails': repDetails, // string shown in details dialog
        'lastConnUpdated': nowTs.toIso8601String(), // timestamp for last connection update
        'lastRepUpdated': nowTs.toIso8601String(), // timestamp for last report update
        'isUpdatingConn': false, // UI flag for "updating" state
        'isUpdatingRep': false, // UI flag for "updating" state
        'staleMinutesConn': staleMinutesConn, // per-source connection stale threshold saved for UI
        'staleMinutesRep': staleMinutesRep, // per-source report stale threshold saved for UI
        'variancePercent': variancePercent, // per-source variance threshold saved for UI
        'reportDueHour': dueHour, // due hour persisted to settings
        'reportDueMinute': dueMinute, // due minute persisted to settings
        'reportValue': reportValue, // numeric report value extracted (nullable)
      });
    }

    // --- Source D (USGS)
    // BACKEND INTEGRATION GUIDE:
    // - This block demonstrates consuming a JSON feed (GeoJSON) and extracting a single numeric metric ('mag').
    // - For your Source D API, follow this pattern:
    //   1) Probe your endpoint (consider headers/auth if needed).
    //   2) Parse JSON; identify a stable numeric metric to represent the report (e.g., "count", "latencyMs", "cpuPct").
    //   3) Map status:
    //      - 'connectionKey': derived from HTTP success + latency rules.
    //      - 'reportKey': 'ok' if metric present; 'warning' if partial/missing; 'error' if parsing failed.
    //   4) Variance/due-time logic is shared and already applied below.
    // - If your response is an array:
    //   * Pick first or aggregate (avg/sum) — be consistent to avoid variance noise.
    // - Make sure to:
    //   * Convert metric to double.
    //   * Set timestamps to support late logging.
    //   * Keep units consistent (avoid mixing seconds/ms or % vs fractions).
    {
      final name = 'Source D'; // declare source name for lookup and storage
      final startIso = DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(); // compute start time for query parameter
      final url = 'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&limit=1&starttime=$startIso'; // build USGS query URL
      // citation: https://earthquake.usgs.gov/fdsnws/event/1/
      final probe = await _probeUrl(url, timeout: const Duration(seconds: 5)); // execute HTTP probe with timeout
      final latency = probe['latencyMs'] as int? ?? 9999; // extract latency measured by probe
      final pbody = probe['body'] as Map<String, dynamic>?; // probe JSON body mapped to Map if available
      final pstatus = probe['status'] as String; // normalized probe status string

      // MAPPING: body → standardized conn/report + numeric value.
      final mapped = _mapProbeToKeysAndValue(name, pbody, pstatus); // use mapping helper to extract keys/value
      String connKeyForCompare = mapped['connection'] ?? 'down'; // connection key fallback
      String repKeyForCompare = mapped['report'] ?? 'warning'; // report key fallback
      final double? reportValue = mapped['value'] as double?; // numeric metric extracted, may be null

      final nowTs = DateTime.now(); // timestamp for this probe
      final connDetails = 'connection ${connKeyForCompare.toUpperCase()}: ${latency}ms to USGS'; // connection detail string
      final repDetails = reportValue != null ? 'magnitude: ${reportValue.toStringAsFixed(2)}' : 'no events'; // report detail string

      // READ SETTINGS: thresholds that control staleness/variance/due-time behavior.
      final settings = _sourceSettings[name]; // load per-source settings if present
      final staleMinutesConn = settings != null && settings['staleMinutesConn'] is int ? settings['staleMinutesConn'] as int : DEFAULT_STALE_MINUTES_CONN; // conn stale threshold
      final staleMinutesRep = settings != null && settings['staleMinutesRep'] is int ? settings['staleMinutesRep'] as int : DEFAULT_STALE_MINUTES_REP; // rep stale threshold
      final variancePercent = settings != null && settings['variancePercent'] is num ? (settings['variancePercent'] as num).toDouble() : DEFAULT_VARIANCE_PERCENT; // variance threshold
      final dueHour = settings != null && settings['reportDueHour'] is int ? settings['reportDueHour'] as int : 0; // due hour
      final dueMinute = settings != null && settings['reportDueMinute'] is int ? settings['reportDueMinute'] as int : 0; // due minute

      // CONNECTION RULE (example): if latency exceeds threshold, mark 'warning'.
      if (pstatus == 'ok' && latency > 1500) connKeyForCompare = 'warning'; // escalate to warning if latency high

      // VARIANCE RULE: compare metric to previous reading to detect sudden changes.
      final prevValue = prev.containsKey(name) ? (prev[name]['reportValue'] as num?)?.toDouble() : null; // previous metric value
      String finalRepKey = repKeyForCompare; // start with mapped report key
      if (reportValue != null && prevValue != null) { // only evaluate if both current and previous exist
        final diff = (reportValue - prevValue).abs(); // absolute diff
        final pct = prevValue == 0 ? (diff > 0 ? 100.0 : 0.0) : (diff / prevValue * 100.0); // percent change
        if (pct >= variancePercent) finalRepKey = 'warning'; // set warning if percent change exceeds threshold
      }

      // DUE-TIME & LATE SUBMISSION: identical behavior to Source C.
      final dueToday = DateTime(nowTs.year, nowTs.month, nowTs.day, dueHour, dueMinute); // today's due datetime
      final dueWindowStart = dueToday.subtract(const Duration(minutes: 30)); // recent window start
      final repTs = nowTs; // current probe timestamp
      final hasRecentReport = repTs.isAfter(dueWindowStart); // whether report is recent enough

      if (nowTs.isBefore(dueToday)) {
        // before due: ok/warning
      } else {
        if (!hasRecentReport) {
          finalRepKey = 'error'; // mark error if past due and no recent report
        } else {
          if (repTs.isAfter(dueToday)) {
            _dailyLog.insert(0, {
              'time': DateTime.now().toIso8601String(),
              'description': '$name late report submitted at ${repTs.toIso8601String()}',
              'status': 'LATE'
            }); // log LATE event
            if (_dailyLog.length > 2000) _dailyLog.removeRange(2000, _dailyLog.length); // cap size
          }
        }
      }

      _markProgressStart(name); // animate progress for this source

      newSources.add({
        'name': name, // source identifier
        'connectionKey': connKeyForCompare, // final connection status
        'reportKey': finalRepKey, // final report status
        'connectionIcon': _iconForKey(connKeyForCompare), // icon mapping for connection
        'reportIcon': _iconForKey(finalRepKey), // icon mapping for report
        'connectionDetails': connDetails, // human-readable connection details
        'reportDetails': repDetails, // human-readable report details
        'lastConnUpdated': nowTs.toIso8601String(), // last connection timestamp
        'lastRepUpdated': nowTs.toIso8601String(), // last report timestamp
        'isUpdatingConn': false, // UI flag
        'isUpdatingRep': false, // UI flag
        'staleMinutesConn': staleMinutesConn, // persisted conn stale threshold
        'staleMinutesRep': staleMinutesRep, // persisted rep stale threshold
        'variancePercent': variancePercent, // persisted variance threshold
        'reportDueHour': dueHour, // persisted due hour
        'reportDueMinute': dueMinute, // persisted due minute
        'reportValue': reportValue, // numeric value extracted from API
      });
    }

    sources = newSources;
  }

  // -----------------------
  // Utility helpers (icons, messages, progress)
  // -----------------------

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

  double _computeProgressToStale(String? lastIso, int staleMinutes, String name) {
    // Progress should animate fill for PROGRESS_ANIMATION_SECONDS when an update occurs,
    // and simultaneously indicate time elapsed toward staleness.
    // We'll combine two components:
    //  - recent update animation: uses _progressStart[name] to animate 0->1 over PROGRESS_ANIMATION_SECONDS
    //  - aging progress: elapsed / (staleMinutes*60) clipped 0..1
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
    // Combine: show animation prominently for the initial period, then fall back to agingPart
    if (animationPart < 1.0) {
      // during animation, blend: 70% animation + 30% aging
      return (0.7 * animationPart + 0.3 * agingPart).clamp(0.0, 1.0);
    } else {
      // after animation finishes, show aging
      return agingPart;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return 'never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'unknown';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // -----------------------
  // UI: build, dialogs, settings
  // -----------------------

  // Build a tappable title that:
  // - loads assets/logo.png then assets/logo.jpg;
  // - if an image loads, shows the image only (no extra text);
  // - if no image found, shows left-aligned "DataWatch" text;
  // - on phones (<=600dp) gives the title up to 50% of screen width;
  // - on larger screens uses 1/8 width and also shows the label text to the right.
  Widget _buildLogoTitleButton() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isPhone = screenWidth <= 600.0;
    final double widthFactor = isPhone ? 0.20 : 0.125;
    final double maxWidth = screenWidth * widthFactor;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutPage()),
        );
      },
      child: Container(
        height: 44,
        width: maxWidth,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white, // ✅ white background behind the logo
          borderRadius: BorderRadius.circular(6),
        ),
        child: Image.asset(
          'assets/nav_logo.png',
          fit: BoxFit.contain,
          height: 40,
          errorBuilder: (ctx, err, stack) => const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'DataWatch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Ensure title has predictable spacing and doesn't get auto-centered/trimmed.
        titleSpacing: 0,        // allow title to start near the left edge
        centerTitle: false,     // left-align title (typical for large screens / Android)
        leadingWidth: 56,       // reserve standard space for a potential leading widget
        toolbarHeight: 56,      // consistent height for the AppBar
        title: _buildLogoTitleButton(),
        backgroundColor: Colors.blue,
        actions: [
          // Responsive: show full actions on wide screens, collapse to a menu on narrow screens
          LayoutBuilder(
            builder: (context, constraints) {
              final double screenWidth = MediaQuery.of(context).size.width;
              // Treat widths <= 600 as phone ranges; you can lower to 480 if preferred.
              // S24 Ultra width in logical pixels typically <= 412 dp in portrait; 600 is safe.
              final bool isPhone = screenWidth <= 600.0;

              if (!isPhone && constraints.maxWidth > 700) {
                // Desktop / wide tablet → full action row
                return Row(children: [
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
                    icon: const Icon(Icons.settings, color: Colors.white),
                    tooltip: 'Settings',
                    onPressed: () => _openGlobalSettings(context),
                  ),
                  IconButton(
                    onPressed: () async {
                      await _clearPersistedAll();
                    },
                    icon: const Icon(Icons.delete_sweep, color: Colors.white),
                    tooltip: 'Clear persisted snapshot and logs',
                  ),
                  IconButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('loggedIn', false);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (Route<dynamic> route) => false,
                      );
                    },
                    icon: const Icon(Icons.logout, color: Colors.white),
                    tooltip: 'Logout',
                  ),
                ]);
              } else {
                // Phone or narrow width → collapsed popup menu
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
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
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('loggedIn', false);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (Route<dynamic> route) => false,
                      );
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
          // On wide screens (desktop), keep 1/8 empty space on both sides ⇒ content width = 3/4 of screen.
          // On mobile, allow more width (e.g., 95%) for comfortable use.
          final bool isWide = constraints.maxWidth >= 800;
          final double widthFactor = isWide ? 0.75 : 0.95; // 0.75 leaves 12.5% per side

          return Center(
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              child: Padding(
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
                              final lastConn = s['lastConnUpdated'] as String?;
                              final lastRep = s['lastRepUpdated'] as String?;
                              final isUpdConn = s['isUpdatingConn'] as bool? ?? false;
                              final isUpdRep = s['isUpdatingRep'] as bool? ?? false;
                              final staleMinutesConn = s['staleMinutesConn'] as int? ?? DEFAULT_STALE_MINUTES_CONN;
                              final staleMinutesRep = s['staleMinutesRep'] as int? ?? DEFAULT_STALE_MINUTES_REP;

                              final connProgress = _computeProgressToStale(lastConn, staleMinutesConn, name);
                              final repProgress = _computeProgressToStale(lastRep, staleMinutesRep, name);

                              return Column(children: [
                                Row(children: [
                                  SizedBox(
                                    width: 140,
                                    child: Row(children: [
                                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                      IconButton(
                                        icon: const Icon(Icons.settings, size: 18),
                                        tooltip: 'Source settings',
                                        onPressed: () => _openPerSourceSettings(context, name),
                                      ),
                                    ]),
                                  ),
                                  Expanded(
                                    child: Column(children: [
                                      Row(children: [
                                        Expanded(
                                          child: LinearProgressIndicator(
                                            value: connProgress,
                                            color: _colorForKey(connKey),
                                            backgroundColor: _colorForKey(connKey).withOpacity(0.2),
                                            minHeight: 6,
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: 6),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          side: const BorderSide(color: Colors.black45),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                        onPressed: () {
                                          _showDetailsDialog(context, '$name - Connection', connDetails, connKey, lastConn, isUpdConn);
                                        },
                                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Icon(connIcon, color: _colorForKey(connKey)),
                                          const SizedBox(width: 8),
                                          Text(connKey.toUpperCase(), style: TextStyle(color: _colorForKey(connKey))),
                                        ]),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${_formatTime(lastConn)} ${isUpdConn ? " • Updating..." : ""}', style: const TextStyle(fontSize: 12)),
                                    ]),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(children: [
                                      Row(children: [
                                        Expanded(
                                          child: LinearProgressIndicator(
                                            value: repProgress,
                                            color: _colorForKey(repKey),
                                            backgroundColor: _colorForKey(repKey).withOpacity(0.2),
                                            minHeight: 6,
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: 6),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          side: const BorderSide(color: Colors.black45),
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                        onPressed: () {
                                          _showDetailsDialog(context, '$name - Report', repDetails, repKey, lastRep, isUpdRep);
                                        },
                                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Icon(repIcon, color: _colorForKey(repKey)),
                                          const SizedBox(width: 8),
                                          Text(repKey.toUpperCase(), style: TextStyle(color: _colorForKey(repKey))),
                                        ]),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${_formatTime(lastRep)} ${isUpdRep ? " • Updating..." : ""}', style: const TextStyle(fontSize: 12)),
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

  // Per-source settings dialog with both slider and number input fields
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

    // Controllers for numeric text inputs
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

  void _openGlobalSettings(BuildContext context) {
    int refreshSeconds = _refreshSeconds;
    final refreshCtrl = TextEditingController(text: refreshSeconds.toString());

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
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              TextButton(onPressed: () async {
                _parseRefresh();
                _refreshSeconds = refreshSeconds;
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
}

// -----------------------
// Error and Log Pages
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

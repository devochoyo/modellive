import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';

// Crash diagnostics for the live stream.
//
// WHY: when the app "closes by itself" the cause is usually a NATIVE crash
// (in the camera / microphone / WebRTC code). Dart cannot catch those, so the
// normal console shows nothing. This service writes every step of going live
// to the console AND to a file on the phone straight away. After the app dies
// and you open it again, it prints that file to the console (look for
// "MODELLIVE CRASH REPORT") and shows the same report on screen, with a Copy
// button, together with Android's own reason for the process death.
//
// Live (while running) console output: filter by  MODELLIVE-DIAG
// Native (logcat) output:  adb logcat -s ModelLive
class Diagnostics {
  static const MethodChannel _channel =
      MethodChannel('com.modellive.app/diagnostics');

  static bool get _enabled => !kIsWeb && Platform.isAndroid;

  static String _ts() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.'
        '${n.millisecond.toString().padLeft(3, '0')}';
  }

  // ---------- Logging ----------

  // Plain print(): always reaches the console, in debug AND release, and is
  // never throttled or dropped. Long text is split so nothing is cut off.
  static void _print(String text) {
    for (final line in text.split('\n')) {
      if (line.length <= 900) {
        // ignore: avoid_print
        print(line);
      } else {
        for (int i = 0; i < line.length; i += 900) {
          // ignore: avoid_print
          print(line.substring(i, i + 900 > line.length ? line.length : i + 900));
        }
      }
    }
  }

  // Fire-and-forget log line (console + file).
  static void log(String tag, String message) {
    final line = '[${_ts()}] [$tag] $message';
    _print('MODELLIVE-DIAG $line');
    if (!_enabled) return;
    unawaited(_channel.invokeMethod<void>('log', line).catchError((_) {}));
  }

  // Same, but waits until the line is safely written to disk. Use it right
  // BEFORE a step that might kill the app, so the line is never lost.
  static Future<void> logNow(String tag, String message) async {
    final line = '[${_ts()}] [$tag] $message';
    _print('MODELLIVE-DIAG $line');
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>('log', line);
    } catch (_) {}
  }

  // Starts a fresh log for one live attempt ("host" or "viewer").
  static Future<void> beginSession(String kind) async {
    if (_enabled) {
      try {
        await _channel.invokeMethod<void>('resetSteps');
      } catch (_) {}
    }
    await logNow('SESSION', 'BEGIN $kind live session');
    final info = await deviceInfo();
    await logNow('DEVICE', info.isEmpty ? 'unknown' : info.toString());
  }

  // Marks the attempt as finished normally (or failed in a way the app
  // handled). If this line is missing on the next launch, the app died.
  static Future<void> endSession(String how) async {
    await logNow('SESSION', 'END ($how)');
  }

  static Future<Map<String, dynamic>> deviceInfo() async {
    if (!_enabled) return {};
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('deviceInfo');
      return map ?? {};
    } catch (_) {
      return {};
    }
  }

  // Android version number (API level), 0 when unknown / not Android.
  static Future<int> androidSdk() async {
    final info = await deviceInfo();
    final v = info['sdkInt'];
    return v is int ? v : 0;
  }

  // ---------- Dart errors ----------

  // Sends every uncaught Dart error to the log too.
  static void installErrorHooks() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      log('DART-ERROR', '${details.exceptionAsString()}\n${details.stack}');
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log('DART-ERROR', 'Uncaught: $error\n$stack');
      return false; // still reported to the console as usual
    };
  }

  // ---------- Report after a crash ----------

  static bool _checked = false;

  // Call once at start-up. If the last run died, prints a full report to the
  // console and shows it on screen.
  static Future<void> checkPreviousRun() async {
    if (_checked || !_enabled) return;
    _checked = true;
    try {
      final steps = (await _channel.invokeMethod<String>('readSteps')) ?? '';
      final crash = (await _channel.invokeMethod<String>('consumeCrash')) ?? '';
      final exits =
          (await _channel.invokeListMethod<dynamic>('consumeExitInfo')) ??
              <dynamic>[];

      final hadLiveSession = steps.contains('BEGIN ');
      final unfinished = hadLiveSession && !steps.contains('] [SESSION] END');
      bool crashLike = false;
      for (final e in exits) {
        final r = (e is Map ? e['reason'] : '')?.toString() ?? '';
        if (r.startsWith('CRASH') ||
            r.startsWith('ANR') ||
            r.startsWith('SIGNALED') ||
            r.startsWith('LOW_MEMORY') ||
            r.startsWith('INITIALIZATION') ||
            r.startsWith('PERMISSION_CHANGE') ||
            r.startsWith('EXCESSIVE')) {
          crashLike = true;
        }
      }

      if (!(unfinished || crash.isNotEmpty || crashLike)) {
        // Previous run was clean: forget it.
        await _channel.invokeMethod<void>('resetSteps');
        return;
      }

      final b = StringBuffer()
        ..writeln('MODELLIVE CRASH REPORT')
        ..writeln('The previous run of the app did not end normally.')
        ..writeln();

      if (unfinished) {
        final lines = steps
            .split('\n')
            .where((l) => l.trim().isNotEmpty && !l.contains('[NATIVE] Activity'))
            .toList();
        final lastLine = lines.isNotEmpty ? lines.last : '(none)';
        b
          ..writeln('LAST STEP BEFORE THE APP DIED:')
          ..writeln(lastLine)
          ..writeln();
      }

      if (crash.isNotEmpty) {
        b
          ..writeln('JAVA/KOTLIN EXCEPTION THAT KILLED THE APP:')
          ..writeln(crash.trim())
          ..writeln();
      }

      if (exits.isNotEmpty) {
        b.writeln('ANDROID PROCESS-EXIT RECORD:');
        for (final e in exits) {
          if (e is! Map) continue;
          b
            ..writeln('- time: ${e['timestamp']}')
            ..writeln('  reason: ${e['reason']}')
            ..writeln('  description: ${e['description']}')
            ..writeln('  status: ${e['status']}');
          final trace = (e['trace'] ?? '').toString();
          if (trace.isNotEmpty) {
            b
              ..writeln('  native dump (readable text only):')
              ..writeln(trace);
          }
        }
        b.writeln();
      }

      if (steps.trim().isNotEmpty) {
        b
          ..writeln('FULL STEP LOG:')
          ..writeln(steps.trim());
      }

      final report = b.toString();
      _print('\n==================== MODELLIVE CRASH REPORT ====================');
      _print(report);
      _print('================== END MODELLIVE CRASH REPORT ==================\n');

      // Reported: clear so it is not shown again.
      await _channel.invokeMethod<void>('resetSteps');
      await _showReport(report);
    } catch (e) {
      _print('MODELLIVE-DIAG could not read the previous run: $e');
    }
  }

  static Future<void> _showReport(String report) async {
    // Wait until the app has a screen to show the dialog on.
    BuildContext? ctx;
    for (int i = 0; i < 30; i++) {
      ctx = ApiService.navigatorKey.currentState?.overlay?.context;
      if (ctx != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (ctx == null) return;

    await showDialog<void>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: const Text('The app closed unexpectedly'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) {
                ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                  const SnackBar(content: Text('Report copied')),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

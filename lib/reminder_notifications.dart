import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void> _queue = Future.value();
  static bool _ready = false;
  static bool _asked = false;

  static Future<void> sync(List<Map<String, String>> entries) {
    if (kIsWeb ||
        ![
          TargetPlatform.iOS,
          TargetPlatform.android,
        ].contains(defaultTargetPlatform)) {
      return Future.value();
    }
    _queue = _queue.then((_) => _sync(entries)).catchError((Object error) {
      debugPrint(
        'Reminder notification scheduling failed: ${error.runtimeType}',
      );
    });
    return _queue;
  }

  static Future<void> _sync(List<Map<String, String>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'scheduled_family_reminders';
    final saved = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(key) ?? '{}') as Map,
    );
    final timed = entries
        .where(
          (e) =>
              e['kind'] == 'reminder' &&
              RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$')
                  .hasMatch(e['time'] ?? ''),
        )
        .toList();
    if (timed.isEmpty && saved.isEmpty) return;
    if (!_ready) {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      _ready = true;
    }
    if (timed.isNotEmpty && !_asked) {
      _asked = true;
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
    }
    final zone = tz.getLocation(
      (await FlutterTimezone.getLocalTimezone()).identifier,
    );
    final now = tz.TZDateTime.now(zone);
    final pending = (await _plugin.pendingNotificationRequests()).asMap().map(
      (_, n) => MapEntry(n.id, n.payload),
    );
    final desired = <String, dynamic>{};
    for (final e in timed) {
      final signature = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                e['label'],
                e['value'],
                e['location'],
                e['time'],
                e['repeat'],
              ]),
            ),
          )
          .toString();
      final id = int.parse(signature.substring(0, 7), radix: 16);
      final daily = e['repeat'] == 'daily';
      final parts = e['time']!.split(':').map(int.parse).toList();
      var next = tz.TZDateTime(
        zone,
        now.year,
        now.month,
        now.day,
        parts.first,
        parts.last,
      );
      if (!next.isAfter(now)) {
        next = tz.TZDateTime(
          zone,
          now.year,
          now.month,
          now.day + 1,
          parts.first,
          parts.last,
        );
      }
      final previous = saved[signature] as int?;
      if (!daily && previous != null) {
        next = tz.TZDateTime.fromMillisecondsSinceEpoch(zone, previous);
      }
      desired[signature] = next.millisecondsSinceEpoch;
      if (!daily && !next.isAfter(now)) continue;
      if (pending.containsKey(id) &&
          pending[id] == null &&
          previous == next.millisecondsSinceEpoch) {
        continue;
      }
      await _plugin.zonedSchedule(
        id: id,
        title: e['label'],
        body: [
          e['value'],
          e['location'],
        ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
        scheduledDate: next,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'family_reminders',
            '家人提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: daily ? DateTimeComponents.time : null,
      );
      saved[signature] = next.millisecondsSinceEpoch;
      await prefs.setString(key, jsonEncode(saved));
    }
    for (final stale in saved.keys.where((s) => !desired.containsKey(s))) {
      await _plugin.cancel(id: int.parse(stale.substring(0, 7), radix: 16));
    }
    if (!mapEquals(saved, desired)) {
      await prefs.setString(key, jsonEncode(desired));
    }
  }
}

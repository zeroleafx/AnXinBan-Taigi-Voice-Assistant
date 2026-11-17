import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deliberately local: pending edits and the elder's applied copy are separate.
class FamilyDemoStore {
  final preferences = DemoPreferences();
  Future<List<Map<String, String>>> read(String copy) async {
    final raw = await preferences.getString('family_demo_$copy');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  Future<void> write(String copy, List<Map<String, String>> entries) =>
      preferences.setString('family_demo_$copy', jsonEncode(entries));
  Future<void> apply() async {
    await write('applied', await read('pending'));
    await preferences.setString(
      'family_demo_applied_at',
      DateTime.now().toIso8601String(),
    );
  }

  Future<bool> hasPin() async =>
      await preferences.getString('family_demo_pin') != null;
  String digest(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
  Future<void> setPin(String pin) async {
    final salt = base64UrlEncode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    );
    await preferences.setString(
      'family_demo_pin',
      '$salt:${digest(salt, pin)}',
    );
  }

  Future<bool> unlock(String pin) async {
    final until = await preferences.getInt('family_demo_locked_until') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < until) return false;
    final stored = await preferences.getString('family_demo_pin');
    if (stored == null) return false;
    final split = stored.split(':');
    if (digest(split.first, pin) == split.last) {
      await preferences.setInt('family_demo_attempts', 0);
      return true;
    }
    final count = (await preferences.getInt('family_demo_attempts') ?? 0) + 1;
    await preferences.setInt('family_demo_attempts', count >= 5 ? 0 : count);
    if (count >= 5) {
      await preferences.setInt(
        'family_demo_locked_until',
        DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
    }
    return false;
  }
}

/// Local prototype storage; not an account or production credential vault.
class DemoPreferences {
  Future<String?> getString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  Future<int?> getInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key);
  Future<void> setString(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Write failed');
    }
  }

  Future<void> setInt(String key, int value) async {
    if (!await (await SharedPreferences.getInstance()).setInt(key, value)) {
      throw StateError('Write failed');
    }
  }
}

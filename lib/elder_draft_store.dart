import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ElderDraftStore {
  static String key(String owner, String link) => 'elder_draft_${owner}_$link';
  Future<Map<String, dynamic>?> read(String owner, String link) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      key(owner, link),
    );
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> save(
    String owner,
    String link,
    List<Map<String, String>> entries,
    int revision,
  ) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      key(owner, link),
      jsonEncode({'entries': entries, 'revision': revision}),
    );
    if (!ok) throw StateError('Draft save failed');
  }

  Future<void> prune(String owner, Set<String> activeLinks) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'elder_draft_${owner}_';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      if (!activeLinks.contains(key.substring(prefix.length))) {
        if (!await prefs.remove(key)) throw StateError('Draft cleanup failed');
      }
    }
  }
}

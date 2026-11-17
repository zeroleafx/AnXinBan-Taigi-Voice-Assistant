import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import 'family_demo_store.dart';

class FamilyPublishException implements Exception {
  const FamilyPublishException(this.message);
  final String message;
}

bool sameFamilySettings(List<dynamic> saved, List<Map<String, String>> draft) =>
    saved.length == draft.length &&
    Iterable<int>.generate(draft.length).every(
      (i) =>
          saved[i] is Map &&
          mapEquals(Map<String, dynamic>.from(saved[i] as Map), draft[i]),
    );

class SecureAuthStorage extends LocalStorage {
  const SecureAuthStorage();
  static const storage = FlutterSecureStorage();
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() => storage.read(key: 'supabase_session');
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: 'supabase_session', value: persistSessionString);
  @override
  Future<void> removePersistedSession() =>
      storage.delete(key: 'supabase_session');
}

class FamilyCloud {
  static bool available = false;
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://ewiszwajtzaamswjoosb.supabase.co',
      publishableKey: 'sb_publishable_nVvrsnwDoCAl_2tLjyxhlw_5KjxCYe1',
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureAuthStorage(),
      ),
    );
    available = true;
  }

  SupabaseClient get client => Supabase.instance.client;
  String? get user => client.auth.currentUser?.id;
  Future<void> login() async {
    if (client.auth.currentSession != null) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final oauth = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: 'com.anxinban.app://login-callback/',
      );
      final callback = await const MethodChannel('anxinban/auth')
          .invokeMethod<String>('signIn', {'url': oauth.url});
      if (callback != null) {
        await client.auth.getSessionFromUrl(Uri.parse(callback));
      }
      return;
    }
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.anxinban.app://login-callback/',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<Map<String, dynamic>?> snapshot(String owner) => client
      .from('family_snapshots')
      .select()
      .eq('owner_id', owner)
      .maybeSingle();
  Future<List<Map<String, dynamic>>> links() =>
      client.from('family_device_links').select();
  Future<String> invite() async =>
      await client.rpc('create_family_invitation') as String;
  Future<void> pair(String code) async {
    await client.rpc('accept_family_invitation', params: {'code': code.trim()});
  }

  Future<int> publish(List<Map<String, String>> entries, int revision) async {
    final owner = user;
    if (owner == null) throw const FamilyPublishException('請先登入');
    if (!(await links()).any((link) => link['owner_id'] == owner)) {
      throw const FamilyPublishException('請先與長輩完成配對，再發佈設定');
    }
    final remote = await snapshot(owner);
    if (remote != null &&
        sameFamilySettings(remote['entries'] as List, entries)) {
      return (remote['revision'] as num).toInt();
    }
    if (((remote?['revision'] as num?)?.toInt() ?? 0) != revision) {
      throw const FamilyPublishException('雲端設定已更新，請重新進入家人設定後再編輯');
    }
    return (await client.rpc(
      'publish_family_settings',
      params: {'items': entries, 'expected_revision': revision},
    ) as num).toInt();
  }

  Future<void> pull() async {
    if (user == null) return;
    final matches = (await links())
        .where((e) => e['elder_id'] == user)
        .toList();
    if (matches.isEmpty) {
      await FamilyDemoStore().write('applied', []);
      return;
    }
    final data = await snapshot(matches.single['owner_id'] as String);
    if (data == null) {
      await FamilyDemoStore().write('applied', []);
      return;
    }
    final entries = (data['entries'] as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
    await FamilyDemoStore().write('applied', entries);
    await client.rpc(
      'ack_family_settings',
      params: {'version': data['revision']},
    );
  }

  Future<void> deleteCloudSettings() async {
    await client.rpc('delete_family_settings');
    await FamilyDemoStore().write('pending', []);
  }
}

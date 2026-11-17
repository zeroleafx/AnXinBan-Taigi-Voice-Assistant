import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_demo_store.dart';

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

  Future<int> publish(List<Map<String, String>> entries, int revision) async =>
      (await client.rpc(
        'publish_family_settings',
        params: {'items': entries, 'expected_revision': revision},
      ) as num).toInt();
  Future<void> pull() async {
    if (user == null) return;
    final matches = (await links())
        .where((e) => e['elder_id'] == user)
        .toList();
    if (matches.isEmpty) return;
    final data = await snapshot(matches.single['owner_id'] as String);
    if (data == null) return;
    final entries = (data['entries'] as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
    await FamilyDemoStore().write('applied', entries);
    await client.rpc(
      'ack_family_settings',
      params: {'version': data['revision']},
    );
  }
}

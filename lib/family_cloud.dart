import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import 'package:google_sign_in/google_sign_in.dart';

import 'family_demo_store.dart';

class FamilyPublishException implements Exception {
  const FamilyPublishException(this.message);
  final String message;
}

/// An elder's request to link, waiting for the family. Both phones show
/// [confirmCode]; the family allows the link only when the two match.
class PairingRequest {
  const PairingRequest({required this.id, required this.confirmCode});
  final String id;
  final String confirmCode;
}

enum PairingStatus { pending, approved, rejected, expired }

/// What to tell the elder when a pairing code is not taken.
String pairingErrorMessage(Object? error) => switch (error) {
  'rate_limited' => '嘗試次數過多，請 10 分鐘後再試',
  'already_paired' => '此裝置已配對，請先解除原本的連結',
  'busy' => '這組配對碼正在等家人確認，請家人先在手機上處理',
  _ => '配對碼不正確或已過期，請家人重新產生',
};

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
  static final _androidGoogleReady = GoogleSignIn.instance.initialize(
    serverClientId: '506241788833-j6jbs2fgo74ijhhfhi40kiq1c99okfmt.apps.googleusercontent.com',
  );
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
  bool get hasFamilyAccount =>
      client.auth.currentUser != null && !client.auth.currentUser!.isAnonymous;
  Future<void> ensureElderIdentity() async {
    if (hasFamilyAccount) {
      throw const FamilyPublishException('請先登出家人帳號，再使用長輩模式');
    }
    if (client.auth.currentSession == null) {
      await client.auth.signInAnonymously();
    }
  }

  Future<void> login() async {
    if (hasFamilyAccount) return;
    final elder = client.auth.currentUser;
    if (elder != null && elder.isAnonymous) {
      final pairings = await links().timeout(const Duration(seconds: 5));
      if (user != elder.id) return;
      if (pairings.any((link) => link['elder_id'] == elder.id)) {
        throw const FamilyPublishException('請先在原家人端解除這支手機的長輩配對，再登入家人模式');
      }
      final store = FamilyDemoStore();
      await store.write('applied', []);
      await store.preferences.setString('paired_elder_user', '');
      if (user != elder.id) return;
      await client.auth.signOut(scope: SignOutScope.local);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _androidGoogleReady;
      try {
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const FamilyPublishException('未取得 Google 登入憑證，請再試一次');
        }
        await client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
      } on GoogleSignInException catch (error) {
        if (error.code != GoogleSignInExceptionCode.canceled) rethrow;
      }
      return;
    }
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
      await client.rpc('create_short_family_invitation') as String;

  /// The elder enters the family's code. A correct code does not link yet:
  /// it asks the family, who compares the returned number before allowing.
  Future<PairingRequest> requestPairing(String code) async {
    final result = await client.rpc(
      'request_family_pairing',
      params: {'code': code.trim()},
    ) as Map;
    final id = result['request_id'];
    final confirmCode = result['confirm_code'];
    if (result['pending'] != true || id is! String || confirmCode is! String) {
      throw FamilyPublishException(pairingErrorMessage(result['error']));
    }
    return PairingRequest(id: id, confirmCode: confirmCode);
  }

  /// What the family decided about this phone's request so far.
  Future<PairingStatus> pairingStatus(String requestId) async {
    final result = await client.rpc(
      'pairing_request_status',
      params: {'request_id': requestId},
    ) as Map;
    return switch (result['status']) {
      'pending' => PairingStatus.pending,
      'approved' => PairingStatus.approved,
      'rejected' => PairingStatus.rejected,
      _ => PairingStatus.expired,
    };
  }

  /// Opens the recorder directly from now on, as for any paired elder.
  Future<void> rememberPairing() =>
      FamilyDemoStore().preferences.setString('paired_elder_user', user!);

  /// Elder phones waiting for this family, newest first.
  Future<List<PairingRequest>> pendingPairings() async {
    final result = await client.rpc('pending_pairing_requests') as Map;
    return [
      for (final row in (result['requests'] as List? ?? const []))
        PairingRequest(
          id: (row as Map)['id'] as String,
          confirmCode: row['confirm_code'] as String,
        ),
    ];
  }

  Future<void> approvePairing(String requestId) async {
    final result = await client.rpc(
      'approve_pairing_request',
      params: {'request_id': requestId},
    ) as Map;
    if (result['ok'] != true) {
      throw FamilyPublishException(switch (result['error']) {
        'expired' => '這組配對碼已過期，請重新產生',
        'already_paired' => '這支長輩手機已經連結其他家人',
        _ => '這個連結請求已經不存在',
      });
    }
  }

  /// Refuses the request; the code it used stops working.
  Future<void> rejectPairing(String requestId) async {
    await client.rpc(
      'reject_pairing_request',
      params: {'request_id': requestId},
    );
  }

  Future<bool> shouldOpenRecorder() async {
    final id = user;
    if (id == null) return false;
    final preferences = FamilyDemoStore().preferences;
    try {
      final paired = (await links().timeout(const Duration(seconds: 5)))
          .any((link) => link['elder_id'] == id);
      if (user != id) return false;
      await preferences.setString('paired_elder_user', paired ? id : '');
      if (!paired) await FamilyDemoStore().write('applied', []);
      return paired;
    } catch (_) {
      return user == id &&
          await preferences.getString('paired_elder_user') == id;
    }
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

  Future<bool> pull() async {
    final elderId = user;
    if (elderId == null) return false;
    final matches = (await links())
        .where((e) => e['elder_id'] == elderId)
        .toList();
    if (user != elderId) throw StateError('Elder session changed during sync');
    if (matches.isEmpty) {
      await FamilyDemoStore().preferences.setString('paired_elder_user', '');
      await FamilyDemoStore().write('applied', []);
      return false;
    }
    await FamilyDemoStore().preferences.setString('paired_elder_user', elderId);
    final data = await elderSnapshot(matches.single['id'] as String);
    if (data == null) {
      await FamilyDemoStore().write('applied', []);
      return true;
    }
    final entries = (data['entries'] as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
    await FamilyDemoStore().write('applied', entries);
    await client.rpc(
      'ack_elder_settings',
      params: {'link_id': matches.single['id'], 'version': data['revision']},
    );
    return true;
  }

  Future<Map<String, dynamic>?> elderSnapshot(String linkId) => client
      .from('elder_snapshots')
      .select()
      .eq('link_id', linkId)
      .maybeSingle();

  Future<List<Map<String, dynamic>>> elderSnapshots() =>
      client.from('elder_snapshots').select();

  Future<int> publishElder(
    String linkId,
    List<Map<String, String>> entries,
    int revision,
  ) async => (await client.rpc(
    'publish_elder_settings',
    params: {
      'link_id': linkId,
      'items': entries,
      'expected_revision': revision,
    },
  ) as num).toInt();

  Future<void> renameElder(String linkId, String name) async {
    await client.rpc(
      'rename_paired_elder',
      params: {'link_id': linkId, 'display_name': name},
    );
  }

  Future<void> deleteCloudSettings() async {
    await client.rpc('delete_family_settings');
    await FamilyDemoStore().write('pending', []);
  }
}

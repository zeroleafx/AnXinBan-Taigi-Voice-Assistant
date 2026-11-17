import 'dart:convert';
import 'dart:async';

import 'family_cloud.dart';
import 'app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'family_demo_store.dart';

import 'home_page.dart';
import 'voice_command.dart';

class FamilyDemoPage extends StatefulWidget {
  const FamilyDemoPage({super.key, this.isFamily});
  final bool? isFamily;
  @override
  State<FamilyDemoPage> createState() => _FamilyDemoPageState();
}

class _FamilyDemoPageState extends State<FamilyDemoPage>
    with WidgetsBindingObserver {
  final store = FamilyDemoStore();
  final cloud = FamilyCloud();
  StreamSubscription<dynamic>? auth;
  int revision = 0;
  String? invitation;
  List<Map<String, dynamic>> devices = [];
  Future<void> refreshCloud() async {
    if (!FamilyCloud.available || cloud.user == null) return;
    devices = await cloud.links();
    if (unlocked) {
      final remote = await cloud.snapshot(cloud.user!);
      revision = (remote?['revision'] as num?)?.toInt() ?? 0;
    } else {
      await cloud.pull();
    }
    await load();
  }

  Future<void> pairDevice() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const PairCodeDialog(),
    );
    if (code == null) return;
    try {
      await cloud.pair(code);
    } catch (error) {
      if (mounted) {
        final detail = error.toString();
        setState(
          () => message = detail.contains('23505')
              ? '這個帳號已連結家人，請先解除原本的配對'
              : '配對未成功：請確認配對碼正確、未過期，且兩端使用不同帳號',
        );
      }
      return;
    }
    if (mounted) setState(() => message = '已連結家人，正在下載設定…');
    try {
      await refreshCloud();
      final link = devices
          .where((d) => d['elder_id'] == cloud.user)
          .firstOrNull;
      if (mounted) {
        setState(
          () => message = (link?['applied_revision'] as num? ?? 0) > 0
              ? '已連結家人，設定已同步完成。可以開始使用長輩模式。'
              : '已連結家人，等待家人發佈設定。',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = '已連結家人，但設定尚未下載完成。請按「重新整理雲端狀態」重試，不必重新配對。');
      }
    }
  }

  bool unlocked = false;
  bool busy = false;
  bool loading = true;
  List<Map<String, String>> pending = [];
  List<Map<String, String>> applied = [];
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    if (widget.isFamily == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(run(enterFamily));
      });
    }
    if (FamilyCloud.available) {
      var previousUser = cloud.user;
      auth = cloud.client.auth.onAuthStateChange.listen(
        (state) {
          if (!mounted) return;
          final user = cloud.user;
          final justSignedIn =
              state.event == AuthChangeEvent.signedIn &&
              user != null &&
              previousUser != user;
          previousUser = user;
          setState(() {
            if (justSignedIn) message = null;
            if (state.event == AuthChangeEvent.signedOut) message = '已登出';
          });
          if (justSignedIn) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.green,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '登入成功',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppColors.card,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: AppColors.freshGreen),
                  ),
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
          }
          unawaited(_refreshAfterLogin());
        },
        onError: (Object error) {
          if (mounted) setState(() => message = '登入未完成，請重新嘗試');
        },
      );
    }
  }

  Future<void> _refreshAfterLogin() async {
    try {
      await refreshCloud().timeout(const Duration(seconds: 10));
    } catch (_) {
      if (mounted) setState(() => message = '已登入，但雲端資料暫時無法讀取，請重新整理');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    auth?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS can become inactive for system overlays without leaving the app.
    // Lock only when it actually enters the background.
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        mounted) {
      setState(() => unlocked = false);
    }
  }

  Future<void> load() async {
    try {
      final p = await store.read('pending');
      final a = await store.read('applied');
      if (mounted) {
        setState(() {
          pending = p;
          applied = a;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          message = '讀取設定失敗，請重新開啟';
        });
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => message = '設定未儲存成功，請再試一次');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enterFamily() async {
    final exists = await store.hasPin();
    if (!mounted) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(create: !exists),
    );
    if (pin == null) return;
    if (!exists) await store.setPin(pin);
    final ok = await store.unlock(pin);
    if (ok && FamilyCloud.available && cloud.user != null) {
      final remote = await cloud.snapshot(cloud.user!);
      revision = (remote?['revision'] as num?)?.toInt() ?? 0;
      final items = remote?['entries'];
      await store.write(
        'pending',
        items == null
            ? []
            : (items as List)
                  .map((e) => Map<String, String>.from(e as Map))
                  .toList(),
      );
      await load();
    }
    if (mounted) {
      setState(() {
        unlocked = ok;
        message = ok ? null : 'PIN 不正確，或已暫時鎖定。連錯五次請等一分鐘。';
      });
    }
  }

  Future<void> edit({int? index, required String kind}) async {
    final original = index == null ? null : pending[index];
    final entry = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _EntryDialog(kind: kind, original: original),
    );
    if (entry == null || !mounted) return;
    // Preserve the submitted entry across a background lock. Reauthenticate
    // instead of silently discarding the form after its dialog has closed.
    if (!unlocked) {
      await enterFamily();
      if (!mounted) return;
      if (!unlocked) {
        setState(() => message = '尚未儲存：請解鎖家人設定後重新新增');
        return;
      }
    }
    if (kind == 'place') {
      Set<String> keys(Map<String, String> item) => {
        normalizeTranscript(item['label']!),
        ...item['aliases']!.split(RegExp('[,，]')).map(normalizeTranscript),
      }..remove('');
      final proposed = keys(entry);
      for (final (i, item) in pending.indexed) {
        if (i != index &&
            item['kind'] == 'place' &&
            keys(item).intersection(proposed).isNotEmpty) {
          if (mounted) setState(() => message = '這個地點名稱或別名已被使用，請換一個名稱');
          return;
        }
      }
    }
    final next = [...pending];
    if (index == null) {
      next.add(entry);
    } else {
      next[index] = entry;
    }
    await store.write('pending', next);
    await load();
    if (mounted) setState(() => message = '已儲存到家人端；按「模擬同步到長輩端」後才會套用');
  }

  @override
  Widget build(BuildContext context) {
    final changed = jsonEncode(pending) != jsonEncode(applied);
    return Scaffold(
      appBar: AppBar(
        title: Text(unlocked || widget.isFamily == true ? '家人設定' : '安心BAN'),
        actions: [
          if (unlocked)
            IconButton(
              tooltip: '鎖定家人設定',
              onPressed: () => setState(() => unlocked = false),
              icon: const Icon(Icons.lock),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  FamilyCloud.available ? '家人連線設定' : '本機模擬模式',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (FamilyCloud.available) ...[
                  Text(
                    cloud.user == null
                        ? '登入後可跨手機連結'
                        : '已登入：${cloud.client.auth.currentUser?.email ?? "Google 帳號"}',
                  ),
                  if (cloud.user == null)
                    OutlinedButton(
                      onPressed: busy ? null : () => run(cloud.login),
                      child: const Text('使用 Google 登入'),
                    ),
                  if (cloud.user != null) ...[
                    if (devices.any((d) => d['elder_id'] == cloud.user))
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.link, color: Colors.green),
                          title: Text('已連結家人'),
                          subtitle: Text('家人發佈的設定會同步到這支手機'),
                        ),
                      ),

                    TextButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await cloud.client.auth.signOut();
                              await store.write('pending', []);
                              await store.write('applied', []);
                              if (mounted) {
                                setState(() {
                                  unlocked = false;
                                  revision = 0;
                                  devices = [];
                                  invitation = null;
                                });
                              }
                              await load();
                            }),
                      child: const Text('登出並清除此機同步副本'),
                    ),

                    OutlinedButton(
                      onPressed: busy ? null : () => run(refreshCloud),
                      child: const Text('重新整理雲端狀態'),
                    ),
                    if (!unlocked && widget.isFamily != true)
                      OutlinedButton(
                        onPressed: busy ? null : () => run(pairDevice),
                        child: const Text('我是長輩，輸入家人配對碼'),
                      ),
                    if (unlocked) ...[
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                invitation = await cloud.invite();
                                if (mounted) setState(() {});
                              }),
                        child: const Text('產生一次性配對碼'),
                      ),
                      if (invitation != null)
                        SelectableText('配對碼（10 分鐘有效）：$invitation'),
                      for (final device in devices.where(
                        (d) => d['owner_id'] == cloud.user,
                      ))
                        ListTile(
                          title: const Text('已連結長輩'),
                          subtitle: Text('已套用版本 ${device["applied_revision"]}'),
                          trailing: IconButton(
                            tooltip: '解除配對',
                            icon: const Icon(Icons.link_off),
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                    await cloud.client
                                        .from('family_device_links')
                                        .delete()
                                        .eq('id', device['id']);
                                    await refreshCloud();
                                  }),
                          ),
                        ),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                final before = revision;
                                try {
                                  revision = await cloud.publish(
                                    pending,
                                    revision,
                                  );
                                } on FamilyPublishException catch (error) {
                                  if (mounted) {
                                    setState(() => message = error.message);
                                  }
                                  return;
                                }
                                if (mounted) {
                                  setState(
                                    () => message = revision == before
                                        ? '設定沒有變更，不需重新發佈（版本 $revision）'
                                        : '已送出版本 $revision，請長輩端同步後查看套用狀態',
                                  );
                                }
                              }),
                        child: const Text('發佈設定給長輩'),
                      ),
                    ],
                  ],
                ] else
                  const Text('雲端尚未連線，可先使用本機設定。'),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(message!),
                  ),
                const SizedBox(height: 24),
                if (!unlocked) ...[
                  if (widget.isFamily != true) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.mic),
                      label: const Text('我是長輩，開始使用'),
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              if (FamilyCloud.available && cloud.user != null) {
                                try {
                                  await cloud.pull().timeout(
                                    const Duration(seconds: 8),
                                  );
                                } catch (_) {
                                  /* Use last local snapshot offline. */
                                }
                              }
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const HomePage(),
                                ),
                              );
                            }),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.isFamily != false)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.family_restroom),
                      label: const Text('我是家人，管理設定'),
                      onPressed: busy ? null : () => run(enterFamily),
                    ),
                  const SizedBox(height: 24),
                  Text('長輩端已套用：${applied.length} 筆設定'),
                  for (final entry in applied)
                    ListTile(
                      title: Text(entry['label']!),
                      subtitle: Text('${entry['aliases']} → ${entry['value']}'),
                    ),
                ] else ...[
                  const Text('設定會先儲存到家人端草稿；按下模擬同步後，才更新長輩端的本機副本。'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() => edit(kind: 'contact')),
                    child: const Text('新增聯絡人與綽號'),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() => edit(kind: 'place')),
                    child: const Text('新增常用地址'),
                  ),
                  for (final (index, entry) in pending.indexed)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          entry['kind'] == 'contact'
                              ? Icons.person
                              : Icons.place,
                        ),
                        title: Text(entry['label']!),
                        subtitle: Text(
                          '${entry['aliases']}\n${entry['value']}',
                        ),
                        onTap: busy
                            ? null
                            : () => run(
                                () => edit(index: index, kind: entry['kind']!),
                              ),
                        trailing: IconButton(
                          tooltip: '移除設定',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  final next = [...pending]..removeAt(index);
                                  await store.write('pending', next);
                                  await load();
                                }),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(changed ? '有修改尚未套用到長輩端' : '本機兩端設定一致'),
                  FilledButton(
                    onPressed: busy || !changed
                        ? null
                        : () => run(() async {
                            await store.apply();
                            await load();
                            if (mounted) {
                              setState(() => message = '模擬同步完成；未傳送到其他手機');
                            }
                          }),
                    child: const Text('模擬同步到長輩端'),
                  ),
                ],
                if (busy) const Text('處理中…'),
              ],
            ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.create});
  final bool create;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final pin = TextEditingController();
  final repeat = TextEditingController();
  String? error;
  @override
  void dispose() {
    pin.dispose();
    repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.create ? '建立家人 PIN' : '輸入家人 PIN'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(labelText: '六位數 PIN'),
          ),
          if (widget.create)
            TextField(
              controller: repeat,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(labelText: '再次輸入 PIN'),
            ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (pin.text.length != 6 ||
              (widget.create && pin.text != repeat.text)) {
            setState(() => error = '請輸入六位數 PIN，並確認兩次相同');
            return;
          }
          Navigator.pop(context, pin.text);
        },
        child: const Text('確認'),
      ),
    ],
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.kind, this.original});
  final String kind;
  final Map<String, String>? original;
  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final label = TextEditingController(text: widget.original?['label']);
  late final aliases = TextEditingController(text: widget.original?['aliases']);
  late final value = TextEditingController(text: widget.original?['value']);
  String? error;
  @override
  void dispose() {
    label.dispose();
    aliases.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.kind == 'contact' ? '聯絡人綽號' : '常用地址'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: label,
            decoration: InputDecoration(
              labelText: widget.kind == 'contact' ? '姓名' : '地點名稱',
            ),
          ),
          TextField(
            controller: aliases,
            decoration: const InputDecoration(
              labelText: '綽號／別名，以逗號分隔',
              hintText: '女兒,阿美 或 家,厝',
            ),
          ),
          TextField(
            controller: value,
            keyboardType: widget.kind == 'contact'
                ? TextInputType.phone
                : TextInputType.streetAddress,
            decoration: InputDecoration(
              labelText: widget.kind == 'contact' ? '電話號碼' : '完整地址',
            ),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (label.text.trim().isEmpty ||
              aliases.text.trim().isEmpty ||
              value.text.trim().isEmpty ||
              (widget.kind == 'contact' &&
                  !RegExp(r'^\+?[0-9 ()-]{3,25}$')
                      .hasMatch(value.text.trim()))) {
            setState(() => error = '請填寫所有欄位，並確認電話號碼格式');
            return;
          }
          Navigator.pop(context, {
            'kind': widget.kind,
            'label': label.text.trim(),
            'aliases': aliases.text.trim(),
            'value': value.text.trim(),
          });
        },
        child: const Text('儲存'),
      ),
    ],
  );
}

/// Owns its controller until the dialog's exit animation has finished.
class PairCodeDialog extends StatefulWidget {
  const PairCodeDialog({super.key});
  @override
  State<PairCodeDialog> createState() => _PairCodeDialogState();
}

class _PairCodeDialogState extends State<PairCodeDialog> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('連結家人'),
    content: TextField(
      controller: input,
      decoration: const InputDecoration(labelText: '家人提供的配對碼'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('確認連結並接收家人設定'),
      ),
    ],
  );
}

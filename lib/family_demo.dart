import 'dart:convert';
import 'dart:async';

import 'family_cloud.dart';
import 'family_dashboard.dart';
import 'app_theme.dart';
import 'confirmation_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'family_demo_store.dart';

import 'home_page.dart';
import 'voice_command.dart';

void showFamilyFeedback(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.card,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.mutedTeal),
        ),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: text.length > 30 ? 6 : 3),
      ),
    );
}

class InvitationCodeDialog extends StatefulWidget {
  const InvitationCodeDialog({super.key, required this.code});
  final String code;
  @override
  State<InvitationCodeDialog> createState() => _InvitationCodeDialogState();
}

class _InvitationCodeDialogState extends State<InvitationCodeDialog> {
  bool copied = false;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: const Text('家人配對碼'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('請在長輩手機輸入此碼。限使用一次，10 分鐘內有效。'),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.bone,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.mutedTeal),
            ),
            child: SelectableText(
              widget.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.leaf,
                fontFamily: 'monospace',
                fontSize: 30,
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      FilledButton.icon(
        icon: Icon(copied ? Icons.check : Icons.copy_rounded),
        label: Text(copied ? '已複製' : '複製'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () async {
          try {
            await Clipboard.setData(ClipboardData(text: widget.code));
            if (mounted) {
              setState(() {
                copied = true;
                error = null;
              });
            }
          } catch (_) {
            if (mounted) setState(() => error = '無法複製，請長按配對碼複製');
          }
        },
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('關閉'),
      ),
    ],
  );
}

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
  List<Map<String, dynamic>> devices = [];
  Future<void> refreshCloud() async {
    if (!FamilyCloud.available || cloud.user == null) return;
    final latestDevices = await cloud.links();
    devices = latestDevices;
    if (cloud.hasFamilyAccount) {
      final remote = await cloud.snapshot(cloud.user!);
      await store.reconcileCloudDeletion(
        cloud.user!,
        remote?['settings_cleared_at'] as String?,
      );
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
              : detail.contains('Invalid or expired invitation')
              ? '配對碼已使用、已過期或不能用於此帳號。請家人產生新的配對碼，並確認兩端使用不同帳號。'
              : '配對未成功，請確認網路與配對碼後重試',
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

  Future<bool> confirmRemoval(String title, String description) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) =>
            ConfirmationDialog(title: title, description: description),
      ) ??
      false;

  Future<void> unlinkDevice(String id) async {
    if (!await confirmRemoval(
      '解除配對？',
      '解除後將停止同步；若這是最後一位長輩，家人的雲端設定也會刪除。雙方手機上的副本或草稿會在下次連線同步時清除，無法復原。',
    )) {
      return;
    }
    await cloud.client.from('family_device_links').delete().eq('id', id);
    await refreshCloud();
    if (mounted) {
      setState(
        () => message = '已解除配對。重新連結請由家人產生新的配對碼；舊碼無法重複使用。遠端副本將在長輩手機下次連線時清除。',
      );
    }
  }

  bool busy = false;
  bool loading = true;
  List<Map<String, String>> pending = [];
  List<Map<String, String>> applied = [];
  // Schedule feedback after the current state update, never inside build.
  set message(String? value) {
    if (value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showFamilyFeedback(context, value);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
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
            message = '登入成功';
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
    if (state == AppLifecycleState.resumed &&
        mounted &&
        FamilyCloud.available) {
      unawaited(_refreshAfterLogin());
    }
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
    if (FamilyCloud.available && !cloud.hasFamilyAccount) {
      message = '請先使用 Google 登入，再解鎖設定';
      return;
    }
    final exists = await store.hasPin();
    if (!mounted) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => FamilyPinDialog(create: !exists),
    );
    if (pin == null) return;
    if (!exists) await store.setPin(pin);
    final ok = await store.unlock(pin);
    if (ok && FamilyCloud.available && cloud.hasFamilyAccount) {
      final remote = await cloud.snapshot(cloud.user!);
      await store.reconcileCloudDeletion(
        cloud.user!,
        remote?['settings_cleared_at'] as String?,
      );
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
      builder: (_) => FamilyEntryDialog(kind: kind, original: original),
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
    if (widget.isFamily == true &&
        (!FamilyCloud.available || !cloud.hasFamilyAccount)) {
      return Scaffold(
        appBar: AppBar(title: const Text('家人登入')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                          color: AppColors.celadon,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.family_restroom_rounded,
                          color: AppColors.leaf,
                          size: 64,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      '一起照顧家人',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: busy || !FamilyCloud.available
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await cloud.login();
                              } on FamilyPublishException catch (error) {
                                if (mounted) {
                                  setState(() => message = error.message);
                                }
                              } catch (_) {
                                if (mounted) {
                                  setState(() => message = '登入未完成，請重新嘗試');
                                }
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: Text(busy ? '登入中…' : '使用 Google 登入'),
                    ),
                    if (!FamilyCloud.available) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '登入服務暫時無法使用，請確認網路後重新開啟 App。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (widget.isFamily == true &&
        FamilyCloud.available &&
        cloud.hasFamilyAccount) {
      return const FamilyDashboard();
    }
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
                    !cloud.hasFamilyAccount
                        ? '登入後可跨手機連結'
                        : '已登入：${cloud.client.auth.currentUser?.email ?? "Google 帳號"}',
                  ),
                  if (!cloud.hasFamilyAccount)
                    OutlinedButton(
                      onPressed: busy ? null : () => run(cloud.login),
                      child: const Text('使用 Google 登入'),
                    ),
                  if (cloud.hasFamilyAccount) ...[
                    if (devices.any((d) => d['elder_id'] == cloud.user))
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.link,
                            color: AppColors.leaf,
                          ),
                          title: const Text('已連結家人'),
                          subtitle: const Text('家人發佈的設定會同步到這支手機'),
                          trailing: IconButton(
                            tooltip: '解除配對',
                            icon: const Icon(Icons.link_off),
                            onPressed: busy
                                ? null
                                : () => run(
                                    () => unlinkDevice(
                                      devices.firstWhere(
                                            (d) => d['elder_id'] == cloud.user,
                                          )['id']
                                          as String,
                                    ),
                                  ),
                          ),
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
                                final code = await cloud.invite();
                                if (!mounted) return;
                                await showDialog<void>(
                                  context: this.context,
                                  builder: (_) =>
                                      InvitationCodeDialog(code: code),
                                );
                              }),
                        child: const Text('產生一次性配對碼'),
                      ),
                      for (final device in devices.where(
                        (d) => d['owner_id'] == cloud.user,
                      ))
                        ListTile(
                          title: const Text('已連結長輩'),
                          subtitle: Text(
                            revision > 0 &&
                                    (device['applied_revision'] as num? ?? 0) ==
                                        revision
                                ? '設定已同步'
                                : '等待同步',
                          ),
                          trailing: IconButton(
                            tooltip: '解除配對',
                            icon: const Icon(Icons.link_off),
                            onPressed: busy
                                ? null
                                : () => run(
                                    () => unlinkDevice(device['id'] as String),
                                  ),
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
                                        ? '設定沒有變更，不需重新發佈'
                                        : '設定已發佈，等待長輩端同步',
                                  );
                                }
                              }),
                        child: const Text('發佈設定給長輩'),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('刪除雲端設定'),
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                if (!await confirmRemoval(
                                  '刪除所有雲端設定？',
                                  '將刪除你發佈的聯絡人、綽號與地址，以及此機草稿。配對會保留，長輩手機下次連線會清除同步副本。此操作無法復原。',
                                )) {
                                  return;
                                }
                                await cloud.deleteCloudSettings();
                                await refreshCloud();
                                if (mounted) {
                                  setState(
                                    () =>
                                        message = '雲端設定與此機草稿已刪除；長輩端下次連線會清除同步副本',
                                  );
                                }
                              }),
                      ),
                    ],
                  ],
                ] else
                  const Text('雲端尚未連線，可先使用本機設定。'),
                const SizedBox(height: 24),
                if (!unlocked) ...[
                  if (widget.isFamily != true) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.mic),
                      label: const Text('我是長輩，開始使用'),
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              if (FamilyCloud.available &&
                                  cloud.hasFamilyAccount) {
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
                      label: Text(
                        widget.isFamily == true ? '解鎖設定' : '我是家人，管理設定',
                      ),
                      onPressed:
                          busy ||
                              (FamilyCloud.available && !cloud.hasFamilyAccount)
                          ? null
                          : () => run(enterFamily),
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

class FamilyPinDialog extends StatefulWidget {
  const FamilyPinDialog({super.key, required this.create});
  final bool create;
  @override
  State<FamilyPinDialog> createState() => FamilyPinDialogState();
}

class FamilyPinDialogState extends State<FamilyPinDialog> {
  final pin = TextEditingController();
  final repeat = TextEditingController();
  String? error;
  @override
  void dispose() {
    pin.dispose();
    repeat.dispose();
    super.dispose();
  }

  void confirm() {
    if (pin.text.length != 6 || (widget.create && repeat.text.length != 6)) {
      setState(() => error = '請輸入完整的六位數 PIN');
    } else if (widget.create && pin.text != repeat.text) {
      setState(() => error = '兩次 PIN 不相同，請再確認');
    } else {
      Navigator.pop(context, pin.text);
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool first = false,
  }) {
    final next = first && widget.create;
    return TextField(
      controller: controller,
      autofocus: first,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      textInputAction: next ? TextInputAction.next : TextInputAction.done,
      onSubmitted: next ? null : (_) => confirm(),
      onChanged: (_) {
        if (error != null) setState(() => error = null);
      },
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    backgroundColor: AppColors.bone,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    icon: const CircleAvatar(
      backgroundColor: AppColors.celadon,
      child: Icon(Icons.lock_outline, color: AppColors.ink),
    ),
    title: Text(widget.create ? '建立家人 PIN' : '輸入家人 PIN'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        field(pin, '六位數 PIN', first: true),
        if (widget.create) ...[
          const SizedBox(height: 16),
          field(repeat, '再次輸入 PIN'),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
    actions: [
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(onPressed: confirm, child: const Text('確認')),
          ),
        ],
      ),
    ],
  );
}

class FamilyEntryDialog extends StatefulWidget {
  const FamilyEntryDialog({super.key, required this.kind, this.original});
  final String kind;
  final Map<String, String>? original;
  @override
  State<FamilyEntryDialog> createState() => FamilyEntryDialogState();
}

class FamilyEntryDialogState extends State<FamilyEntryDialog> {
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
    title: Text(
      widget.kind == 'contact'
          ? '聯絡人綽號'
          : widget.kind == 'place'
          ? '常用地址'
          : '提醒事項',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: label,
            decoration: InputDecoration(
              labelText: widget.kind == 'contact'
                  ? '姓名'
                  : widget.kind == 'place'
                  ? '地點名稱'
                  : '提醒標題',
            ),
          ),
          if (widget.kind != 'reminder')
            TextField(
              controller: aliases,
              decoration: const InputDecoration(
                labelText: '綽號／別名，以逗號分隔',
                hintText: '女兒,阿美 或 家,厝',
              ),
            ),
          TextField(
            controller: value,
            maxLines: widget.kind == 'reminder' ? 4 : 1,
            keyboardType: widget.kind == 'contact'
                ? TextInputType.phone
                : widget.kind == 'reminder'
                ? TextInputType.multiline
                : TextInputType.streetAddress,
            decoration: InputDecoration(
              labelText: widget.kind == 'contact'
                  ? '電話號碼'
                  : widget.kind == 'place'
                  ? '完整地址'
                  : '提醒內容',
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
              (widget.kind != 'reminder' && aliases.text.trim().isEmpty) ||
              label.text.trim().length > 100 ||
              value.text.trim().length > 1000 ||
              value.text.trim().isEmpty ||
              (widget.kind == 'contact' &&
                  !RegExp(r'^\+?[0-9 ()-]{3,25}$')
                      .hasMatch(value.text.trim()))) {
            setState(
              () => error = widget.kind == 'reminder'
                  ? '請填寫提醒標題（100 字內）與內容（1000 字內）'
                  : '請填寫所有欄位（名稱 100 字、內容 1000 字內），並確認電話號碼格式',
            );
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
  void confirm() {
    final code = input.text.trim();
    if (RegExp(r'^[0-9]{6}$').hasMatch(code)) Navigator.pop(context, code);
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.card,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: BorderSide(color: AppColors.mutedTeal.withValues(alpha: 0.4)),
    ),
    contentPadding: const EdgeInsets.all(24),
    content: SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.celadon,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: AppColors.leaf,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '連結家人',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '輸入家人提供的 6 位數配對碼\n也可以直接貼上完整配對碼',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink, height: 1.5),
            ),
            const SizedBox(height: 24),
            Semantics(
              label: '6 位數配對碼',
              child: SizedBox(
                height: 64,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: TextField(
                        controller: input,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        autocorrect: false,
                        enableSuggestions: false,
                        showCursor: false,
                        style: const TextStyle(color: Colors.transparent),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => confirm(),
                        onTap: () => input.selection = TextSelection.collapsed(
                          offset: input.text.length,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Row(
                            children: List.generate(
                              6,
                              (i) => Expanded(
                                child: Container(
                                  key: ValueKey('pairing-digit-$i'),
                                  margin: EdgeInsets.only(
                                    right: i == 5 ? 0 : 6,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.bone,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: i == input.text.length
                                          ? AppColors.leaf
                                          : AppColors.mutedTeal,
                                      width: i == input.text.length ? 2 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    i < input.text.length ? input.text[i] : '',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const StadiumBorder(),
                      foregroundColor: AppColors.leaf,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const StadiumBorder(),
                      backgroundColor: AppColors.leaf,
                    ),
                    onPressed: input.text.length == 6 ? confirm : null,
                    child: const Text('確認'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'family_cloud.dart';
import 'family_demo.dart';
import 'family_demo_store.dart';
import 'elder_draft_store.dart';
import 'voice_command.dart';

class FamilyDashboard extends StatefulWidget {
  const FamilyDashboard({super.key, this.cloud});
  final FamilyCloud? cloud;
  @override
  State<FamilyDashboard> createState() => _FamilyDashboardState();
}

class _FamilyDashboardState extends State<FamilyDashboard>
    with WidgetsBindingObserver {
  late final cloud = widget.cloud ?? FamilyCloud();
  final drafts = ElderDraftStore();
  List<Map<String, dynamic>> links = [];
  Map<String, int> versions = {};
  bool loading = true;
  bool busy = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(refresh());
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  bool refreshing = false;
  Future<void> refresh() async {
    if (refreshing || !cloud.hasFamilyAccount) return;
    refreshing = true;
    final owner = cloud.user!;
    try {
      final result = await cloud.links().timeout(const Duration(seconds: 10));
      final owned = result.where((e) => e['owner_id'] == owner).toList();
      final snapshots = await cloud.elderSnapshots().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted || cloud.user != owner) return;
      await drafts.prune(owner, owned.map((e) => e['id'] as String).toSet());
      if (!mounted) return;
      setState(() {
        links = owned;
        versions = {
          for (final s in snapshots)
            s['link_id'] as String: (s['revision'] as num).toInt(),
        };
        error = null;
      });
    } catch (_) {
      if (mounted) setState(() => error = '暫時無法讀取長輩清單，請稍後重試');
    } finally {
      refreshing = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> invite() async {
    setState(() => busy = true);
    try {
      final code = await cloud.invite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => InvitationCodeDialog(code: code),
      );
      await refresh();
    } catch (_) {
      if (mounted) showFamilyFeedback(context, '無法產生配對碼，請稍後重試');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的家人'),
      actions: [
        IconButton(
          tooltip: '重新整理',
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '登出',
          icon: const Icon(Icons.logout),
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await drafts.prune(cloud.user!, {});
                    await FamilyDemoStore().write('pending', []);
                    await FamilyDemoStore().write('applied', []);
                    await cloud.client.auth.signOut();
                  } catch (_) {
                    if (mounted) {
                      showFamilyFeedback(this.context, '登出未完成，請再試一次');
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
      ],
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : invite,
      icon: const Icon(Icons.add),
      label: Text(busy ? '處理中…' : '新增長輩'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const Text('選擇一位長輩，管理他的聯絡人與地址。'),
                const SizedBox(height: 24),
                if (error != null) Text(error!),
                if (links.isEmpty && error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Text(
                      '還沒有連結的長輩\n點下方「新增長輩」開始配對',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final (index, link) in links.indexed)
                  Card(
                    color: AppColors.card,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(20),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.cream,
                        child: Icon(Icons.person, color: AppColors.green),
                      ),
                      title: Text(
                        elderName(link, index),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                        ),
                      ),
                      subtitle: Text(
                        (versions[link['id']] ?? 0) == 0
                            ? '尚未設定'
                            : link['applied_revision'] == versions[link['id']]
                            ? '設定已同步'
                            : '等待同步',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ElderSettingsPage(
                              cloud: cloud,
                              link: link,
                              name: elderName(link, index),
                            ),
                          ),
                        );
                        await refresh();
                      },
                    ),
                  ),
              ],
            ),
          ),
  );
}

String elderName(Map<String, dynamic> link, int index) {
  final name = (link['display_name'] as String? ?? '').trim();
  return name.isEmpty ? '長輩 ${index + 1}' : name;
}

class ElderSettingsPage extends StatefulWidget {
  const ElderSettingsPage({
    super.key,
    required this.link,
    required this.name,
    this.cloud,
  });
  final FamilyCloud? cloud;
  final Map<String, dynamic> link;
  final String name;
  @override
  State<ElderSettingsPage> createState() => _ElderSettingsPageState();
}

class _ElderSettingsPageState extends State<ElderSettingsPage>
    with WidgetsBindingObserver {
  late final cloud = widget.cloud ?? FamilyCloud();
  final drafts = ElderDraftStore();
  final pins = FamilyDemoStore();
  late final String owner = widget.link['owner_id'] as String;
  late final String linkId = widget.link['id'] as String;
  late String name = widget.name;
  List<Map<String, String>> entries = [];
  List<Map<String, String>> published = [];
  int revision = 0;
  bool loading = true, busy = false, unlocked = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setState(() => unlocked = false);
    }
  }

  Future<void> load({bool discardDraft = false}) async {
    try {
      final remote = await cloud
          .elderSnapshot(linkId)
          .timeout(const Duration(seconds: 10));
      if (remote == null) throw StateError('Unlinked');
      final draft = discardDraft ? null : await drafts.read(owner, linkId);
      if (!mounted) return;
      setState(() {
        published = (remote['entries'] as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
        entries = draft == null
            ? [...published]
            : (draft['entries'] as List)
                  .map((e) => Map<String, String>.from(e as Map))
                  .toList();
        revision = ((draft ?? remote)['revision'] as num).toInt();
        error = null;
      });
      if (discardDraft) await drafts.save(owner, linkId, entries, revision);
    } catch (_) {
      if (mounted) setState(() => error = '無法讀取設定，請確認網路及配對狀態');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> unlock() async {
    if (unlocked) return true;
    final exists = await pins.hasPin();
    if (!mounted) return false;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => FamilyPinDialog(create: !exists),
    );
    if (pin == null) return false;
    if (!exists) await pins.setPin(pin);
    final ok = await pins.unlock(pin);
    if (mounted) {
      setState(() => unlocked = ok);
      if (!ok) showFamilyFeedback(context, 'PIN 不正確或已暫時鎖定');
    }
    return ok && mounted;
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) showFamilyFeedback(context, '操作未完成，請重試；若雲端已更新，請先重新載入');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(List<Map<String, String>> next) async {
    await drafts.save(owner, linkId, next, revision);
    if (mounted) setState(() => entries = next);
  }

  Future<void> edit(String kind, [int? index]) async {
    if (!await unlock() || !mounted) return;
    final value = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => FamilyEntryDialog(
        kind: kind,
        original: index == null ? null : entries[index],
      ),
    );
    if (value == null || !await unlock()) return;
    if (kind == 'place') {
      Set<String> keys(Map<String, String> e) => {
        normalizeTranscript(e['label']!),
        ...e['aliases']!.split(RegExp('[,，]')).map(normalizeTranscript),
      }..remove('');
      for (final (i, existing) in entries.indexed) {
        if (i != index &&
            existing['kind'] == 'place' &&
            keys(existing).intersection(keys(value)).isNotEmpty) {
          if (mounted) showFamilyFeedback(context, '此長輩已有相同地點名稱或別名');
          return;
        }
      }
    }
    final next = [...entries];
    if (index == null) {
      next.add(value);
    } else {
      next[index] = value;
    }
    await save(next);
    if (mounted) showFamilyFeedback(context, '已儲存草稿，發佈後會同步給$name');
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(name),
      actions: [
        if (unlocked)
          IconButton(
            tooltip: '鎖定設定',
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
              if (error != null) ...[
                Text(error!),
                TextButton(onPressed: () => load(), child: const Text('重試')),
              ] else ...[
                Text('這裡的修改只會套用到$name。'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => run(() => edit('contact')),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('新增聯絡人與綽號'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => run(() => edit('place')),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('新增常用地址'),
                ),
                for (final (index, entry) in entries.indexed)
                  Card(
                    color: AppColors.card,
                    child: ListTile(
                      leading: Icon(
                        entry['kind'] == 'contact' ? Icons.person : Icons.place,
                      ),
                      title: Text(entry['label']!),
                      subtitle: Text('${entry['aliases']}\n${entry['value']}'),
                      onTap: busy
                          ? null
                          : () => run(() => edit(entry['kind']!, index)),
                      trailing: IconButton(
                        tooltip: '移除設定',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                if (await unlock()) {
                                  await save([...entries]..removeAt(index));
                                }
                              }),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy || sameFamilySettings(published, entries)
                      ? null
                      : () => run(() async {
                          if (!await unlock()) return;
                          final nextRevision = await cloud.publishElder(
                            linkId,
                            entries,
                            revision,
                          );
                          revision = nextRevision;
                          await drafts.save(owner, linkId, entries, revision);
                          if (mounted) {
                            setState(() => published = [...entries]);
                            showFamilyFeedback(this.context, '設定已發佈，等待$name同步');
                          }
                        }),
                  child: const Text('發佈設定'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (await confirm('重新載入設定？', '未發佈的草稿將被雲端設定取代。')) {
                            await load(discardDraft: true);
                          }
                        }),
                  child: const Text('重新載入雲端設定'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (!await unlock() || !mounted) return;
                          final result = await showDialog<String>(
                            context: this.context,
                            builder: (_) => _NameDialog(name: name),
                          );
                          if (result == null || !await unlock()) return;
                          await cloud.renameElder(linkId, result);
                          if (mounted) setState(() => name = result);
                        }),
                  child: const Text('更改長輩名稱'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (!await unlock() || !mounted) return;
                          if (!await confirm(
                            '解除與$name的配對？',
                            '此長輩的雲端設定及本機草稿會刪除，其他長輩不受影響。長輩手機下次連線會清除同步副本。',
                          )) {
                            return;
                          }
                          if (!await unlock()) return;
                          await cloud.client
                              .from('family_device_links')
                              .delete()
                              .eq('id', linkId);
                          final active = (await cloud.links())
                              .where((e) => e['owner_id'] == owner)
                              .map((e) => e['id'] as String)
                              .toSet();
                          await drafts.prune(owner, active);
                          if (mounted) Navigator.pop(this.context);
                        }),
                  child: const Text('解除配對'),
                ),
              ],
              if (busy) const Center(child: Text('處理中…')),
            ],
          ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.name});
  final String name;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final input = TextEditingController(text: widget.name);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('長輩名稱'),
    content: TextField(
      controller: input,
      maxLength: 40,
      decoration: const InputDecoration(hintText: '例如：阿公、阿嬤'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (input.text.trim().isNotEmpty) {
            Navigator.pop(context, input.text.trim());
          }
        },
        child: const Text('確認'),
      ),
    ],
  );
}

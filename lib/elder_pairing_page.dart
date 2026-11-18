import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_cloud.dart';
import 'family_demo.dart';
import 'home_page.dart';

class ElderPairingPage extends StatefulWidget {
  const ElderPairingPage({super.key});
  @override
  State<ElderPairingPage> createState() => _ElderPairingPageState();
}

class _ElderPairingPageState extends State<ElderPairingPage> {
  final cloud = FamilyCloud();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (FamilyCloud.available) {
      WidgetsBinding.instance.addPostFrameCallback((_) => checkPairing());
    }
  }

  Future<void> openRecorder() async {
    try {
      await cloud.pull().timeout(const Duration(seconds: 10));
    } catch (_) {
      // The recorder can use the last local copy until synchronization resumes.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  Future<void> checkPairing() async {
    if (!mounted || cloud.user == null) return;
    setState(() => busy = true);
    try {
      final links = await cloud.links().timeout(const Duration(seconds: 10));
      if (links.any((link) => link['elder_id'] == cloud.user)) {
        await openRecorder();
      }
    } catch (_) {
      if (mounted) showFamilyFeedback(context, '暫時無法確認配對，請確認網路後重試');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pair() async {
    if (!FamilyCloud.available) {
      showFamilyFeedback(context, '配對服務尚未連線，請稍後重試');
      return;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const PairCodeDialog(),
    );
    if (code == null || !mounted) return;
    setState(() => busy = true);
    try {
      await cloud.ensureElderIdentity();
      final links = await cloud.links();
      if (!links.any((link) => link['elder_id'] == cloud.user)) {
        await cloud.pair(code);
      }
      if (mounted) showFamilyFeedback(context, '配對成功');
      await openRecorder();
    } on AuthException catch (_) {
      if (mounted) showFamilyFeedback(context, '無法建立裝置連線，請確認網路及匿名登入服務已啟用');
    } catch (_) {
      if (mounted) showFamilyFeedback(context, '配對未完成，請確認網路，並請家人提供新的配對碼');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('連結家人')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.family_restroom, size: 80),
              const SizedBox(height: 24),
              const Text(
                '讓家人幫你設定',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('輸入家人提供的配對碼，就能開始使用。', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: busy ? null : pair,
                child: Text(busy ? '連線中…' : '與家人配對'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

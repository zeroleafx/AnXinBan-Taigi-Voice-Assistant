/// Pairing needs the family's approval. The elder's phone shows a two-digit
/// number; the family's phone shows the same number and allows the link only
/// when the two match. A guessed code therefore gains nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_feedback.dart';
import 'app_theme.dart';
import 'family_cloud.dart';

/// Elder side: sends [code], shows the number for the family and waits for
/// their decision. True once the family allowed the link. Throws
/// [FamilyPublishException] when the code is not taken.
Future<bool> pairWithFamily(
  BuildContext context,
  FamilyCloud cloud,
  String code,
) async {
  final request = await cloud.requestPairing(code);
  if (!context.mounted) return false;
  final status = await showDialog<PairingStatus>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ElderPairingWaitDialog(cloud: cloud, request: request),
  );
  if (!context.mounted) return false;
  switch (status) {
    case PairingStatus.approved:
      await cloud.rememberPairing();
      return true;
    case PairingStatus.rejected:
      showAppFeedback(context, '家人沒有允許這次連結，請家人重新產生配對碼');
    case PairingStatus.expired:
      showAppFeedback(context, '等候太久，請家人重新產生配對碼');
    case PairingStatus.pending:
    case null:
      // Cancelled; the request lapses on its own.
      break;
  }
  return false;
}

/// Family side: shows the elder's request and asks whether the numbers match.
Future<void> reviewPairingRequest(
  BuildContext context,
  FamilyCloud cloud,
  PairingRequest request,
) async {
  final allow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PairingApprovalDialog(request: request),
  );
  if (allow == null || !context.mounted) return;
  try {
    if (allow) {
      await cloud.approvePairing(request.id);
      if (context.mounted) showAppFeedback(context, '已連結長輩');
    } else {
      await cloud.rejectPairing(request.id);
      if (context.mounted) showAppFeedback(context, '已拒絕，這組配對碼已失效');
    }
  } on FamilyPublishException catch (error) {
    if (context.mounted) showAppFeedback(context, error.message);
  } catch (_) {
    if (context.mounted) showAppFeedback(context, '暫時無法處理連結請求，請稍後重試');
  }
}

/// Shows the number and checks every few seconds whether the family decided.
/// Pops with the decision, or with null when the elder cancels.
class ElderPairingWaitDialog extends StatefulWidget {
  const ElderPairingWaitDialog({
    super.key,
    required this.cloud,
    required this.request,
    this.interval = const Duration(seconds: 2),
  });
  final FamilyCloud cloud;
  final PairingRequest request;
  final Duration interval;
  @override
  State<ElderPairingWaitDialog> createState() => _ElderPairingWaitDialogState();
}

class _ElderPairingWaitDialogState extends State<ElderPairingWaitDialog> {
  Timer? poll;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(widget.interval, (_) => unawaited(check()));
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    try {
      final status = await widget.cloud.pairingStatus(widget.request.id);
      if (status != PairingStatus.pending && mounted) {
        poll?.cancel();
        Navigator.pop(context, status);
      }
    } catch (_) {
      // Try again on the next tick; the network may be back by then.
    } finally {
      checking = false;
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PairingDialog(
    icon: Icons.verified_user_outlined,
    title: '請家人確認',
    description: '請把這個號碼告訴家人。\n家人手機上會出現同樣的號碼。',
    code: widget.request.confirmCode,
    footer: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.leaf,
          ),
        ),
        SizedBox(width: 12),
        Text('等待家人允許…', style: TextStyle(fontSize: 18, color: AppColors.ink)),
      ],
    ),
    actions: [
      _DialogButton(label: '取消', onPressed: () => Navigator.pop(context)),
    ],
  );
}

/// Asks the family whether the number matches the one on the elder's phone.
/// Pops true to allow, false to refuse.
class PairingApprovalDialog extends StatelessWidget {
  const PairingApprovalDialog({super.key, required this.request});
  final PairingRequest request;

  @override
  Widget build(BuildContext context) => _PairingDialog(
    icon: Icons.phonelink_lock_rounded,
    title: '長輩手機要連結',
    description: '請看長輩手機上的號碼。\n和下面一樣才允許；不一樣，或不是你的長輩，請拒絕。',
    code: request.confirmCode,
    actions: [
      _DialogButton(
        label: '不一樣，拒絕',
        onPressed: () => Navigator.pop(context, false),
      ),
      _DialogButton(
        label: '一樣，允許',
        filled: true,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
}

/// The layout of the app's confirmation dialog, with a large number.
class _PairingDialog extends StatelessWidget {
  const _PairingDialog({
    required this.icon,
    required this.title,
    required this.description,
    required this.code,
    required this.actions,
    this.footer,
  });
  final IconData icon;
  final String title;
  final String description;
  final String code;
  final List<Widget> actions;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.card,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.celadon,
                ),
                child: Icon(icon, size: 44, color: AppColors.leaf),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: AppColors.ink.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.bone,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.mutedTeal),
              ),
              child: Semantics(
                label: '確認號碼 ${code.split('').join(' ')}',
                excludeSemantics: true,
                child: Text(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.leaf,
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 12,
                  ),
                ),
              ),
            ),
            if (footer != null) ...[const SizedBox(height: 24), footer!],
            const SizedBox(height: 32),
            Row(
              children: [
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: action),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    return filled
        ? FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54),
              backgroundColor: AppColors.leaf,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onPressed,
            child: Text(label, style: text),
          )
        : TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 54),
              foregroundColor: AppColors.leaf,
            ),
            onPressed: onPressed,
            child: Text(label, style: text),
          );
  }
}

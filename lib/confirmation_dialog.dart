import 'package:flutter/material.dart';

import 'app_theme.dart';

class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.notifications_active_outlined,
  });
  final String title;
  final String description;
  final IconData icon;

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
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      foregroundColor: AppColors.leaf,
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      backgroundColor: AppColors.leaf,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      '確認',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

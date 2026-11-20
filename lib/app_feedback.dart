import 'package:flutter/material.dart';

import 'app_theme.dart';

void showAppFeedback(BuildContext context, String text) {
  // Reserve space through Scaffold so the add button follows the animation.
  // Only the inset card paints a surface.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: _FeedbackCard(text),
        ),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.fixed,
        duration: Duration(seconds: text.length > 30 ? 6 : 3),
      ),
    );
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppColors.mutedTeal),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class TopFeedback extends StatelessWidget {
  const TopFeedback({super.key, required this.message, required this.onClose});
  final String? message;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Positioned(
    top: 6,
    left: 24,
    right: 24,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: message == null
          ? const SizedBox.shrink()
          : Dismissible(
              key: ValueKey(message),
              direction: DismissDirection.up,
              resizeDuration: null,
              confirmDismiss: (_) async {
                onClose();
                return false;
              },
              child: Semantics(
                liveRegion: true,
                onDismiss: onClose,
                child: SizedBox(
                  width: double.infinity,
                  child: _FeedbackCard(message!),
                ),
              ),
            ),
    ),
  );
}

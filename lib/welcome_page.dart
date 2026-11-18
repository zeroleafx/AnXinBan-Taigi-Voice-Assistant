import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'family_demo.dart';
import 'elder_pairing_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  void _openRole(BuildContext context, {required bool isFamily}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => isFamily
            ? const FamilyDemoPage(isFamily: true)
            : const ElderPairingPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 40,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: AppColors.cream,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.freshGreen.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.spa_rounded,
                          size: 120,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '安心BAN',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 64),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(64),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => _openRole(context, isFamily: true),
                          child: const Text(
                            '家人',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.green,
                            minimumSize: const Size.fromHeight(64),
                            side: const BorderSide(
                              color: AppColors.green,
                              width: 1.5,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => _openRole(context, isFamily: false),
                          child: const Text(
                            '長輩',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

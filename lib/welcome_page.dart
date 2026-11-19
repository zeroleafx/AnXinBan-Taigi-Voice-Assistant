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
                          color: AppColors.celadon,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.mutedTeal.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.spa_rounded,
                          size: 120,
                          color: AppColors.leaf,
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
                            minimumSize: const Size.fromHeight(76),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => _openRole(context, isFamily: false),
                          child: const Text(
                            '長輩',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 220,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.ocean,
                            minimumSize: const Size.fromHeight(50),
                            side: const BorderSide(
                              color: AppColors.ocean,
                              width: 1.5,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => _openRole(context, isFamily: true),
                          child: const Text(
                            '家人',
                            style: TextStyle(
                              fontSize: 19,
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

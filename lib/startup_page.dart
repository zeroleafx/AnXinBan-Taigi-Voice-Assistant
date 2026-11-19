import 'package:flutter/material.dart';

import 'family_cloud.dart';
import 'app_theme.dart';
import 'home_page.dart';
import 'welcome_page.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool started = false;
  late final Future<bool> paired;

  @override
  void initState() {
    super.initState();
    paired = FamilyCloud.available
        ? FamilyCloud().shouldOpenRecorder()
        : Future.value(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.value = 1;
    } else if (!started) {
      animation.forward();
    }
    started = true;
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: paired,
    builder: (context, snapshot) => AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        if (animation.isCompleted &&
            snapshot.connectionState == ConnectionState.done) {
          return snapshot.data == true ? const HomePage() : const WelcomePage();
        }
        final slide = const Interval(
          .18,
          .48,
          curve: Curves.easeInOutCubic,
        ).transform(animation.value);
        final letters =
            (const Interval(.49, .85).transform(animation.value) * 5).floor();
        return Scaffold(
          backgroundColor: AppColors.bone,
          body: Center(
            child: Semantics(
              label: '安心BAN',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/brand/splash.png',
                        width: 96,
                        height: 96,
                      ),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: slide,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Stack(
                              children: [
                                const Opacity(
                                  opacity: 0,
                                  child: Text('安心BAN', style: _wordmark),
                                ),
                                Text(
                                  '安心BAN'.substring(0, letters),
                                  style: _wordmark,
                                ),
                              ],
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
        );
      },
    ),
  );
  static const _wordmark = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );
}

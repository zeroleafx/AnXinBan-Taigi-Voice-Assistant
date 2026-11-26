import 'package:flutter/material.dart';

import 'family_cloud.dart';
import 'family_demo_store.dart';
import 'family_demo.dart';
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
    duration: const Duration(milliseconds: 2300),
  );
  bool started = false;
  late final Future<Widget> landingPage;

  @override
  void initState() {
    super.initState();
    landingPage = resolveLandingPage();
  }

  Future<Widget> resolveLandingPage() async {
    if (await FamilyDemoStore().prefersStandaloneRecorder) {
      return const HomePage(useFamilySettings: false);
    }
    if (FamilyCloud.available) {
      final cloud = FamilyCloud();
      if (cloud.hasFamilyAccount) {
        final owner = cloud.user;
        try {
          final links = await cloud.links().timeout(const Duration(seconds: 5));
          if (owner != null &&
              cloud.user == owner &&
              links.any((link) => link['owner_id'] == owner)) {
            return const FamilyDemoPage(isFamily: true);
          }
        } catch (_) {
          // The role picker remains available when pairing cannot be verified.
        }
      } else if (await cloud.shouldOpenRecorder()) {
        return const HomePage();
      }
    }
    return const WelcomePage();
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
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: landingPage,
    builder: (context, snapshot) => AnimatedBuilder(
      animation: animation,
      builder: (context, _) =>
          animation.isCompleted &&
              snapshot.connectionState == ConnectionState.done
          ? ColoredBox(
              color: AppColors.bone,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 360),
                curve: Curves.easeInOut,
                child: snapshot.data ?? const WelcomePage(),
                builder: (context, opacity, child) => IgnorePointer(
                  ignoring: opacity < 1,
                  child: Opacity(opacity: opacity, child: child),
                ),
              ),
            )
          : _splash(),
    ),
  );

  Widget _splash() {
    final slide = const Interval(
      .14,
      .38,
      curve: Curves.easeInOutCubic,
    ).transform(animation.value);
    final letters = (const Interval(.39, .67).transform(animation.value) * 5)
        .floor();
    return Scaffold(
      key: const ValueKey('splash'),
      backgroundColor: AppColors.bone,
      body: Center(
        child: Semantics(
          label: '安心BAN',
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Opacity(
                opacity:
                    1 -
                    const Interval(
                      .76,
                      1,
                      curve: Curves.easeInOut,
                    ).transform(animation.value),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Painted, not decoded from an image, so the mark is already
                    // there on the first frame when the launch screen goes away.
                    const CustomPaint(
                      size: Size.square(96),
                      painter: _LeafMark(),
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
      ),
    );
  }

  static const _wordmark = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );
}

/// The leaf mark of the native launch screens (web/splash-leaf.svg, the
/// Android splash_system_icon and the iOS LaunchImage), drawn at the same
/// size and place so the splash carries on exactly where they leave off.
class _LeafMark extends CustomPainter {
  const _LeafMark();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 128, size.height / 128);
    canvas.drawCircle(
      const Offset(64, 64),
      60,
      Paint()..color = AppColors.celadon,
    );
    canvas.drawPath(
      Path()
        ..moveTo(64, 62)
        ..quadraticBezierTo(44, 45, 64, 25)
        ..quadraticBezierTo(84, 45, 64, 62)
        ..close()
        ..moveTo(64, 94)
        ..quadraticBezierTo(33, 91, 27, 51)
        ..quadraticBezierTo(49, 52, 64, 72)
        ..quadraticBezierTo(79, 52, 101, 51)
        ..quadraticBezierTo(95, 91, 64, 94)
        ..close(),
      Paint()..color = AppColors.leaf,
    );
  }

  @override
  bool shouldRepaint(_LeafMark oldDelegate) => false;
}

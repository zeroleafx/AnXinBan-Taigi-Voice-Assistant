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
      builder: (context, _) => ColoredBox(
        // Shows between the splash and the next page while they fade.
        color: AppColors.bone,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: _fadeThrough,
          child:
              animation.isCompleted &&
                  snapshot.connectionState == ConnectionState.done
              ? (snapshot.data == true ? const HomePage() : const WelcomePage())
              : _splash(),
        ),
      ),
    ),
  );

  Widget _splash() {
    final slide = const Interval(
      .18,
      .48,
      curve: Curves.easeInOutCubic,
    ).transform(animation.value);
    final letters = (const Interval(.49, .85).transform(animation.value) * 5)
        .floor();
    return Scaffold(
      key: _splashKey,
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
    );
  }

  // Fade through: the splash fades out in the first 30% of the switch, then
  // the next page fades in, so the two logos and names never overlap.
  static Widget _fadeThrough(Widget child, Animation<double> fade) =>
      FadeTransition(
        opacity: fade.drive(
          CurveTween(
            curve: child.key == _splashKey
                ? const Interval(.7, 1)
                : const Interval(.3, 1),
          ),
        ),
        child: child,
      );

  static const _splashKey = ValueKey('splash');
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

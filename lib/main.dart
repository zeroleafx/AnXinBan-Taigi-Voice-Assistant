import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme.dart';
import 'family_cloud.dart';
import 'startup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The home screen is designed to fit one portrait screen without scrolling.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  try {
    await FamilyCloud.initialize();
  } catch (_) {
    /* Offline local mode remains available. */
  }
  runApp(const AnXinBanApp());
}

const _taiwan = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
  countryCode: 'TW',
);

class AnXinBanApp extends StatelessWidget {
  const AnXinBanApp({super.key, this.home = const StartupPage()});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '安心BAN',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: _taiwan,
    supportedLocales: const [_taiwan],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    // Large system text is honoured up to a size that still fits one screen.
    builder: (context, child) =>
        MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2, child: child!),
    home: home,
  );
}

import 'package:flutter/material.dart';

import 'family_cloud.dart';
import 'home_page.dart';
import 'welcome_page.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  late final Future<bool> paired;

  @override
  void initState() {
    super.initState();
    paired = FamilyCloud.available
        ? FamilyCloud().shouldOpenRecorder()
        : Future.value(false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: paired,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snapshot.data == true ? const HomePage() : const WelcomePage();
    },
  );
}

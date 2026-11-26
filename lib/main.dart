import 'dart:io';

import 'package:flutter/material.dart';

import 'services/app_store.dart';
import 'screens/welcome.dart';
import 'screens/onboarding.dart';
import 'screens/dashboard.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final path = await native.invokeMethod<String>('storagePath');
    if (path == null) {
      throw const FileSystemException('App storage unavailable');
    }
    final store = AppStore(Directory(path));
    await store.load();
    runApp(GranniesApp(store: store));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Your saved information could not be opened. Please restart the app. Your pairing code has not been replaced.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GranniesApp extends StatelessWidget {
  const GranniesApp({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Grannies Healthbar',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Widget page;
        if (store.role.isEmpty) {
          page = WelcomePage(store: store);
        } else if (store.plan != null) {
          page = DashboardPage(store: store);
        } else if (store.role == 'grandma') {
          page = GrandmaPairPage(store: store);
        } else {
          page = HelperSetupPage(store: store);
        }
        return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(.05, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey('${store.role}-${store.plan != null}'),
            child: page,
          ),
        );
      },
    ),
  );
}

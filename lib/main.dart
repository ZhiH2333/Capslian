import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'core/network/storage_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/direct/providers/chat_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runZonedGuarded(() {
    runApp(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
        child: const CapslianApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    if (error is WebSocketChannelException) {
      return;
    }
    if (error.toString().contains('Connection refused') &&
        error.toString().contains('61199')) {
      return;
    }
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'runZonedGuarded',
    ));
  });
}

class CapslianApp extends ConsumerWidget {
  const CapslianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(wsLifecycleProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Capslian',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: createAppRouter(),
    );
  }
}

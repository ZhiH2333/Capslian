import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'core/network/storage_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/theme/theme_settings_provider.dart';
import 'features/direct/providers/chat_providers.dart';
import 'features/notifications/providers/notifications_providers.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.getInstance().then((SharedPreferences prefs) {
      runApp(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
          child: const MolianApp(),
        ),
      );
    });
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

class MolianApp extends ConsumerWidget {
  const MolianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(wsLifecycleProvider);
    ref.watch(pushSubscribeOnAuthProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    return MaterialApp.router(
      title: 'Molian',
      theme: AppTheme.light(themeSettings),
      darkTheme: AppTheme.dark(themeSettings),
      themeMode: themeMode,
      routerConfig: createAppRouter(),
    );
  }
}

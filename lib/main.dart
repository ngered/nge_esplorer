import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/memory_repository.dart';
import 'data/settings.dart';
import 'lng.dart';
import 'providers/app_provider.dart';
import 'screens/map_screen.dart';
import 'theme.dart';
import 'widgets/device_frame.dart';
import 'widgets/photo.dart';
import 'widgets/back_to_map.dart';

void main() {
  // Web (provisoire) : dépôt en mémoire, données de test uniquement. Android : SQLite chiffrée (à venir).
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(MemoryRepository(), settings: Settings())
        ..urlPhotoServer = photoServerFromUrl(Uri.base)
        ..loadSettings(),
      child: const NgeEsPlorerApp(),
    ),
  );
}

class NgeEsPlorerApp extends StatelessWidget {
  const NgeEsPlorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final language = context.select((AppProvider app) => app.language);
    return MaterialApp(
      title: 'NgeEsPlorer',
      debugShowCheckedModeBanner: false,
      // thème clair imposé, même si le terminal est en mode sombre (lisibilité en extérieur)
      theme: ngeTheme(),
      themeMode: ThemeMode.light,
      // langue de l'interface (Paramètres) : textes de l'application (lng.dart) et des composants Material
      locale: Locale(language),
      supportedLocales: [for (final code in Lng.languages.keys) Locale(code)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [screenStack],
      // web : `?terminal=smartphone` (ou grand, tablette, paysage, 390x844) affiche l'application dans un cadre de terminal
      builder: (context, child) {
        final size = Terminal.fromUrl(Uri.base);
        return size == null ? child! : DeviceFrame(size: size, child: child!);
      },
      home: const MapScreen(),
    );
  }
}

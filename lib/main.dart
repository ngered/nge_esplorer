import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/memory_repository.dart';
import 'data/reglages.dart';
import 'providers/app_provider.dart';
import 'screens/carte_screen.dart';
import 'widgets/retour_carte.dart';

void main() {
  // Web (provisoire) : dépôt en mémoire, données de test uniquement. Android : SQLite chiffrée (à venir).
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(MemoryRepository(), reglages: Reglages())..chargerReglages(),
      child: const NgeEsPlorerApp(),
    ),
  );
}

class NgeEsPlorerApp extends StatelessWidget {
  const NgeEsPlorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NgeEsPlorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF00558C), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF00558C), brightness: Brightness.dark, useMaterial3: true),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [pileEcrans],
      home: const CarteScreen(),
    );
  }
}

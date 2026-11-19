import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scanner_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The overlay math assumes a portrait UI.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BillScannerApp());
}

class BillScannerApp extends StatelessWidget {
  const BillScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bill Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const ScannerPage(),
    );
  }
}

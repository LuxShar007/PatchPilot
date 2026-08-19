import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/scanner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system overlay for clean light minimalist theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF7F7F5),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const PatchPilotApp());
}

class PatchPilotApp extends StatelessWidget {
  const PatchPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PatchPilot',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7F7F5),
        primaryColor: const Color(0xFF111111),
        cardColor: const Color(0xFFFCFCFB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF111111),
          secondary: Color(0xFF6B6B6B),
          surface: Color(0xFFFCFCFB),
          error: Color(0xFFEF4444),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF111111),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F7F5),
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Color(0xFF111111)),
          titleTextStyle: TextStyle(
            color: Color(0xFF111111),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF111111),
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          ),
        ),
      ),
      home: const ScannerScreen(),
    );
  }
}

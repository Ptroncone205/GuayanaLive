import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_provider.dart';
import 'main_layout.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

// Global notifier for guest mode
final ValueNotifier<bool> guestModeNotifier = ValueNotifier(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://oulpjjpvkfxcskrqibet.supabase.co',
    anonKey: 'sb_publishable_FXvexleGAbzKf-iwOU8fyw_xfA4DFhk',
  );

  final prefs = await SharedPreferences.getInstance();
  final String languageCode = prefs.getString('language_code') ?? 'es';

  runApp(LocaleProviderScope(notifier: LocaleProvider(Locale(languageCode)), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color appleGreen = Color(0xFF9ACF7C);
    final localeProvider = LocaleProviderScope.of(context);

    return MaterialApp(
      title: 'Guayana Live',
      debugShowCheckedModeBanner: false,
      locale: localeProvider.locale,
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: appleGreen),
        useMaterial3: true,
        primaryColor: appleGreen,
        appBarTheme: const AppBarTheme(
          backgroundColor: appleGreen,
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  bool _profileComplete = false;
  bool _checkingProfile = true;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;
    _checkProfileStatus();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _session = data.session;
        });
        if (_session != null) {
          _checkProfileStatus();
        }
      }
    });
  }

  Future<void> _checkProfileStatus() async {
    setState(() => _checkingProfile = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _checkingProfile = false);
        return;
      }

      final data = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          final fullName = data?['full_name'] as String?;
          _profileComplete =
              fullName != null &&
              fullName.trim().isNotEmpty &&
              fullName.trim().toLowerCase() != 'usuario';
          _checkingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: guestModeNotifier,
      builder: (context, isGuest, child) {
        if (_session == null && !isGuest) {
          return const LoginScreen();
        }

        if (_session != null && _checkingProfile) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_session != null && !_profileComplete) {
          return ProfileScreen(onSetupComplete: _checkProfileStatus);
        }

        return const MainLayout();
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'pinterest_screen.dart';
import 'profile_screen.dart';

// Global notifier for guest mode
final ValueNotifier<bool> guestModeNotifier = ValueNotifier(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');

  await Supabase.initialize(
    url: 'https://oulpjjpvkfxcskrqibet.supabase.co',
    anonKey: 'sb_publishable_FXvexleGAbzKf-iwOU8fyw_xfA4DFhk',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guayana Live',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green.shade700),
        useMaterial3: true,
        primaryColor: Colors.green.shade700,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        iconTheme: IconThemeData(color: Colors.green.shade700),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.green.shade700,
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
          _profileComplete = fullName != null && 
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
    // Listen to guest mode toggles securely
    return ValueListenableBuilder<bool>(
      valueListenable: guestModeNotifier,
      builder: (context, isGuest, child) {
        if (_session == null && !isGuest) {
          return const LoginScreen();
        }

        if (_session != null && _checkingProfile) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.green)),
          );
        }

        if (_session != null && !_profileComplete) {
          return ProfileScreen(
            onSetupComplete: _checkProfileStatus,
          );
        }

        // If Guest OR Setup is complete, grant access to Main Feed
        return const PinterestScreen();
      },
    );
  }
}
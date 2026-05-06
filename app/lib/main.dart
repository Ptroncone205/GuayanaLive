import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'login_screen.dart';
import 'pinterest_screen.dart';
import 'profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Gemini.init(apiKey: 'AIzaSyADB8TsEgLfzN1MR3sWcXdWhGatD42cobo');

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
      title: 'Edu-Pinterest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
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
    if (_session != null) {
      _checkProfileStatus();
    } else {
      _checkingProfile = false;
    }
    
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _session = data.session;
          if (_session != null) {
            _checkProfileStatus();
          } else {
            _checkingProfile = false;
            _profileComplete = false;
          }
        });
      }
    });
  }

  Future<void> _checkProfileStatus() async {
    setState(() => _checkingProfile = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          final fullName = data?['full_name'] as String?;
          // Logic: incomplete if null, empty, or 'usuario' (case insensitive)
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
    if (_session == null) {
      return const LoginScreen();
    }

    if (_checkingProfile) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    if (!_profileComplete) {
      return ProfileScreen(
        onSetupComplete: () {
          setState(() {
            _profileComplete = true;
          });
        },
      );
    }
    
    return const PinterestScreen();
  }
}
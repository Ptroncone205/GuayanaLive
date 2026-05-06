import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _supabase = Supabase.instance.client;
  
  bool _isLoading = false;
  bool _isLogin = true; 

  // Controllers for Login
  final _identifierController = TextEditingController(); // Accepts Email OR Username
  final _loginPasswordController = TextEditingController();

  // Controllers for Registration
  final _regEmailController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _identifierController.dispose();
    _loginPasswordController.dispose();
    _regEmailController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _showError('Por favor, llena todos los campos');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String loginEmail = identifier;

      // If the identifier doesn't have an '@', assume it's a username and look up the email
      if (!identifier.contains('@')) {
        final emailResult = await _supabase.rpc('get_email_by_username', params: {'p_username': identifier});
        if (emailResult == null) {
          throw Exception('Usuario no encontrado');
        }
        loginEmail = emailResult as String;
      }

      await _supabase.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );
      // main.dart will automatically redirect on success
    } on AuthException catch (error) {
      _showError('Error de autenticación: ${error.message}');
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _register() async {
    final email = _regEmailController.text.trim();
    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text.trim();
    final confirmPassword = _regConfirmPasswordController.text.trim();

    if (email.isEmpty || username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showError('Todos los campos son obligatorios');
      return;
    }

    if (password != confirmPassword) {
      _showError('Las contraseñas no coinciden');
      return;
    }

    if (password.length < 6) {
      _showError('La contraseña debe tener al menos 6 caracteres');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Verify if username is already taken
      final existingUser = await _supabase
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (existingUser != null) {
        throw Exception('El nombre de usuario ya está en uso');
      }

      // 2. Sign up the user and pass the username in the metadata
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username}, // The SQL trigger reads this to set the profile!
      );
      
      // main.dart will automatically redirect on success
    } on AuthException catch (error) {
      _showError('Error: ${error.message}');
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildLoginFields() {
    return Column(
      children: [
        TextField(
          controller: _identifierController,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico o Usuario',
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: Icon(Icons.lock),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterFields() {
    return Column(
      children: [
        TextField(
          controller: _regEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _regUsernameController,
          decoration: const InputDecoration(
            labelText: 'Nombre de usuario',
            prefixIcon: Icon(Icons.alternate_email),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _regPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: Icon(Icons.lock),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _regConfirmPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirmar contraseña',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24.0),
            margin: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  _isLogin ? 'Iniciar Sesión' : 'Crea tu cuenta',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Switch between forms
                _isLogin ? _buildLoginFields() : _buildRegisterFields(),
                
                const SizedBox(height: 24),
                
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isLoading ? null : (_isLogin ? _login : _register),
                  child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_isLogin ? 'Entrar' : 'Registrarse', style: const TextStyle(fontSize: 16, color: Colors.white)),
                ),
                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: () {
                    setState(() => _isLogin = !_isLogin);
                  },
                  child: Text(
                    _isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Inicia sesión',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
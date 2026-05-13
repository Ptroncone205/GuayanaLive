import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void showAuthModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const AuthModal(isBottomSheet: true),
    ),
  );
}

class AuthModal extends StatefulWidget {
  final bool isBottomSheet;
  const AuthModal({super.key, this.isBottomSheet = false});

  @override
  State<AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<AuthModal> {
  final _supabase = Supabase.instance.client;
  
  bool _isLoading = false;
  bool _isLogin = true; 

  final _identifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();

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
      
      if (widget.isBottomSheet && mounted) {
        Navigator.of(context).pop();
      }
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
      final existingUser = await _supabase
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (existingUser != null) {
        throw Exception('El nombre de usuario ya está en uso');
      }

      // 1. Perform the sign up
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'username': username}, 
      );
      
      // 2. Show the success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Registro exitoso! Por favor, revisa tu correo electrónico para confirmar tu cuenta.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5), // Give them time to read it
          ),
        );
      }

      // 3. Handle UI navigation
      if (mounted) {
        if (widget.isBottomSheet) {
          // If it's the modal from inside the app, close it
          Navigator.of(context).pop();
        } else {
          // If it's the LoginScreen version, switch back to Login mode 
          // so they don't try to register again immediately
          setState(() {
            _isLogin = true;
            _isLoading = false;
          });
          // Clear registration fields
          _regEmailController.clear();
          _regUsernameController.clear();
          _regPasswordController.clear();
          _regConfirmPasswordController.clear();
        }
      }
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
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(24.0),
      margin: widget.isBottomSheet ? EdgeInsets.zero : const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.isBottomSheet 
            ? const BorderRadius.vertical(top: Radius.circular(24))
            : BorderRadius.circular(16),
        boxShadow: widget.isBottomSheet ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isBottomSheet)
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          
          if (!widget.isBottomSheet)
            Icon(Icons.school, size: 64, color: primaryColor),
            
          const SizedBox(height: 16),
          Text(
            _isLogin ? 'Iniciar Sesión' : 'Crea tu cuenta',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          _isLogin ? _buildLoginFields() : _buildRegisterFields(),
          
          const SizedBox(height: 24),
          
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
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
              style: TextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
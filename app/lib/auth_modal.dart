import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'translations.dart';

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
      _showError(Translations.text(context, 'fill_all_fields'));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String loginEmail = identifier;

      if (!identifier.contains('@')) {
        final emailResult = await _supabase.rpc('get_email_by_username', params: {'p_username': identifier});
        if (emailResult == null) {
          throw Exception(Translations.text(context, 'user_not_found'));
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
      _showError('${Translations.text(context, 'auth_error')}: ${error.message}');
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

  if (email.isEmpty ||
      username.isEmpty ||
      password.isEmpty ||
      confirmPassword.isEmpty) {
    _showError(Translations.text(context, 'fill_all_fields'));
    return;
  }

  if (password != confirmPassword) {
    _showError(Translations.text(context, 'passwords_dont_match'));
    return;
  }

  if (password.length < 6) {
    _showError(Translations.text(context, 'password_length_error'));
    return;
  }

  setState(() => _isLoading = true);

  try {
    // CHECK USERNAME
    final existingUser = await _supabase
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();

    if (existingUser != null) {
      throw Exception(
        Translations.text(context, 'username_in_use'),
      );
    }

    // TRY SIGNUP
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
      },
      emailRedirectTo:
          'https://YOURPROJECT.workers.dev',
    );

    // SUCCESS
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.text(
              context,
              'registration_success',
            ),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    }

    // SWITCH TO LOGIN
    if (mounted) {
      setState(() {
        _isLogin = true;
      });

      _regEmailController.clear();
      _regUsernameController.clear();
      _regPasswordController.clear();
      _regConfirmPasswordController.clear();
    }
  } on AuthException catch (error) {
    final msg = error.message.toLowerCase();

    // EMAIL EXISTS BUT NOT VERIFIED
    if (msg.contains('already registered') ||
        msg.contains('user already registered')) {
      try {
        await _supabase.auth.resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo:
              'https://YOURPROJECT.workers.dev',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Verification email resent.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        _showError(
          'Account exists. Please login.',
        );
      }
    } else {
      _showError(error.message);
    }
  } catch (e) {
    _showError(
      e.toString().replaceAll('Exception: ', ''),
    );
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  Widget _buildLoginFields() {
    return Column(
      children: [
        TextField(
          controller: _identifierController,
          decoration: InputDecoration(
            labelText: Translations.text(context, 'email_or_username'),
            prefixIcon: const Icon(Icons.person),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: Translations.text(context, 'password'),
            prefixIcon: const Icon(Icons.lock),
            border: const OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: Translations.text(context, 'email'),
            prefixIcon: const Icon(Icons.email),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _regUsernameController,
          decoration: InputDecoration(
            labelText: Translations.text(context, 'username'),
            prefixIcon: const Icon(Icons.alternate_email),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _regPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: Translations.text(context, 'password'),
            prefixIcon: const Icon(Icons.lock),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _regConfirmPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: Translations.text(context, 'confirm_password'),
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
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
            Icon(Icons.local_florist, size: 64, color: primaryColor),
            
          const SizedBox(height: 16),
          Text(
            _isLogin ? Translations.text(context, 'login') : Translations.text(context, 'create_account'),
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
              : Text(_isLogin ? Translations.text(context, 'login') : Translations.text(context, 'register'), style: const TextStyle(fontSize: 16, color: Colors.white)),
          ),
          const SizedBox(height: 16),
          
          TextButton(
            onPressed: () {
              setState(() => _isLogin = !_isLogin);
            },
            child: Text(
              _isLogin ? Translations.text(context, 'no_account_prompt') : Translations.text(context, 'have_account_prompt'),
              style: TextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
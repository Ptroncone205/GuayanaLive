import 'package:flutter/material.dart';
import 'auth_modal.dart';
import 'main.dart'; // To access guestModeNotifier
import 'translations.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AuthModal(isBottomSheet: false),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  // Activate guest mode natively
                  guestModeNotifier.value = true;
                },
                icon: const Icon(Icons.person_outline, color: Colors.grey),
                label: Text(
                  Translations.text(context, 'continue_as_guest'),
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
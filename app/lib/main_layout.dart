import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pinterest_screen.dart';
import 'chat_screen.dart';
import 'user_chat_screen.dart'; // Import the missing feature
import 'profile_screen.dart';
import 'camera_screen.dart';
import 'auth_modal.dart';
import 'map_screen.dart'; // Tu nueva pantalla de mapa

final GlobalKey<PinterestScreenState> pinterestKey =
    GlobalKey<PinterestScreenState>();

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  String? _profileAvatarUrl;
  late final StreamSubscription<dynamic> _authSubscription;

  // The persistent screens in our stack (AQUÍ ESTÁ EL MAPA AÑADIDO)
  final List<Widget> _screens = [
    PinterestScreen(key: pinterestKey), // Stack Index 0
    const ChatScreen(), // Stack Index 1
    const MapScreen(), // Stack Index 2 (Nueva pantalla del mapa)
    const UserChatScreen(), // Stack Index 3
    const ProfileScreen(), // Stack Index 4
  ];

  // Logic to determine which screen from the list above to show
  int get _activeScreenIndex {
    switch (_selectedIndex) {
      case 0:
        return 0; // Home Feed
      case 1:
        return 1; // AI Chat
      case 3:
        return 2; // Map (El índice 2 de navegación está reservado para "Añadir")
      case 4:
        return 3; // User Chat
      case 5:
        return 4; // Profile
      default:
        return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserAvatar();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) {
        _loadUserAvatar();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadUserAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (_profileAvatarUrl != null) {
        setState(() => _profileAvatarUrl = null);
      }
      return;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      final avatarUrl = profile?['avatar_url'] as String?;
      if (mounted) {
        setState(() {
          _profileAvatarUrl = (avatarUrl != null && avatarUrl.isNotEmpty)
              ? avatarUrl
              : null;
        });
      }
    } catch (_) {
      if (mounted && _profileAvatarUrl != null) {
        setState(() => _profileAvatarUrl = null);
      }
    }
  }

  void _onItemTapped(int index) {
    // Intercept "Add Post" (Index 2) to show the upload options
    if (index == 2) {
      if (Supabase.instance.client.auth.currentUser == null) {
        showAuthModal(context);
      } else {
        pinterestKey.currentState?.showAddPostOptions();
      }
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context),
          Expanded(
            child: IndexedStack(index: _activeScreenIndex, children: _screens),
          ),
        ],
      ),
      // The Scan button now ONLY appears if we are on the Home Feed (_selectedIndex == 0)
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraScreen()),
                );
              },
              child: const Icon(Icons.camera_alt, size: 28),
            )
          : null,
      bottomNavigationBar: isDesktop ? null : _buildBottomNavBar(context),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      width: 80,
      color: primaryColor,
      child: Column(
        children: [
          const SizedBox(height: 20),
          _AnimatedNavButton(
            icon: _buildProfileNavIcon(),
            activeIcon: _buildProfileNavIcon(isActive: true),
            isSelected: _selectedIndex == 4,
            onTap: () => _onItemTapped(4),
          ),
          _AnimatedNavButton(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            isSelected: _selectedIndex == 0,
            onTap: () => _onItemTapped(0),
          ),
          _AnimatedNavButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            activeIcon: const Icon(Icons.auto_awesome),
            isSelected: _selectedIndex == 1,
            onTap: () => _onItemTapped(1),
          ),
          _AnimatedNavButton(
            icon: Icons.map_outlined,
            activeIcon: Icons.map,
            isSelected: _selectedIndex == 3, // El mapa es el 3
            onTap: () => _onItemTapped(3),
          ),

          _AnimatedNavButton(
            icon: const Icon(Icons.chat_bubble_outline),
            activeIcon: const Icon(Icons.chat_bubble),
            isSelected: _selectedIndex == 4,
            onTap: () => _onItemTapped(4),
          ),

          const Spacer(),
          _AnimatedNavButton(
            icon: const Icon(Icons.add_box_outlined),
            activeIcon: const Icon(Icons.add_box),
            isSelected: false,
            onTap: () =>
                _onItemTapped(2), // Añadir sigue siendo el 2 (no cambia estado)
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: primaryColor,
        border: Border(
          top: BorderSide(color: Colors.black.withOpacity(0.05), width: 1),
        ),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        iconSize: 28,
        // Detailed labels for improved developer readability
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home Feed', // Índice 0
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_outlined),
            activeIcon: Icon(Icons.auto_awesome),
            label: 'AI Chat', // Índice 1
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            activeIcon: Icon(Icons.add_box),
            label: 'Add New Post', // Índice 2
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map', // Índice 3
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'User Messages', // Índice 4
          ),
          BottomNavigationBarItem(
            icon: _buildProfileNavIcon(),
            activeIcon: _buildProfileNavIcon(isActive: true),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildProfileNavIcon({bool isActive = false}) {
    if (_profileAvatarUrl != null) {
      return CircleAvatar(
        radius: 14,
        backgroundImage: NetworkImage(_profileAvatarUrl!),
      );
    }

    return Icon(
      isActive ? Icons.person : Icons.person_outline,
      size: 24,
      color: Colors.white,
    );
  }
}

class _AnimatedNavButton extends StatelessWidget {
  final Widget icon;
  final Widget activeIcon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedNavButton({
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedScale(
          scale: isSelected ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(child: isSelected ? activeIcon : icon),
          ),
        ),
      ),
    );
  }
}

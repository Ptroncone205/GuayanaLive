import 'package:flutter/material.dart';
import 'pinterest_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'camera_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const PinterestScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()));
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildBottomNavBar(context),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    
    return Container(
      width: 80, // Más delgado
      color: primaryColor, 
      child: Column(
        children: [
          const SizedBox(height: 20),
          _AnimatedNavButton(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            isSelected: _selectedIndex == 0,
            onTap: () => _onItemTapped(0),
          ),
          _AnimatedNavButton(
            icon: Icons.auto_awesome_outlined, // Sparkles IA
            activeIcon: Icons.auto_awesome,
            isSelected: _selectedIndex == 1,
            onTap: () => _onItemTapped(1),
          ),
          _AnimatedNavButton(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            isSelected: _selectedIndex == 2,
            onTap: () => _onItemTapped(2),
          ),
          const Spacer(),
          _AnimatedNavButton(
            icon: Icons.camera_alt_outlined,
            activeIcon: Icons.camera_alt,
            isSelected: false,
            onTap: () => _onItemTapped(3),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: primaryColor,
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05), width: 1)),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent, // Usa el color del container
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        showSelectedLabels: false, // Sin texto
        showUnselectedLabels: false, // Sin texto
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        iconSize: 30, // Iconos más grandes
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_outlined),
            activeIcon: Icon(Icons.auto_awesome),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            activeIcon: Icon(Icons.camera_alt),
            label: '',
          ),
        ],
      ),
    );
  }
}

class _AnimatedNavButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
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
          child: Icon(
            isSelected ? activeIcon : icon,
            color: Colors.white,
            size: 30, // Iconos más grandes
          ),
        ),
      ),
    );
  }
}
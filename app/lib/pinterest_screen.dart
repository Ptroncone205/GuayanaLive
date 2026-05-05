import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class PinterestScreen extends StatefulWidget {
  const PinterestScreen({super.key});

  @override
  State<PinterestScreen> createState() => _PinterestScreenState();
}

class _PinterestScreenState extends State<PinterestScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  List<Map<String, dynamic>> _filteredPins = [];

  final List<Map<String, dynamic>> _pins = const [
    {
      'title': 'Montaña',
      'imageUrl': 'https://picsum.photos/200/300?random=1',
      'height': 300.0,
    },
    {
      'title': 'Playa',
      'imageUrl': 'https://picsum.photos/200/400?random=2',
      'height': 400.0,
    },
    {
      'title': 'Ciudad',
      'imageUrl': 'https://picsum.photos/200/250?random=3',
      'height': 250.0,
    },
    {
      'title': 'Naturaleza',
      'imageUrl': 'https://picsum.photos/200/350?random=4',
      'height': 350.0,
    },
    {
      'title': 'Café',
      'imageUrl': 'https://picsum.photos/200/280?random=5',
      'height': 280.0,
    },
    {
      'title': 'Arte',
      'imageUrl': 'https://picsum.photos/200/320?random=6',
      'height': 320.0,
    },
    {
      'title': 'Flores',
      'imageUrl': 'https://picsum.photos/200/380?random=7',
      'height': 380.0,
    },
    {
      'title': 'Nieve',
      'imageUrl': 'https://picsum.photos/200/260?random=8',
      'height': 260.0,
    },
    {
      'title': 'Atardecer',
      'imageUrl': 'https://picsum.photos/200/340?random=9',
      'height': 340.0,
    },
    {
      'title': 'Viaje',
      'imageUrl': 'https://picsum.photos/200/290?random=10',
      'height': 290.0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _filteredPins = List<Map<String, dynamic>>.from(_pins);
    _searchController.addListener(() {
      _filterPins(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showAddPostOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Añadir publicación'),
                subtitle: Text('Selecciona cámara o galería'),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _openCameraScreen();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir desde dispositivo'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (!mounted) return;

      if (pickedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se seleccionó ninguna imagen.')),
        );
        return;
      }

      setState(() {
        _selectedImage = pickedFile;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archivo seleccionado: ${pickedFile.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  Future<void> _openCameraScreen() async {
    final imagePath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const CameraScreen(),
      ),
    );

    if (imagePath != null && mounted) {
      setState(() {
        _selectedImage = XFile(imagePath);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto tomada desde la cámara')),
      );
    }
  }

  void _filterPins(String query) {
    final filtered = query.isEmpty
        ? _pins
        : _pins.where((pin) {
            final title = (pin['title'] as String).toLowerCase();
            return title.contains(query.toLowerCase());
          }).toList();

    setState(() {
      _filteredPins = filtered;
    });
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    FocusScope.of(context).requestFocus(_searchFocusNode);
  }

  void _stopSearch() {
    _searchController.clear();
    _filterPins('');
    setState(() {
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: !_isSearching
            ? const Text('Pinterest Style')
            : TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Buscar publicaciones',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
                  border: InputBorder.none,
                ),
              ),
        backgroundColor: Colors.redAccent,
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _stopSearch,
              tooltip: 'Cerrar búsqueda',
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _startSearch,
              tooltip: 'Buscar',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPostOptions,
        backgroundColor: Colors.redAccent,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Row(
        children: [
          Container(
            width: 100,
            color: Colors.red.shade50,
            child: Column(
              children: [
                const SizedBox(height: 20),
                _NavButton(
                  icon: Icons.person,
                  label: 'Perfil',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const ProfileScreen()),
                    );
                  },
                ),
                _NavButton(
                  icon: Icons.home_filled,
                  label: 'Feed',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ver feed')),
                    );
                  },
                ),
                _NavButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'IA',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const ChatScreen()),
                    );
                  },
                ),
                _NavButton(
                  icon: Icons.camera_alt,
                  label: 'Cámara',
                  onTap: () async {
                    final imagePath = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (context) => const CameraScreen(),
                      ),
                    );
                    if (imagePath != null && mounted) {
                      setState(() {
                        _selectedImage = XFile(imagePath);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Foto tomada desde la cámara')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  if (_selectedImage != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12.0),
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.grey.shade200,
                        image: DecorationImage(
                          image: FileImage(
                            File(_selectedImage!.path),
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: _filteredPins.isEmpty
                        ? const Center(
                            child: Text('No se encontraron publicaciones.'),
                          )
                        : MasonryGridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8.0,
                            crossAxisSpacing: 8.0,
                            itemCount: _filteredPins.length,
                            itemBuilder: (context, index) {
                              final pin = _filteredPins[index];
                              return GestureDetector(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Tapped on pin ${index + 1}')),
                                  );
                                },
                                child: Container(
                                  height: pin['height'],
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12.0),
                                    image: DecorationImage(
                                      image: NetworkImage(pin['imageUrl']),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      margin: const EdgeInsets.all(8.0),
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(12.0),
                                      ),
                                      child: Text(
                                        pin['title'],
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.0),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.redAccent),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'camera_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class PinterestScreen extends StatefulWidget {
  const PinterestScreen({super.key});

  @override
  State<PinterestScreen> createState() => _PinterestScreenState();
}

class _PinterestScreenState extends State<PinterestScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  bool _isSearching = false;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _pins = [];
  List<Map<String, dynamic>> _filteredPins = [];

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchPins();
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

  Future<void> _fetchPins() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('pins')
          .select()
          .order('created_at', ascending: false);
          
      setState(() {
        _pins = List<Map<String, dynamic>>.from(response);
        _filteredPins = List<Map<String, dynamic>>.from(_pins);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando publicaciones: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadPin(XFile image, String title) async {
    try {
      // Use image.name instead of image.path for the extension, as web blob URLs don't have extensions
      final fileExt = image.name.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // 1. Upload image to Supabase Storage (Handling Web vs Mobile)
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _supabase.storage.from('images').uploadBinary(fileName, bytes);
      } else {
        final file = File(image.path);
        await _supabase.storage.from('images').upload(fileName, file);
      }

      // 2. Get public URL
      final imageUrl = _supabase.storage.from('images').getPublicUrl(fileName);

      // 3. Insert record into database
      await _supabase.from('pins').insert({
        'title': title,
        'image_url': imageUrl,
        'height': 200.0 + Random().nextInt(200), // Random height for masonry
      });

      // 4. Refresh feed
      await _fetchPins();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Publicación subida con éxito!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir: $e')),
        );
      }
    }
  }

  Future<void> _showUploadDialog(XFile image) async {
    final titleController = TextEditingController();
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nueva publicación'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: kIsWeb
                        ? Image.network(
                            image.path, 
                            height: 150,
                            width: 300,
                            fit: BoxFit.cover,
                            // Adding error builder just in case the web blob fails
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 150,
                              width: 300,
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          )
                        : Image.file(
                            File(image.path), 
                            height: 150,
                            width: 300,
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Título de la imagen',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !isUploading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (titleController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Por favor ingresa un título')),
                            );
                            return;
                          }
                          setDialogState(() => isUploading = true);
                          await _uploadPin(image, titleController.text.trim());
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Subir', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
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
        return;
      }
      
      await _showUploadDialog(pickedFile);
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
      await _showUploadDialog(XFile(imagePath));
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
                    _fetchPins(); // Refresh feed manually
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
                    await _openCameraScreen();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : _filteredPins.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No se encontraron publicaciones.'),
                          TextButton(
                            onPressed: _fetchPins,
                            child: const Text('Recargar', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchPins,
                      color: Colors.redAccent,
                      child: MasonryGridView.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8.0,
                          crossAxisSpacing: 8.0,
                          itemCount: _filteredPins.length,
                          itemBuilder: (context, index) {
                            final pin = _filteredPins[index];
                            return GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(pin['title'])),
                                );
                              },
                              child: Container(
                                height: (pin['height'] as num?)?.toDouble() ?? 250.0,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.0),
                                  color: Colors.grey.shade300,
                                  image: DecorationImage(
                                    image: NetworkImage(pin['image_url']),
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
                                      pin['title'] ?? 'Sin título',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
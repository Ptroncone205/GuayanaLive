import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'camera_screen.dart';
import 'pin_detail_screen.dart';
import 'auth_modal.dart';

class PinterestScreen extends StatefulWidget {
  const PinterestScreen({super.key});

  @override
  State<PinterestScreen> createState() => PinterestScreenState(); // State exposed globally
}

class PinterestScreenState extends State<PinterestScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  bool _isSearching = false;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _pins = [];
  List<Map<String, dynamic>> _filteredPins = [];
  List<String> _existingTags = [];
  final List<String> _selectedTagFilters = [];
  final TextEditingController _tagController = TextEditingController();
  final List<String> _draftTags = [];

  final _supabase = Supabase.instance.client;
  
  bool get isGuest => _supabase.auth.currentUser == null;

  @override
  void initState() {
    super.initState();
    _fetchExistingTags();
    _fetchPins();
    _searchController.addListener(() {
      _filterPins(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _fetchPins() async {
    setState(() => _isLoading = true);
    try {
      final pinResponse = await _supabase
          .from('pins')
          .select('id,title,image_url,height,created_at, user_id, profiles(username, avatar_url)') 
          .order('created_at', ascending: false);

      final pins = List<Map<String, dynamic>>.from(pinResponse as List);
      final pinIds = pins.map((pin) => pin['id'] as int).toList();

      // Obtener conteo de likes para cada pin
      final likeCounts = pinIds.isEmpty
          ? <int, int>{}
          : Map<int, int>.fromEntries(
              (await _supabase
                  .from('pin_likes')
                  .select('pin_id')
                  .inFilter('pin_id', pinIds) as List)
                  .map((row) => row['pin_id'] as int)
                  .fold<Map<int, int>>({}, (counts, pinId) {
                    counts[pinId] = (counts[pinId] ?? 0) + 1;
                    return counts;
                  }).entries);

      final tagRows = pinIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _supabase
                  .from('pin_tags')
                  .select('pin_id, tags(name)')
                  .inFilter('pin_id', pinIds) 
              as List);

      final pinTagsMap = <int, List<String>>{};
      for (final row in tagRows) {
        final pinId = row['pin_id'] as int?;
        final tag = ((row['tags'] as Map<String, dynamic>?)?['name']) as String?;
        if (pinId != null && tag != null) {
          pinTagsMap.putIfAbsent(pinId, () => []).add(tag);
        }
      }

      if (!mounted) return;
      setState(() {
        _pins = pins.map((pin) {
          final pinId = pin['id'] as int?;
          return {
            ...pin,
            'tags': pinId != null ? List<String>.from(pinTagsMap[pinId] ?? []) : <String>[],
            'like_count': pinId != null ? likeCounts[pinId] ?? 0 : 0,
          };
        }).toList();
      });
      _filterPins(_searchController.text);
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

  Future<void> _uploadPin(XFile image, String title, List<String> tags) async {
    try {
      final fileExt = image.name.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _supabase.storage.from('images').uploadBinary(fileName, bytes);
      } else {
        final file = File(image.path);
        await _supabase.storage.from('images').upload(fileName, file);
      }

      final imageUrl = _supabase.storage.from('images').getPublicUrl(fileName);

      final pinResponse = await _supabase.from('pins').insert({
        'title': title,
        'image_url': imageUrl,
        'height': 200.0 + Random().nextInt(200), 
        'user_id': _supabase.auth.currentUser!.id, 
      }).select('id');

      final pinRows = List<Map<String, dynamic>>.from(pinResponse as List);
      final pinId = pinRows.isNotEmpty ? pinRows.first['id'] as int? : null;

      if (pinId != null && tags.isNotEmpty) {
        final tagIds = await _ensureTagIds(tags);

        if (tagIds.isNotEmpty) {
          await _supabase.from('pin_tags').insert(
            tagIds.map((tagId) => {'pin_id': pinId, 'tag_id': tagId}).toList(),
          );
        }
      }

      await _fetchPins();
      await _fetchExistingTags();
      
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

  Future<void> _fetchExistingTags() async {
    try {
      final response = await _supabase
          .from('tags')
          .select('name')
          .order('name', ascending: true);

      final tags = List<Map<String, dynamic>>.from(response as List);
      if (!mounted) return;

      setState(() {
        _existingTags = tags.map((tag) => tag['name'] as String).toList();
      });
    } catch (_) { }
  }

  String _normalizeTag(String tag) {
    return tag.trim().toLowerCase();
  }

  Future<List<int>> _ensureTagIds(List<String> tags) async {
    final normalizedTags = tags.map(_normalizeTag).where((tag) => tag.isNotEmpty).toSet().toList();
    if (normalizedTags.isEmpty) return [];

    try {
      final existingResponse = await _supabase
          .from('tags')
          .select('id,name')
          .inFilter('name', normalizedTags); 

      final existingTags = List<Map<String, dynamic>>.from(existingResponse as List);
      final existingTagNames = existingTags
          .map((tag) => (tag['name'] as String).toLowerCase())
          .toSet();
      final missingTags = normalizedTags.where((tag) => !existingTagNames.contains(tag)).toList();

      if (missingTags.isNotEmpty) {
        await _supabase.from('tags').insert(
          missingTags.map((tag) => {'name': tag}).toList(),
        );
      }

      final allResponse = await _supabase
          .from('tags')
          .select('id,name')
          .inFilter('name', normalizedTags); 

      final allTags = List<Map<String, dynamic>>.from(allResponse as List);
      if (!mounted) return [];

      return allTags.map((tag) => tag['id'] as int).toList();
    } catch (e) {
      return [];
    }
  }

  void _addDraftTagsFromInput(String input, void Function(void Function()) setDialogState) {
    final values = input
        .split(',')
        .map(_normalizeTag)
        .where((tag) => tag.isNotEmpty)
        .toList();
    if (values.isEmpty) return;

    setDialogState(() {
      for (final tag in values) {
        if (!_draftTags.contains(tag)) {
          _draftTags.add(tag);
        }
      }
      _tagController.clear();
    });
  }

  void _toggleTagFilter(String tag) {
    setState(() {
      if (_selectedTagFilters.contains(tag)) {
        _selectedTagFilters.remove(tag);
      } else {
        _selectedTagFilters.add(tag);
      }
    });
    _filterPins(_searchController.text);
  }

  void _clearTagFilters() {
    setState(() {
      _selectedTagFilters.clear();
    });
    _filterPins(_searchController.text);
  }

  Future<void> _showUploadDialog(XFile image) async {
    final titleController = TextEditingController();
    _tagController.clear();
    setState(() => _draftTags.clear());
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = _tagController.text.trim().toLowerCase();
            final tagSuggestions = query.isEmpty
                ? <String>[]
                : _existingTags
                    .where((tag) => tag.contains(query) && !_draftTags.contains(tag))
                    .toList();

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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      labelText: 'Tags',
                      hintText: 'ej. viaje, naturaleza',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _tagController.text.trim().isEmpty
                            ? null
                            : () => _addDraftTagsFromInput(_tagController.text, setDialogState),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (value) => _addDraftTagsFromInput(value, setDialogState),
                    enabled: !isUploading,
                  ),
                  const SizedBox(height: 12),
                  if (_draftTags.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _draftTags.map((tag) {
                          return Chip(
                            label: Text(tag),
                            onDeleted: () {
                              setDialogState(() {
                                _draftTags.remove(tag);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  if (tagSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tagSuggestions.map((tag) {
                          return ActionChip(
                            label: Text(tag),
                            onPressed: () {
                              setDialogState(() {
                                if (!_draftTags.contains(tag)) {
                                  _draftTags.add(tag);
                                }
                                _tagController.clear();
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
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
                          await _uploadPin(image, titleController.text.trim(), _draftTags);
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

  // Exposed globally to trigger from MainLayout's Navbar
  Future<void> showAddPostOptions() async {
    if (isGuest) {
      showAuthModal(context);
      return;
    }
    
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
      if (pickedFile == null) return;
      
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
    final lowerQuery = query.toLowerCase();

    final filtered = _pins.where((pin) {
      final title = (pin['title'] as String).toLowerCase();
      final tags = List<String>.from(pin['tags'] as List? ?? []);
      final matchesSearch = lowerQuery.isEmpty ||
          title.contains(lowerQuery) ||
          tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
      final matchesTagFilter = _selectedTagFilters.isEmpty ||
          _selectedTagFilters.any((filter) => tags.contains(filter));
      return matchesSearch && matchesTagFilter;
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
            ? const Text('Guayana Live')
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
        backgroundColor: Theme.of(context).primaryColor,
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
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: _isLoading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedTagFilters.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._selectedTagFilters.map((tag) => FilterChip(
                              label: Text(tag),
                              selected: true,
                              onSelected: (_) => _toggleTagFilter(tag),
                            )),
                        ActionChip(
                          label: const Text('Borrar filtros'),
                          onPressed: _clearTagFilters,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _filteredPins.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('No se encontraron publicaciones.'),
                            TextButton(
                              onPressed: _fetchPins,
                              child: Text('Recargar', style: TextStyle(color: Theme.of(context).primaryColor)),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchPins,
                        color: Theme.of(context).primaryColor,
                        child: MasonryGridView.count(
                            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                            mainAxisSpacing: 8.0,
                            crossAxisSpacing: 8.0,
                            itemCount: _filteredPins.length,
                            itemBuilder: (context, index) {
                              final pin = _filteredPins[index];
                              final pinTags = List<String>.from(pin['tags'] as List? ?? []);
                              final ownerProfile = pin['profiles'] as Map<String, dynamic>?;
                              final ownerAvatarUrl = ownerProfile?['avatar_url'] as String?;

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PinDetailScreen(pin: pin),
                                    ),
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
                                  child: Stack(
                                    children: [
                                      Align(
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
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.white70,
                                          child: CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Colors.grey.shade300,
                                            backgroundImage: ownerAvatarUrl != null && ownerAvatarUrl.isNotEmpty
                                                ? NetworkImage(ownerAvatarUrl)
                                                : null,
                                            child: ownerAvatarUrl == null || ownerAvatarUrl.isEmpty
                                                ? Text(
                                                    (ownerProfile?['username'] ?? ownerProfile?['full_name'] ?? 'U')[0].toString().toUpperCase(),
                                                    style: const TextStyle(fontSize: 12),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                      if (pinTags.isNotEmpty)
                                        Positioned(
                                          left: 8,
                                          right: 8,
                                          bottom: 8,
                                          child: Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: pinTags.take(3).map((tag) {
                                              return GestureDetector(
                                                onTap: () => _toggleTagFilter(tag),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black54,
                                                    borderRadius: BorderRadius.circular(12.0),
                                                  ),
                                                  child: Text(
                                                    tag,
                                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      Positioned(
                                        bottom: pinTags.isNotEmpty ? 40 : 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(12.0),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.favorite,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${pin['like_count'] ?? 0}',
                                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ),
                ),
              ],
            ),
      ),
    );
  }
}
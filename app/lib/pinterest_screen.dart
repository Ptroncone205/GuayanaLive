import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:exif/exif.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'camera_screen.dart';
import 'pin_detail_screen.dart';
import 'auth_modal.dart';
import 'services/groq_service.dart';

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
          .select(
            'id,title,image_url,width,height,created_at, user_id, profiles(username, avatar_url)',
          ) // Agregamos width
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
                          .inFilter('pin_id', pinIds)
                      as List)
                  .map((row) => row['pin_id'] as int)
                  .fold<Map<int, int>>({}, (counts, pinId) {
                    counts[pinId] = (counts[pinId] ?? 0) + 1;
                    return counts;
                  })
                  .entries,
            );

      final tagRows = pinIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _supabase
                      .from('pin_tags')
                      .select('pin_id, tags(name)')
                      .inFilter('pin_id', pinIds)
                  as List,
            );

      final pinTagsMap = <int, List<String>>{};
      for (final row in tagRows) {
        final pinId = row['pin_id'] as int?;
        final tag =
            ((row['tags'] as Map<String, dynamic>?)?['name']) as String?;
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
            'tags': pinId != null
                ? List<String>.from(pinTagsMap[pinId] ?? [])
                : <String>[],
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

  Future<void> _uploadPin(
    XFile image,
    String title,
    List<String> tags,
    bool isFromCamera,
  ) async {
    try {
      Map<String, double>? location = await _extractLocation(image);

      if (location == null && mounted && isFromCamera) {
        final useDeviceGPS = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Ubicación de la especie'),
            content: const Text(
              'No pudimos detectar la ubicación en la foto. Para que este avistamiento se registre en el mapa de calor, necesitamos usar la ubicación actual de tu dispositivo. ¿Deseas permitirlo? (Si cancelas, se subirá sin ubicación).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No, subir sin ubicación'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).primaryColor,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Sí, usar mi ubicación',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );

        if (useDeviceGPS == true) {
          try {
            location = await _getDeviceLocation();
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Ubicación: ${e.toString().replaceAll('Exception: ', '')}',
                  ),
                ),
              );
            }
          }
        }
      }

      final fileExt = image.name.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // 1. OBTENER DIMENSIONES REALES
      final bytes = await image.readAsBytes();
      final decodedImage = await decodeImageFromList(bytes);
      final double realWidth = decodedImage.width.toDouble();
      final double realHeight = decodedImage.height.toDouble();

      // 2. SUBIR A STORAGE
      if (kIsWeb) {
        await _supabase.storage.from('images').uploadBinary(fileName, bytes);
      } else {
        final file = File(image.path);
        await _supabase.storage.from('images').upload(fileName, file);
      }

      final imageUrl = _supabase.storage.from('images').getPublicUrl(fileName);

      // 3. GUARDAR EN DB (Usando dimensiones reales, no random)
      final pinResponse = await _supabase
          .from('pins')
          .insert({
            'title': title,
            'image_url': imageUrl,
            'width': realWidth, // <-- Importante
            'height': realHeight, // <-- Importante
            'user_id': _supabase.auth.currentUser!.id,
            if (location != null) 'latitude': location['latitude'],
            if (location != null) 'longitude': location['longitude'],
          })
          .select('id');

      final pinRows = List<Map<String, dynamic>>.from(pinResponse as List);
      final pinId = pinRows.isNotEmpty ? pinRows.first['id'] as int? : null;

      if (pinId != null && tags.isNotEmpty) {
        final tagIds = await _ensureTagIds(tags);

        if (tagIds.isNotEmpty) {
          await _supabase
              .from('pin_tags')
              .insert(
                tagIds
                    .map((tagId) => {'pin_id': pinId, 'tag_id': tagId})
                    .toList(),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir: $e')));
      }
    }
  }

  Future<Map<String, double>?> _extractLocation(XFile image) async {
    if (kIsWeb)
      return null; // EXIF and Geolocator might need specific web handling or be skipped
    try {
      final bytes = await image.readAsBytes();
      final data = await readExifFromBytes(bytes);

      if (data.containsKey('GPS GPSLatitude') &&
          data.containsKey('GPS GPSLongitude')) {
        final latTag = data['GPS GPSLatitude'];
        final latRef = data['GPS GPSLatitudeRef'];
        final lngTag = data['GPS GPSLongitude'];
        final lngRef = data['GPS GPSLongitudeRef'];

        double? lat = _getDecimalDegrees(latTag, latRef);
        double? lng = _getDecimalDegrees(lngTag, lngRef);

        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
    } catch (e) {
      debugPrint('Error leyendo EXIF: $e');
    }
    return null;
  }

  Future<Map<String, double>?> _getDeviceLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(
          'El servicio de GPS está desactivado. Por favor enciéndelo en la configuración de Windows/Android.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permiso de ubicación denegado.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicación denegado permanentemente.');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error al obtener ubicación: $e');
    }
  }

  double? _getDecimalDegrees(IfdTag? tag, IfdTag? ref) {
    if (tag == null || tag.values.length < 3) return null;
    try {
      final values = tag.values.toList();
      double parseRatio(dynamic val) {
        if (val is Ratio) return val.numerator / val.denominator;
        return double.tryParse(val.toString()) ?? 0.0;
      }

      final d = parseRatio(values[0]);
      final m = parseRatio(values[1]);
      final s = parseRatio(values[2]);

      double degrees = d + (m / 60.0) + (s / 3600.0);
      if (ref != null) {
        final refStr = ref.printable.toUpperCase();
        if (refStr == 'S' || refStr == 'W') {
          degrees = -degrees;
        }
      }
      return degrees;
    } catch (e) {
      return null;
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
    } catch (_) {}
  }

  String _normalizeTag(String tag) {
    return tag.trim().toLowerCase();
  }

  Future<List<int>> _ensureTagIds(List<String> tags) async {
    final normalizedTags = tags
        .map(_normalizeTag)
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedTags.isEmpty) return [];

    try {
      final existingResponse = await _supabase
          .from('tags')
          .select('id,name')
          .inFilter('name', normalizedTags);

      final existingTags = List<Map<String, dynamic>>.from(
        existingResponse as List,
      );
      final existingTagNames = existingTags
          .map((tag) => (tag['name'] as String).toLowerCase())
          .toSet();
      final missingTags = normalizedTags
          .where((tag) => !existingTagNames.contains(tag))
          .toList();

      if (missingTags.isNotEmpty) {
        await _supabase
            .from('tags')
            .insert(missingTags.map((tag) => {'name': tag}).toList());
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

  void _addDraftTagsFromInput(
    String input,
    void Function(void Function()) setDialogState,
  ) {
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

  Future<void> _generateWithAI(
    XFile image,
    TextEditingController titleController,
    void Function(void Function()) setDialogState,
  ) async {
    setDialogState(() => _isLoading = true);
    try {
      final bytes = await image.readAsBytes();
      final groqService = GroqService();
      final result = await groqService.getAutoFillData(bytes);

      if (result.containsKey('titulo')) {
        titleController.text = result['titulo'].toString();
      }
      if (result.containsKey('tags')) {
        final tags = List<String>.from(result['tags'] as List);
        _addDraftTagsFromInput(tags.join(','), setDialogState);
      }
    } catch (e) {
      debugPrint('Error en IA: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al procesar con IA: $e')));
      }
    } finally {
      setDialogState(() => _isLoading = false);
    }
  }

  Future<void> _showUploadDialog(
    XFile image, {
    bool isFromCamera = false,
  }) async {
    final titleController = TextEditingController();
    _tagController.clear();
    setState(() => _draftTags.clear());
    bool isUploading = false;
    bool isGeneratingAI = false;

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
                      .where(
                        (tag) =>
                            tag.contains(query) && !_draftTags.contains(tag),
                      )
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
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  height: 150,
                                  width: 300,
                                  color: Colors.grey.shade300,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
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
                    decoration: InputDecoration(
                      labelText: 'Título de la imagen',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: isGeneratingAI
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.auto_awesome,
                                color: Colors.purple,
                              ),
                        tooltip: 'Autocompletar con IA',
                        onPressed: isGeneratingAI || isUploading
                            ? null
                            : () async {
                                setDialogState(() => isGeneratingAI = true);
                                await _generateWithAI(
                                  image,
                                  titleController,
                                  setDialogState,
                                );
                                setDialogState(() => isGeneratingAI = false);
                              },
                      ),
                    ),
                    enabled: !isUploading && !isGeneratingAI,
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
                        onPressed:
                            _tagController.text.trim().isEmpty || isGeneratingAI
                            ? null
                            : () => _addDraftTagsFromInput(
                                _tagController.text,
                                setDialogState,
                              ),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (value) =>
                        _addDraftTagsFromInput(value, setDialogState),
                    enabled: !isUploading && !isGeneratingAI,
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
                  onPressed: isUploading || isGeneratingAI
                      ? null
                      : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  onPressed: isUploading || isGeneratingAI
                      ? null
                      : () async {
                          if (titleController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Por favor ingresa un título'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isUploading = true);
                          await _uploadPin(
                            image,
                            titleController.text.trim(),
                            _draftTags,
                            isFromCamera,
                          );
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
                      : const Text(
                          'Subir',
                          style: TextStyle(color: Colors.white),
                        ),
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

      await _showUploadDialog(
        pickedFile,
        isFromCamera: source == ImageSource.camera,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  Future<void> _openCameraScreen() async {
    final result = await Navigator.of(context).push<CameraResult>(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (result != null && mounted && result.action == CameraAction.post) {
      await _showUploadDialog(XFile(result.imagePath), isFromCamera: true);
    }
    // CameraAction.scanAI is handled in main_layout.dart
  }

  /// Called from MainLayout's FAB when the user chose "Publicar" after
  /// taking a photo with the dedicated camera button on the Home Feed.
  Future<void> showUploadFromCameraResult(String imagePath) async {
    if (!mounted) return;
    await _showUploadDialog(XFile(imagePath), isFromCamera: true);
  }

  void _filterPins(String query) {
    final lowerQuery = query.toLowerCase();

    final filtered = _pins.where((pin) {
      final title = (pin['title'] as String).toLowerCase();
      final tags = List<String>.from(pin['tags'] as List? ?? []);
      final matchesSearch =
          lowerQuery.isEmpty ||
          title.contains(lowerQuery) ||
          tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
      final matchesTagFilter =
          _selectedTagFilters.isEmpty ||
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
            ? Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).primaryColor,
                ),
              )
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
                          ..._selectedTagFilters.map(
                            (tag) => FilterChip(
                              label: Text(tag),
                              selected: true,
                              onSelected: (_) => _toggleTagFilter(tag),
                            ),
                          ),
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
                                const Icon(
                                  Icons.image_not_supported,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text('No se encontraron publicaciones.'),
                                TextButton(
                                  onPressed: _fetchPins,
                                  child: Text(
                                    'Recargar',
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchPins,
                            color: Theme.of(context).primaryColor,
                            child: MasonryGridView.count(
                              crossAxisCount:
                                  MediaQuery.of(context).size.width > 600
                                  ? 4
                                  : 2,
                              mainAxisSpacing: 8.0,
                              crossAxisSpacing: 8.0,
                              itemCount: _filteredPins.length,
                              itemBuilder: (context, index) {
                                final pin = _filteredPins[index];
                                final pinTags = List<String>.from(
                                  pin['tags'] as List? ?? [],
                                );
                                final ownerProfile =
                                    pin['profiles'] as Map<String, dynamic>?;

                                final maxTags = MediaQuery.of(context).size.width > 1100 ? 4 : 2;
                                final double width =
                                    (pin['width'] as num?)?.toDouble() ?? 0;
                                final double height =
                                    (pin['height'] as num?)?.toDouble() ?? 0;
                                double aspectRatio = width / height;

                                if (width > 0 && height > 0) {
                                  aspectRatio = width / height;
                                  aspectRatio = aspectRatio.clamp(0.6, 1.5);
                                  print(aspectRatio);
                                } else {
                                  aspectRatio = 0.8;
                                }

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            PinDetailScreen(pin: pin),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12.0),
                                    child: Container(
                                      color: Colors.grey.shade300,
                                      child: Stack(
                                        children: [
                                          // USAMOS ASPECTRATIO PARA DEFINIR EL TAMAÑO DINÁMICO
                                          AspectRatio(
                                            aspectRatio: aspectRatio,
                                            child: Image.network(
                                              pin['image_url'],
                                              fit: BoxFit.cover,
                                              // Previene saltos visuales mientras carga
                                              loadingBuilder:
                                                  (
                                                    context,
                                                    child,
                                                    loadingProgress,
                                                  ) {
                                                    if (loadingProgress == null)
                                                      return child;
                                                    return Container(
                                                      color:
                                                          Colors.grey.shade200,
                                                    );
                                                  },
                                            ),
                                          ),

                                          // OVERLAYS (Título)
                                          Positioned(
                                            top: 8,
                                            left: 8,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8.0,
                                                    vertical: 4.0,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black45,
                                                borderRadius:
                                                    BorderRadius.circular(12.0),
                                              ),
                                              child: Text(
                                                pin['title'] ?? 'Sin título',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ),

                                          // AVATAR DEL DUEÑO

                                          // TAGS Y LIKES (Seccion Inferior)
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black54,
                                                  ],
                                                ),
                                              ),
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  // Tags (Máximo 4 para no saturar)
                                                  if (pinTags.isNotEmpty)
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        ...List.generate(
                                                          pinTags.length > maxTags
                                                              ? maxTags
                                                              : pinTags.length,
                                                          (index) => Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                  right:
                                                                      index == 3
                                                                      ? 0
                                                                      : 4,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                    color: Colors
                                                                        .white24,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          8,
                                                                        ),
                                                                  ),
                                                              child: Text(
                                                                '#${pinTags[index]}',
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 9,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),

                                                        // Mostrar "..." si hay más de 4 tags
                                                        if (pinTags.length > 4)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Colors
                                                                      .white24,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        8,
                                                                      ),
                                                                ),
                                                            child: const Text(
                                                              '...',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),

                                                  // Contador de Likes
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
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

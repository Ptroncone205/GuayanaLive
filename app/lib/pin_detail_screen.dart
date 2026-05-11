import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_screen.dart';

class PinDetailScreen extends StatefulWidget {
  final Map<String, dynamic> pin;

  const PinDetailScreen({super.key, required this.pin});

  @override
  State<PinDetailScreen> createState() => _PinDetailScreenState();
}

class _PinDetailScreenState extends State<PinDetailScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _commentController = TextEditingController();
  
  List<Map<String, dynamic>> _relatedPins = [];
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingRelated = true;
  bool _isLoadingComments = true;
  bool _isLiked = false;
  bool _isLikeLoading = false;
  bool _isSavingImage = false;
  int _likesCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchComments();
    _fetchRelatedPins();
    _fetchLikeState();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchComments() async {
    try {
      final response = await _supabase
          .from('comments')
          .select('id, pin_id, text, user_id, created_at')
          .eq('pin_id', widget.pin['id'])
          .order('created_at', ascending: true);

      final comments = List<Map<String, dynamic>>.from(response as List);
      final userIds = comments
          .map((comment) => comment['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final profiles = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _supabase
                  .from('profiles')
                  .select('id, username, full_name')
                  .inFilter('id', userIds),
            );

      final profileById = {
        for (final profile in profiles)
          profile['id'] as String: profile,
      };

      if (mounted) {
        setState(() {
          _comments = comments.map((comment) {
            final userId = comment['user_id'] as String?;
            return {
              ...comment,
              'profiles': userId != null ? profileById[userId] : null,
            };
          }).toList();
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando comentarios: $e')),
        );
      }
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    final currentUser = _supabase.auth.currentUser;
    if (text.isEmpty) return;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes iniciar sesión para comentar.')),
        );
      }
      return;
    }

    _commentController.clear();

    try {
      await _supabase.from('comments').insert({
        'pin_id': widget.pin['id'],
        'text': text,
        'user_id': currentUser.id,
      });

      await _fetchComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar comentario: $e')),
        );
      }
    }
  }

  String get _likesField {
    if (widget.pin.containsKey('likes_count')) return 'likes_count';
    if (widget.pin.containsKey('likes')) return 'likes';
    return 'likes_count';
  }

  bool get _hasLikesField {
    return widget.pin.containsKey('likes_count') || widget.pin.containsKey('likes');
  }

  Future<void> _fetchLikeState() async {
    final pinId = widget.pin['id'];
    if (pinId == null) return;

    if (_hasLikesField) {
      if (mounted) {
        setState(() {
          _likesCount = widget.pin['likes_count'] ?? widget.pin['likes'] ?? 0;
          _isLiked = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _likesCount = 0;
        _isLiked = false;
      });
    }
  }

  Future<void> _toggleLike() async {
    final pinId = widget.pin['id'];
    final currentUserId = _supabase.auth.currentUser?.id;
    if (pinId == null) {
      return;
    }

    if (_isLikeLoading) return;

    if (!_hasLikesField) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Funcionalidad de likes no está disponible para esta publicación.')),
        );
      }
      return;
    }

    if (currentUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes iniciar sesión para dar like.')),
        );
      }
      return;
    }

    setState(() => _isLikeLoading = true);

    try {
      final newCount = _isLiked ? max(0, _likesCount - 1) : _likesCount + 1;
      final updated = await _supabase
          .from('pins')
          .update({_likesField: newCount})
          .eq('id', pinId)
          .select(_likesField)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likesCount = updated != null ? (updated[_likesField] as int? ?? newCount) : newCount;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar like: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLikeLoading = false);
    }
  }

  Future<void> _saveImageToGallery() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abre la imagen en el navegador para guardarla.')),
        );
      }
      return;
    }

    if (_isSavingImage) return;
    setState(() => _isSavingImage = true);

    try {
      final response = await http.get(Uri.parse(widget.pin['image_url'] ?? ''));
      if (response.statusCode != 200) {
        throw Exception('No se pudo descargar la imagen');
      }

      final fileName = 'pin_${widget.pin['id']}_${DateTime.now().millisecondsSinceEpoch}';
      final result = await ImageGallerySaver.saveImage(
        response.bodyBytes,
        name: fileName,
      );

      final saved = result != null && (result['isSuccess'] == true || result['filePath'] != null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saved ? 'Imagen guardada en la galería' : 'No se pudo guardar la imagen')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando imagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingImage = false);
    }
  }

  Future<void> _fetchRelatedPins() async {
    try {
      final tags = List<String>.from(widget.pin['tags'] ?? []);
      
      if (tags.isEmpty) {
        // If no tags, just fetch some random recent pins
        final response = await _supabase
            .from('pins')
            .select('id,title,image_url,height')
            .neq('id', widget.pin['id'])
            .limit(10);
        
        if (mounted) {
          setState(() {
            _relatedPins = List<Map<String, dynamic>>.from(response);
            _isLoadingRelated = false;
          });
        }
        return;
      }

      // Fetch pins that share at least one tag
      final matchingTagsResponse = await _supabase
          .from('tags')
          .select('id, name')
          .inFilter('name', tags);
          
      final tagIds = (matchingTagsResponse as List).map((t) => t['id'] as int).toList();

      final pinTagsResponse = await _supabase
          .from('pin_tags')
          .select('pin_id')
          .inFilter('tag_id', tagIds);

      final relatedPinIds = (pinTagsResponse as List)
          .map((pt) => pt['pin_id'] as int)
          .where((id) => id != widget.pin['id'])
          .toSet()
          .toList();

      if (relatedPinIds.isEmpty) {
        if (mounted) setState(() => _isLoadingRelated = false);
        return;
      }

      final response = await _supabase
          .from('pins')
          .select('id,title,image_url,height')
          .inFilter('id', relatedPinIds)
          .limit(15);

      if (mounted) {
        setState(() {
          _relatedPins = List<Map<String, dynamic>>.from(response);
          _isLoadingRelated = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRelated = false);
    }
  }

  Widget _buildImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        widget.pin['image_url'],
        fit: BoxFit.contain,
        width: double.infinity,
      ),
    );
  }

  Widget _buildDetailsAndComments() {
    final pinTags = List<String>.from(widget.pin['tags'] ?? []);
    final ownerProfile = widget.pin['profiles'] as Map<String, dynamic>?;
    final ownerName = ownerProfile?['username'] ?? 'Anónimo';
    final ownerId = widget.pin['user_id'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
                IconButton(icon: const Icon(Icons.share), onPressed: () {}),
                IconButton(
                  icon: _isLikeLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          color: _isLiked ? Colors.redAccent : Colors.black,
                        ),
                  onPressed: _toggleLike,
                ),
              ],
            ),
            ElevatedButton(
              onPressed: _isSavingImage ? null : _saveImageToGallery,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _isSavingImage
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        Text(
          widget.pin['title'] ?? 'Sin título',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        if (_likesCount > 0) ...[
          const SizedBox(height: 8),
          Text('$_likesCount likes', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54)),
        ],
        
        // Post Owner Profile Header
        if (ownerId != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: ownerId)));
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.redAccent.shade100,
                  child: Text(ownerName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text(ownerName, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],

        if (widget.pin['description'] != null) ...[
          const SizedBox(height: 12),
          Text(widget.pin['description']),
        ],
        
        if (pinTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pinTags.map((tag) => Chip(
              label: Text(tag, style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.grey.shade200,
              side: BorderSide.none,
            )).toList(),
          ),
        ],

        const Divider(height: 32),
        const Text('Comentarios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Expanded(
          child: _isLoadingComments
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
                  ? const Center(child: Text('Aún no hay comentarios.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        final commenterProfile = comment['profiles'] as Map<String, dynamic>?;
                        final commenterName = commenterProfile?['full_name'] ?? 'Usuario';
                        final commenterId = comment['user_id'];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: commenterId == null ? null : () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: commenterId)));
                                },
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.grey.shade300,
                                  child: Text(commenterName[0].toUpperCase(), style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: commenterId == null ? null : () {
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: commenterId)));
                                      },
                                      child: Text(commenterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                    Text(comment['text'], style: const TextStyle(fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
        
        Container(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              CircleAvatar(radius: 18, backgroundColor: Colors.redAccent.shade100, child: const Icon(Icons.person, color: Colors.white)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: InputDecoration(
                    hintText: 'Añadir un comentario...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade200,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: Colors.grey),
                      onPressed: _addComment,
                    ),
                  ),
                  onSubmitted: (_) => _addComment(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Main Post Card
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // WIDE SCREEN LAYOUT (Web/Tablet)
                    if (constraints.maxWidth > 700) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _buildImage(),
                          ),
                          Expanded(
                            flex: 4,
                            child: Container(
                              height: 600, // Fixed height to allow scrolling comments
                              padding: const EdgeInsets.all(24.0),
                              child: _buildDetailsAndComments(),
                            ),
                          ),
                        ],
                      );
                    }
                    // MOBILE LAYOUT
                    return Column(
                      children: [
                        _buildImage(),
                        Container(
                          height: 400, // Give comments a fixed height block on mobile
                          padding: const EdgeInsets.all(16.0),
                          child: _buildDetailsAndComments(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // Related Pins Section
            const SizedBox(height: 24),
            const Text('Más como esto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            if (_isLoadingRelated)
              const CircularProgressIndicator(color: Colors.redAccent)
            else if (_relatedPins.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No hay publicaciones relacionadas.', style: TextStyle(color: Colors.grey)),
              )
            else
              Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: MasonryGridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 800 ? 4 : 2,
                  mainAxisSpacing: 8.0,
                  crossAxisSpacing: 8.0,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _relatedPins.length,
                  itemBuilder: (context, index) {
                    final pin = _relatedPins[index];
                    return GestureDetector(
                      onTap: () {
                        // Navigate to related pin
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PinDetailScreen(pin: pin),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: Image.network(
                          pin['image_url'],
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
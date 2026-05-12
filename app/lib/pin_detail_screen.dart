import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_screen.dart';
import 'auth_modal.dart'; 

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

  bool get isGuest => _supabase.auth.currentUser == null; 

  @override
  void initState() {
    super.initState();
    _fetchComments();
    _fetchRelatedPins();
    _checkLikeStatus();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // --- NUEVA FUNCIÓN PARA OBTENER EL ESTADO DEL LIKE ---
  Future<void> _checkLikeStatus() async {
    if (isGuest) return;
    try {
      final res = await _supabase.from('pin_likes')
          .select('id')
          .eq('pin_id', widget.pin['id'])
          .eq('user_id', _supabase.auth.currentUser!.id)
          .maybeSingle();
      if (mounted) setState(() => _isLiked = res != null);
    } catch (_) {}
  }

  Future<void> _fetchComments() async {
    try {
      final response = await _supabase
          .from('comments')
          .select('*, profiles(username, full_name)') 
          .eq('pin_id', widget.pin['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(response);
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _addComment() async {
    if (isGuest) {
      showAuthModal(context);
      return;
    }

    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    _commentController.clear();
    
    try {
      await _supabase.from('comments').insert({
        'pin_id': widget.pin['id'],
        'text': text,
        'user_id': _supabase.auth.currentUser!.id,
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

  Future<void> _deleteComment(int commentId) async {
    // Pedir confirmación antes de eliminar
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('¿Estás seguro de que deseas eliminar este comentario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('Cancelar')
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Eliminar', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase.from('comments').delete().eq('id', commentId);
      await _fetchComments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comentario eliminado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar comentario: $e')),
        );
      }
    }
  }

  Future<void> _toggleLike() async {
    if (isGuest) {
      showAuthModal(context);
      return;
    }

    final userId = _supabase.auth.currentUser!.id;
    final pinId = widget.pin['id'];

    // UI optimista: Cambiamos el estado visualmente al instante
    setState(() {
      _isLiked = !_isLiked;
    });

    try {
      if (_isLiked) {
        await _supabase.from('pin_likes').insert({'pin_id': pinId, 'user_id': userId});
      } else {
        await _supabase.from('pin_likes').delete().eq('pin_id', pinId).eq('user_id', userId);
      }
    } catch (e) {
      // Si falla, revertimos
      if (mounted) {
        setState(() => _isLiked = !_isLiked);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error actualizando like: $e')),
        );
      }
    }
  }

  Future<void> _fetchRelatedPins() async {
    try {
      final tags = List<String>.from(widget.pin['tags'] ?? []);
      
      if (tags.isEmpty) {
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

      final matchingTagsResponse = await _supabase
          .from('tags')
          .select('id, name')
          .inFilter('name', tags);
          
      final tagIds = (matchingTagsResponse as List).map((t) => t['id'] as int).toList();

      if (tagIds.isEmpty) {
        if (mounted) setState(() => _isLoadingRelated = false);
        return;
      }

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
    final primaryColor = Theme.of(context).primaryColor;
    final pinTags = List<String>.from(widget.pin['tags'] ?? []);
    final ownerProfile = widget.pin['profiles'] as Map<String, dynamic>?;
    final ownerName = ownerProfile?['username'] ?? ownerProfile?['full_name'] ?? 'Anónimo';
    final ownerId = widget.pin['user_id'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? Colors.red : Colors.black), 
                  onPressed: _toggleLike,
                ),
                IconButton(icon: const Icon(Icons.share), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
              ],
            ),
            ElevatedButton(
              onPressed: isGuest ? () => showAuthModal(context) : () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        Text(
          widget.pin['title'] ?? 'Sin título',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        
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
                  backgroundColor: primaryColor.withOpacity(0.3),
                  child: Text(ownerName[0].toUpperCase(), style: TextStyle(color: primaryColor, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text(
                  pinTags.isNotEmpty ? ownerName : 'Usuario eliminado',
                  style: TextStyle(fontWeight: FontWeight.bold, fontStyle: pinTags.isEmpty ? FontStyle.italic : FontStyle.normal)
                ),
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
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : _comments.isEmpty
                  ? const Center(child: Text('Aún no hay comentarios.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        final commenterProfile = comment['profiles'] as Map<String, dynamic>?;
                        final commenterName = commenterProfile?['username'] ?? commenterProfile?['full_name'] ?? 'Usuario';
                        final commenterId = comment['user_id'];
                        final isMyComment = !isGuest && _supabase.auth.currentUser?.id == commenterId;

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
                                    Text(comment['text'] ?? '', style: const TextStyle(fontSize: 14)),
                                  ],
                                ),
                              ),
                              if (isMyComment)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                  onPressed: () => _deleteComment(comment['id']),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
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
              CircleAvatar(radius: 18, backgroundColor: primaryColor.withOpacity(0.3), child: Icon(Icons.person, color: primaryColor)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  readOnly: isGuest,
                  onTap: isGuest ? () {
                    FocusScope.of(context).unfocus();
                    showAuthModal(context);
                  } : null,
                  decoration: InputDecoration(
                    hintText: isGuest ? 'Inicia sesión para comentar...' : 'Añadir un comentario...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade200,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: Colors.grey),
                      onPressed: isGuest ? () => showAuthModal(context) : _addComment,
                    ),
                  ),
                  onSubmitted: isGuest ? (_) => showAuthModal(context) : (_) => _addComment(),
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
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 700) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: _buildImage()),
                          Expanded(
                            flex: 4,
                            child: Container(
                              height: 600, 
                              padding: const EdgeInsets.all(24.0),
                              child: _buildDetailsAndComments(),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildImage(),
                        Container(
                          height: 400, 
                          padding: const EdgeInsets.all(16.0),
                          child: _buildDetailsAndComments(),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text('Más como esto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            if (_isLoadingRelated)
              Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
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
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => PinDetailScreen(pin: pin)),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: Image.network(pin['image_url'], fit: BoxFit.cover),
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
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_screen.dart';
import 'auth_modal.dart';
import 'utils/platform_file_saver.dart';
import 'translations.dart';

class PinDetailScreen extends StatefulWidget {
  final Map<String, dynamic> pin;
  final bool fromProfile;

  const PinDetailScreen({super.key, required this.pin, this.fromProfile = false});

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
  String? _currentUserAvatarUrl;
  final ScrollController _commentScrollController = ScrollController();
  final GlobalKey _imageBoxKey = GlobalKey();
  double? _imageHeight;
  int _likeCount = 0;

  bool get isGuest => _supabase.auth.currentUser == null; 

  @override
  void initState() {
    super.initState();
    _fetchComments();
    _fetchRelatedPins();
    _checkLikeStatus();
    _loadCurrentUserAvatar();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageHeight());
  }

  Future<void> _loadCurrentUserAvatar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (_currentUserAvatarUrl != null) {
        setState(() => _currentUserAvatarUrl = null);
      }
      return;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      final avatarUrl = profile?['avatar_url'] as String?;
      if (mounted) {
        setState(() {
          _currentUserAvatarUrl = avatarUrl != null && avatarUrl.isNotEmpty ? avatarUrl : null;
        });
      }
    } catch (_) {
      if (mounted && _currentUserAvatarUrl != null) {
        setState(() => _currentUserAvatarUrl = null);
      }
    }
  }

  Future<void> _savePinImage() async {
    final imageUrl = widget.pin['image_url'] as String?;
    if (imageUrl == null || imageUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.text(context, 'image_not_found'))),
        );
      }
      return;
    }

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Código de respuesta ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final fileName = 'pin_${widget.pin['id'] ?? DateTime.now().millisecondsSinceEpoch}';
      final savedPath = await saveImageToDevice(bytes, fileName);

      if (mounted) {
        if (savedPath != null) {
          final message = savedPath == 'download'
              ? Translations.text(context, 'download_started')
              : Translations.text(context, 'image_saved', {'path': savedPath});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Translations.text(context, 'could_not_save_image'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Translations.text(context, 'error_saving_image')}: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageHeight());
  }

  @override
  void didUpdateWidget(covariant PinDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageHeight());
  }

  void _updateImageHeight() {
    final context = _imageBoxKey.currentContext;
    final size = context?.size;
    if (size == null) return;
    final newHeight = size.height;
    if (_imageHeight != newHeight) {
      setState(() => _imageHeight = newHeight);
    }
  }

  // --- NUEVA FUNCIÓN PARA OBTENER EL ESTADO DEL LIKE ---
  Future<void> _checkLikeStatus() async {
    if (isGuest) {
      // Para invitados, solo obtenemos el conteo total de likes
      try {
        final countResponse = await _supabase
            .from('pin_likes')
            .select('id')
            .eq('pin_id', widget.pin['id']);
        if (mounted) setState(() => _likeCount = (countResponse as List).length);
      } catch (_) {}
      return;
    }

    try {
      final res = await _supabase.from('pin_likes')
          .select('id')
          .eq('pin_id', widget.pin['id'])
          .eq('user_id', _supabase.auth.currentUser!.id)
          .maybeSingle();
      
      // Obtener conteo total de likes
      final countResponse = await _supabase
          .from('pin_likes')
          .select('id')
          .eq('pin_id', widget.pin['id']);
      
      if (mounted) {
        setState(() {
          _isLiked = res != null;
          _likeCount = (countResponse as List).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchComments() async {
    try {
      final response = await _supabase
          .from('comments')
          .select('*, profiles(username, full_name, avatar_url)') 
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

      // Notify pin owner
      final pinOwnerId = widget.pin['user_id'] as String?;
      final commenterId = _supabase.auth.currentUser!.id;
      if (pinOwnerId != null && pinOwnerId != commenterId) {
        try {
          final myProfile = await _supabase
              .from('profiles')
              .select('full_name, username')
              .eq('id', commenterId)
              .maybeSingle();
          final myName = myProfile != null
              ? (myProfile['full_name'] as String?) ?? (myProfile['username'] as String?) ?? 'Alguien'
              : 'Alguien';
          final pinTitle = (widget.pin['title'] as String?) ?? '';
          await _supabase.from('notifications').insert({
            'user_id': pinOwnerId,
            'actor_id': commenterId,
            'type': 'message',
            'title': Translations.text(context, 'new_comment_title'),
            'message': Translations.text(context, 'new_comment_message',
                {'actor': myName, 'title': pinTitle, 'comment': text}),
            'reference_id': widget.pin['id'].toString(),
            'is_read': false,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {} // Don't block comment if notification fails
      }

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
        title: Text(Translations.text(context, 'delete_comment')),
        content: Text(Translations.text(context, 'delete_comment_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text(Translations.text(context, 'cancel'))
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text(Translations.text(context, 'delete'), style: const TextStyle(color: Colors.red))
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
          SnackBar(content: Text(Translations.text(context, 'comment_deleted'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Translations.text(context, 'error_deleting_comment')}: $e')),
        );
      }
    }
  }

  Future<void> _deletePin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Translations.text(context, 'delete_post')),
        content: Text(Translations.text(context, 'delete_post_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(Translations.text(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(Translations.text(context, 'delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final pinId = widget.pin['id'];

      // eliminar comentarios
      await _supabase.from('comments').delete().eq('pin_id', pinId);

      // eliminar likes
      await _supabase.from('pin_likes').delete().eq('pin_id', pinId);

      // eliminar relaciones tags
      await _supabase.from('pin_tags').delete().eq('pin_id', pinId);

      // eliminar pin
      await _supabase.from('pins').delete().eq('id', pinId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Translations.text(context, 'post_deleted'))),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${Translations.text(context, 'error_deleting_post')}: $e')),
      );
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
      _likeCount += _isLiked ? 1 : -1;
    });

    try {
      if (_isLiked) {
        await _supabase.from('pin_likes').insert({'pin_id': pinId, 'user_id': userId});

        // Notify the pin owner (skip if it's the owner themselves)
        final pinOwnerId = widget.pin['user_id'] as String?;
        if (pinOwnerId != null && pinOwnerId != userId) {
          try {
            final myProfile = await _supabase
                .from('profiles')
                .select('full_name, username')
                .eq('id', userId)
                .maybeSingle();
            final myName = myProfile != null
                ? (myProfile['full_name'] as String?) ?? (myProfile['username'] as String?) ?? 'Alguien'
                : 'Alguien';
            final pinTitle = (widget.pin['title'] as String?) ?? '';
            await _supabase.from('notifications').insert({
              'user_id': pinOwnerId,
              'actor_id': userId,
              'type': 'like',
              'title': Translations.text(context, 'new_like_title'),
              'message': Translations.text(context, 'new_like_message',
                  {'actor': myName, 'title': pinTitle}),
              'reference_id': pinId.toString(),
              'is_read': false,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (_) {} // Don't block the like if notification fails
        }
      } else {
        await _supabase.from('pin_likes').delete().eq('pin_id', pinId).eq('user_id', userId);
      }
    } catch (e) {
      // Si falla, revertimos
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? -1 : 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Translations.text(context, 'error_updating_like')}: $e')),
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
    return SizedBox(
      key: _imageBoxKey,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          widget.pin['image_url'],
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      ),
    );
  }

  // Cambia la firma de la función para aceptar el booleano
Widget _buildDetailsAndComments({required bool isDesktop}) {
  final primaryColor = Theme.of(context).primaryColor;
  final pinTags = List<String>.from(widget.pin['tags'] ?? []);
  final ownerProfile = widget.pin['profiles'] as Map<String, dynamic>?;
  final ownerName = ownerProfile?['username'] ?? ownerProfile?['full_name'] ?? 'Anónimo';
  final ownerId = widget.pin['user_id'];
  final ownerAvatarUrl = ownerProfile?['avatar_url'] as String?;

  // Widgets de cabecera (Likes, Botones, Título, Descripción)
  final headerInfo = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Fila de Acciones (Likes, Share, More, Guardar)
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.red : Colors.black,
                      ),
                      onPressed: _toggleLike,
                    ),
                    Text(
                      '$_likeCount',
                      style: TextStyle(
                        color: _isLiked ? Colors.red : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    IconButton(icon: const Icon(Icons.share), onPressed: () {}),

                    // DELETE BUTTON
                    if (_supabase.auth.currentUser?.id == widget.pin['user_id'])
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: _deletePin,
                      ),

                    IconButton(
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () {},
                    ),
                  ],
                ),
            ],
          ),
          ElevatedButton(
            onPressed: isGuest ? () => showAuthModal(context) : _savePinImage,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: Text(Translations.text(context, 'save'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      // Título
      Text(
        widget.pin['title'] ?? Translations.text(context, 'untitled'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      // Perfil del Dueño
      if (ownerId != null) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: ownerId))),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundImage: ownerAvatarUrl != null && ownerAvatarUrl.isNotEmpty
                    ? NetworkImage(ownerAvatarUrl)
                    : null,
                child: ownerAvatarUrl == null || ownerAvatarUrl.isEmpty
                    ? Text(
                        ownerName[0].toUpperCase(),
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  ownerName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      // Descripción
      if (widget.pin['description'] != null) ...[
        const SizedBox(height: 12),
        Text(widget.pin['description']),
      ],
      // Tags
      if (pinTags.isNotEmpty) ...[
        const SizedBox(height: 12),
        ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: Scrollbar(
            thumbVisibility: true,
            trackVisibility: false,
            interactive: true,
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: pinTags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final tag = pinTags[index];

                  return Chip(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    label: Text(
                      tag,
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
      const Divider(height: 32),
      Text(Translations.text(context, 'comments'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
    ],
  );

  // Lista de comentarios
  Widget commentsList = _isLoadingComments
      ? const Center(child: CircularProgressIndicator())
      : _comments.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(Translations.text(context, 'no_comments_yet'), style: const TextStyle(color: Colors.grey)),
            )
          : Scrollbar(
              controller: _commentScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _commentScrollController,
                shrinkWrap: !isDesktop,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
                  // ... (Mantenemos el mismo itemBuilder de comentarios que tenías)
                  final commenterProfile = comment['profiles'] as Map<String, dynamic>?;
                  final commenterName = commenterProfile?['username'] ?? 'Usuario';
                  final currentUserId = _supabase.auth.currentUser?.id;
                  final isMyComment = currentUserId != null && comment['user_id'] == currentUserId;

                  return InkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: comment['user_id'],
        ),
      ),
    );
  },
  child: ListTile(
    contentPadding: EdgeInsets.zero,

    leading: CircleAvatar(
      radius: 14,
      backgroundImage: commenterProfile?['avatar_url'] != null
          ? NetworkImage(commenterProfile?['avatar_url'])
          : null,
    ),

    title: Text(
      commenterName,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    ),

    subtitle: Text(comment['text'] ?? ''),

    trailing: isMyComment
        ? IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.grey,
            ),
            onPressed: () => _deleteComment(comment['id']),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          )
        : null,
  ),
);
                },
              ),
            );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      headerInfo, // Todo lo que "restauramos" (Likes, Título, etc.)
      if (isDesktop)
        Expanded(child: commentsList) // En desktop, los comentarios usan el resto del alto
      else
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _imageHeight ?? 400),
          child: commentsList,
        ),
      const SizedBox(height: 12),
      _buildCommentInput(primaryColor), // El input de texto al final
    ],
  );
}

// Factorizamos el input para limpieza
Widget _buildCommentInput(Color primaryColor) {
  return Container(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundImage: _currentUserAvatarUrl != null ? NetworkImage(_currentUserAvatarUrl!) : null,
          child: _currentUserAvatarUrl == null ? const Icon(Icons.person) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _commentController,
            decoration: InputDecoration(
              hintText: Translations.text(context, 'add_a_comment'),
              filled: true,
              fillColor: Colors.grey.shade200,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _addComment),
            ),
          ),
        ),
      ],
    ),
  );
}

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
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
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
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
                            // OBLIGAMOS a que este panel mida lo mismo que la imagen
                            height: (_imageHeight ?? 600).clamp(520.0, double.infinity),
                            padding: const EdgeInsets.all(24.0),
                            child: _buildDetailsAndComments(isDesktop: true),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _buildImage(),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildDetailsAndComments(isDesktop: false),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

            const SizedBox(height: 24),
            Text(Translations.text(context, 'more_like_this'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            if (_isLoadingRelated)
              Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
            else if (_relatedPins.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(Translations.text(context, 'no_related_posts'), style: const TextStyle(color: Colors.grey)),
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
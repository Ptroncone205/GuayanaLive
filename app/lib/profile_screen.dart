import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'auth_modal.dart';
import 'main.dart'; 
import 'user_chat_screen.dart'; // Importación necesaria para la navegación al chat
import 'pin_detail_screen.dart'; // Importación para navegar a detalles de pin

class ProfileScreen extends StatefulWidget {
  final String? userId;
  final VoidCallback? onSetupComplete;

  const ProfileScreen({super.key, this.userId, this.onSetupComplete});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  bool _isLoading = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();

  String? _avatarUrl;
  final ImagePicker _picker = ImagePicker();

  final int _followers = 0;
  final int _following = 0;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;
  int _postsCount = 0;

  List<Map<String, dynamic>> _posts = [];
  final _supabase = Supabase.instance.client;

  // Getters de utilidad
  bool get isGuest => widget.userId == null && _supabase.auth.currentUser == null;
  String get _targetUserId => widget.userId ?? _supabase.auth.currentUser?.id ?? '';
  bool get _isMyProfile => widget.userId == null || widget.userId == _supabase.auth.currentUser?.id;
  bool get _isSetupMode => widget.onSetupComplete != null;

  @override
  void initState() {
    super.initState();
    if (isGuest) {
      _isLoading = false;
    } else if (!_isSetupMode) {
      _fetchProfileData();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _fetchProfileData() async {
    if (isGuest) return;
    
    setState(() => _isLoading = true);
    try {
      final profileData = await _supabase
          .from('profiles')
          .select()
          .eq('id', _targetUserId)
          .maybeSingle();

      if (profileData != null) {
        _nameController.text = profileData['full_name'] ?? '';
        _usernameController.text = profileData['username'] ?? '';
        _bioController.text = profileData['bio'] ?? '';
        _locationController.text = profileData['location'] ?? '';
        _websiteController.text = profileData['website'] ?? '';
        _avatarUrl = profileData['avatar_url'];
      }

      final response = await _supabase
          .from('pins')
          .select('id,title,image_url,width,height,created_at, user_id, profiles(username, avatar_url)') 
          .eq('user_id', _targetUserId)
          .order('created_at', ascending: false)
          .limit(9);

      final pins = List<Map<String, dynamic>>.from(response as List);
      final pinIds = pins.map((pin) => pin['id'] as int).toList();

      // Obtener tags para cada pin
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

      if (mounted) {
        setState(() {
          _posts = pins.map((pin) {
            final pinId = pin['id'] as int?;
            return {
              ...pin,
              'tags': pinId != null ? List<String>.from(pinTagsMap[pinId] ?? []) : <String>[],
              'like_count': pinId != null ? likeCounts[pinId] ?? 0 : 0,
            };
          }).toList();
          _postsCount = _posts.length;
          _isLoading = false;
        });
      }

      await _fetchFollowInfo();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFollowInfo() async {
    if (_supabase.auth.currentUser == null || _isMyProfile) return;

    try {
      final followRes = await _supabase.from('follows').select('id')
          .eq('follower_id', _supabase.auth.currentUser!.id)
          .eq('followee_id', _targetUserId)
          .maybeSingle();

      final followersRes = await _supabase.from('follows').select('id').eq('followee_id', _targetUserId);
      final followingRes = await _supabase.from('follows').select('id').eq('follower_id', _targetUserId);

      if (mounted) {
        setState(() {
          _isFollowing = followRes != null;
          _followersCount = (followersRes as List).length;
          _followingCount = (followingRes as List).length;
        });
      }
    } catch (e) {
      debugPrint('Error cargando estado de seguimiento: $e');
    }
  }

  Future<void> _toggleFollow() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      showAuthModal(context);
      return;
    }
    if (_isMyProfile) return;

    setState(() => _isLoading = true);
    try {
      if (_isFollowing) {
        await _supabase.from('follows').delete().match({
          'follower_id': currentUser.id,
          'followee_id': _targetUserId,
        });
        if (mounted) {
          setState(() {
            _isFollowing = false;
            _followersCount = (_followersCount - 1).clamp(0, 999999);
          });
        }
      } else {
        await _supabase.from('follows').insert({
          'follower_id': currentUser.id,
          'followee_id': _targetUserId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        await _supabase.from('notifications').insert({
          'user_id': _targetUserId,
          'actor_id': currentUser.id,
          'type': 'follow',
          'title': 'Nuevo seguidor',
          'message': '${_nameController.text.isNotEmpty ? _nameController.text : 'Alguien'} te sigue.',
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _followersCount += 1;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error actualizando seguimiento: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Lógica para iniciar o abrir un chat existente
  Future<void> _startChatWithUser() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;
    
    setState(() => _isLoading = true);

    try {
      // 1. Buscar si ya existe un hilo entre estos dos usuarios
      final existingThread = await _supabase.from('chat_threads')
          .select('id')
          .or('and(user1_id.eq.${currentUser.id},user2_id.eq.$_targetUserId),and(user1_id.eq.$_targetUserId,user2_id.eq.${currentUser.id})')
          .maybeSingle();

      String threadId;
      if (existingThread != null) {
        threadId = existingThread['id'];
      } else {
        // 2. Si no existe, crear uno nuevo
        final insertRes = await _supabase.from('chat_threads').insert({
          'user1_id': currentUser.id,
          'user2_id': _targetUserId,
          'last_message': 'Chat iniciado',
        }).select('id').single();
        threadId = insertRes['id'];
      }

      final partner = ChatPartner(
        id: _targetUserId,
        name: _nameController.text.isNotEmpty ? _nameController.text : 'Usuario',
        avatarUrl: _avatarUrl,
      );

      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserChatThreadScreen(
          threadId: threadId,
          currentUserId: currentUser.id,
          partner: partner,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar chat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAvatar() async {
    if (!_isMyProfile || isGuest) return;

    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    try {
      final fileExt = pickedFile.name.split('.').last;
      final fileName = '${_targetUserId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        await _supabase.storage.from('avatars').uploadBinary(fileName, bytes);
      } else {
        final file = File(pickedFile.path);
        await _supabase.storage.from('avatars').upload(fileName, file);
      }

      final newAvatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);

      await _supabase.from('profiles').upsert({
        'id': _targetUserId,
        'avatar_url': newAvatarUrl,
      });

      setState(() => _avatarUrl = newAvatarUrl);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar foto: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El nombre es requerido')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.from('profiles').upsert({
        'id': _targetUserId,
        'full_name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'location': _locationController.text.trim(),
        'website': _websiteController.text.trim(),
      });

      setState(() => _isEditing = false);
      
      if (_isSetupMode && widget.onSetupComplete != null) {
        widget.onSetupComplete!();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil guardado')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoField({required String label, required TextEditingController controller}) {
    final bool isEditable = _isEditing || _isSetupMode;

    if ((!isEditable && controller.text.isEmpty) || isGuest) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: !isEditable,
          decoration: InputDecoration(
            filled: !isEditable ? true : false,
            fillColor: isEditable ? null : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          maxLines: label == 'Biografía' ? 3 : 1,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    final content = Scaffold(
      appBar: AppBar(
        title: Text(_isSetupMode ? 'Completa tu perfil' : (_isMyProfile ? 'Mi perfil' : 'Perfil')),
        actions: [
          if (_isMyProfile)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                if (isGuest) {
                  guestModeNotifier.value = false;
                  Navigator.pop(context);
                } else {
                  guestModeNotifier.value = false;
                  _supabase.auth.signOut();
                }
              },
              tooltip: isGuest ? 'Salir' : 'Cerrar sesión',
            )
        ],
      ),
      body: _isLoading && _posts.isEmpty && !_isSetupMode
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isSetupMode) ...[
                      const Center(
                        child: Text(
                          '¡Bienvenido!',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'Por favor completa tu nombre para continuar.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    Row(
                      children: [
                        GestureDetector(
                          onTap: (_isEditing || _isSetupMode) && !isGuest ? _updateAvatar : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 42,
                                backgroundColor: primaryColor.withOpacity(0.3),
                                backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                                child: _avatarUrl == null 
                                    ? Text(
                                        isGuest ? 'I' : (_nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : '?'),
                                        style: const TextStyle(fontSize: 32, color: Colors.white),
                                      )
                                    : null,
                              ),
                              if ((_isEditing || _isSetupMode) && !isGuest)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                                    child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isGuest ? 'Invitado' : (_nameController.text.isNotEmpty ? _nameController.text : 'Usuario'),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              if (!isGuest)
                                Text(
                                  _usernameController.text.isNotEmpty ? '@${_usernameController.text}' : '',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              if (!isGuest)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '$_followersCount seguidores • $_followingCount siguiendo',
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              
                              // BOTONES DE ACCIÓN (Editar o Mensaje)
                              if (_isMyProfile)
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: isGuest 
                                            ? () => showAuthModal(context) 
                                            : (_isEditing || _isSetupMode ? _saveProfile : () => setState(() => _isEditing = true)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                        ),
                                        child: Text(
                                          isGuest ? 'Iniciar sesión / Registrarse' : (_isEditing || _isSetupMode ? 'Guardar perfil' : 'Editar perfil'), 
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isGuest && !_isEditing && !_isSetupMode)
                                      SizedBox(
                                        height: 44,
                                        child: OutlinedButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => const ProfileSettingsScreen(),
                                              ),
                                            );
                                          },
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: Colors.white.withOpacity(0.7)),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                          ),
                                          child: const Icon(Icons.settings, color: Colors.white),
                                        ),
                                      ),
                                  ],
                                )
                              else if (!isGuest)
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _startChatWithUser,
                                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                        label: const Text('Enviar Mensaje'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green.shade700,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _toggleFollow,
                                      icon: Icon(
                                        _isFollowing ? Icons.check : Icons.person_add,
                                        size: 18,
                                      ),
                                      label: Text(_isFollowing ? 'Siguiendo' : 'Seguir'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _isFollowing ? Colors.green.shade700 : Colors.white,
                                        backgroundColor: _isFollowing ? Colors.white : Colors.green.shade700,
                                        side: BorderSide(
                                          color: _isFollowing ? Colors.green.shade700 : Colors.transparent,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    if (isGuest)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0, bottom: 24.0),
                        child: Text(
                          'Regístrate para interactuar con la comunidad, guardar tus especies favoritas y compartir tus propios descubrimientos.', 
                          style: TextStyle(color: Colors.grey, fontSize: 16)
                        ),
                      ),

                    if (!isGuest) ...[
                      _buildInfoField(label: 'Nombre', controller: _nameController),
                      if (!_isSetupMode)
                        _buildInfoField(label: 'Usuario', controller: _usernameController),
                      _buildInfoField(label: 'Biografía', controller: _bioController),
                      _buildInfoField(label: 'Ubicación', controller: _locationController),
                      _buildInfoField(label: 'Sitio web', controller: _websiteController),
                    ],
                    
                    const SizedBox(height: 12),
                    if (!_isSetupMode) ...[
                        Text(_isMyProfile && !isGuest ? 'Tus publicaciones recientes' : 'Publicaciones recientes', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (isGuest)
                          const Text('Regístrate para publicar tus descubrimientos.', style: TextStyle(color: Colors.grey))
                        else if (_posts.isEmpty)
                           Text(_isMyProfile ? 'No has subido ninguna publicación.' : 'Sin publicaciones.', style: const TextStyle(color: Colors.grey))
                        else
                          MasonryGridView.count(
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 700 ? 4 : 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];

                            final double width =
                                (post['width'] as num?)?.toDouble() ?? 0;

                            final double height =
                                (post['height'] as num?)?.toDouble() ?? 0;

                            double aspectRatio = 0.8;

                            if (width > 0 && height > 0) {
                              aspectRatio = width / height;
                              aspectRatio = aspectRatio.clamp(0.6, 1.5);
                            }

                            return GestureDetector(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PinDetailScreen(
                                      pin: post,
                                      fromProfile: true,
                                    ),
                                  ),
                                );

                                // Reload after returning from details
                                if (mounted) {
                                  await _fetchProfileData();
                                }
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.grey.shade300,
                                  child: AspectRatio(
                                    aspectRatio: aspectRatio,
                                    child: Image.network(
                                      post['image_url'],
                                      fit: BoxFit.cover,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                            if (loadingProgress == null)
                                              return child;

                                            return Container(
                                              color: Colors.grey.shade200,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ]
                  ],
                ),
              ),
            ),
    );

    if (_isSetupMode) {
      return PopScope(
        canPop: false,
        child: content,
      );
    }
    return content;
  }
}

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: const [
          _SettingsTile(
            icon: Icons.brightness_6,
            title: 'Modo oscuro',
            subtitle: 'Cambiar el color de los menús a modo oscuro',
          ),
          _SettingsTile(
            icon: Icons.language,
            title: 'Idioma',
            subtitle: 'Colocar la aplicación en otro idioma',
          ),
          _SettingsTile(
            icon: Icons.block,
            title: 'Usuarios bloqueados',
            subtitle: 'Ver usuarios bloqueados',
          ),
          _SettingsTile(
            icon: Icons.download,
            title: 'Fotos descargadas',
            subtitle: 'Solicitar fotos de publicaciones descargadas',
          ),
          _SettingsTile(
            icon: Icons.history,
            title: 'Historial visto',
            subtitle: 'Historial de publicaciones vistas',
          ),
          _SettingsTile(
            icon: Icons.lock,
            title: 'Privacidad',
            subtitle: 'Privacidad',
          ),
          _SettingsTile(
            icon: Icons.help_outline,
            title: 'Solicitar ayuda',
            subtitle: 'Solicitar ayuda',
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
        child: Icon(icon, color: Theme.of(context).primaryColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }
}

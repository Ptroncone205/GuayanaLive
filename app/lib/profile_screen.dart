import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'auth_modal.dart';
import 'locale_provider.dart';
import 'main.dart'; 
import 'translations.dart';
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
    if (_supabase.auth.currentUser == null) return;

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

  // Prevent spam taps
  if (_isLoading) return;

  setState(() => _isLoading = true);

  try {
    if (_isFollowing) {
      // UNFOLLOW
      await _supabase
          .from('follows')
          .delete()
          .match({
            'follower_id': currentUser.id,
            'followee_id': _targetUserId,
          });

      if (mounted) {
        setState(() {
          _isFollowing = false;
          _followersCount =
              (_followersCount - 1).clamp(0, 999999);
        });
      }
    } else {
      // CHECK FIRST (prevents duplicate insert)
      final existing = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', currentUser.id)
          .eq('followee_id', _targetUserId)
          .maybeSingle();

      if (existing == null) {
        await _supabase.from('follows').insert({
          'follower_id': currentUser.id,
          'followee_id': _targetUserId,
          'created_at': DateTime.now()
              .toUtc()
              .toIso8601String(),
        });

        // FOLLOW NOTIFICATION
        final myProfileRes = await _supabase
            .from('profiles')
            .select('full_name, username')
            .eq('id', currentUser.id)
            .maybeSingle();

        final myName = myProfileRes != null
            ? (myProfileRes['full_name'] as String?) ??
                (myProfileRes['username'] as String?) ??
                'Usuario'
            : 'Usuario';

        await _supabase.from('notifications').insert({
          'user_id': _targetUserId,
          'actor_id': currentUser.id,
          'type': 'follow',
          'title': 'Nuevo seguidor',
          'message': '$myName comenzó a seguirte.',
          'reference_id': currentUser.id,
          'is_read': false,
          'created_at': DateTime.now()
              .toUtc()
              .toIso8601String(),
        });
      }

      if (mounted) {
        setState(() {
          _isFollowing = true;
          _followersCount += 1;
        });
      }
    }

    // FINAL SYNC WITH DATABASE
    await _fetchFollowInfo();
  } catch (e) {
    debugPrint('Follow error: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error updating follow: $e',
          ),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
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
          'last_message': Translations.text(context, 'chat_started'),
        }).select('id').single();
        threadId = insertRes['id'];
      }

      final partner = ChatPartner(
        id: _targetUserId,
        name: _nameController.text.isNotEmpty ? _nameController.text : Translations.text(context, 'user'),
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
          SnackBar(content: Text('${Translations.text(context, 'error_starting_chat')}: $e')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Translations.text(context, 'error_updating_photo', {'error': e.toString()}))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Translations.text(context, 'name_required'))));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Translations.text(context, 'profile_saved'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Translations.text(context, 'error_saving_profile', {'error': e.toString()}))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoField({
  required String label,
  required TextEditingController controller,
  bool isBiography = false,
}) {
  final bool isEditable = _isEditing || _isSetupMode;

  // Hide empty fields in view mode
  if ((!isEditable && controller.text.isEmpty) || isGuest) {
    return const SizedBox.shrink();
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.grey.shade800,
          ),
        ),
      ),

      TextField(
        controller: controller,
        readOnly: !isEditable,
        maxLines: isBiography ? 4 : 1,
        cursorColor: Theme.of(context).primaryColor,

        style: TextStyle(
          fontSize: 15,
          color: isEditable
              ? Colors.black87
              : Colors.grey.shade800,
        ),

        decoration: InputDecoration(
          hintText: isEditable
              ? '${Translations.text(context, 'enter')} $label'
              : null,

          filled: true,

          fillColor: isEditable
              ? Colors.white
              : Colors.grey.shade100,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),

          // NORMAL BORDER
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.grey.shade300,
              width: 1.2,
            ),
          ),

          // ENABLED BORDER
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: isEditable
                  ? Colors.grey.shade400
                  : Colors.transparent,
              width: 1.2,
            ),
          ),

          // FOCUSED BORDER
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Theme.of(context).primaryColor,
              width: 2,
            ),
          ),

          // READONLY BORDER
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.transparent,
            ),
          ),
        ),
      ),

      const SizedBox(height: 18),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    final content = Scaffold(
      appBar: AppBar(
        title: Text(_isSetupMode ? Translations.text(context, 'complete_profile') : (_isMyProfile ? Translations.text(context, 'my_profile') : Translations.text(context, 'profile'))),
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
              tooltip: isGuest ? Translations.text(context, 'logout_guest') : Translations.text(context, 'logout'),
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
                      Center(
                        child: Text(
                          Translations.text(context, 'welcome'),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          Translations.text(context, 'complete_profile'),
                          style: const TextStyle(color: Colors.grey),
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
                                isGuest ? Translations.text(context, 'guest') : (_nameController.text.isNotEmpty ? _nameController.text : Translations.text(context, 'user')),
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
                                    Translations.text(context, 'followers_following_count', {
                                      'followers': _followersCount.toString(),
                                      'following': _followingCount.toString(),
                                    }),
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              
                              // BOTONES DE ACCIÓN (Editar o Mensaje)
                              if (_isMyProfile)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 44,
                                      child: ElevatedButton(
                                        onPressed: isGuest 
                                            ? () => showAuthModal(context) 
                                            : (_isEditing || _isSetupMode ? _saveProfile : () => setState(() => _isEditing = true)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                        ),
                                        child: Text(
                                          isGuest ? Translations.text(context, 'login_signup') : (_isEditing || _isSetupMode ? Translations.text(context, 'save_profile') : Translations.text(context, 'edit_profile')),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!_isEditing && !_isSetupMode)
                                      SizedBox(
                                        height: 44,
                                        width: 44,
                                        child: OutlinedButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => const ProfileSettingsScreen(),
                                              ),
                                            );
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: primaryColor,
                                            side: BorderSide(color: Colors.white.withOpacity(0.7)),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                          ),
                                          child: Icon(Icons.settings, color: primaryColor),
                                        ),
                                      ),
                                  ],
                                )
                              else if (!isGuest)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 44,
                                      child: ElevatedButton.icon(
                                        onPressed: _startChatWithUser,
                                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                        label: Text(Translations.text(context, 'send_message')),
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(0, 44),
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                      label: Text(_isFollowing ? Translations.text(context, 'following') : Translations.text(context, 'follow')),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 44),
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                        child: Text(
                          Translations.text(context, 'register_to_interact'),
                          style: const TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),

                    if (!isGuest) ...[
                      _buildInfoField(label: Translations.text(context, 'name'), controller: _nameController),
                      if (!_isSetupMode)
                      _buildInfoField(label: Translations.text(context, 'biography'), controller: _bioController, isBiography: true),
                      _buildInfoField(label: Translations.text(context, 'location'), controller: _locationController),
                      _buildInfoField(label: Translations.text(context, 'website'), controller: _websiteController),
                    ],
                    
                    const SizedBox(height: 12),
                    if (!_isSetupMode) ...[
                        Text(
                          _isMyProfile && !isGuest
                              ? Translations.text(context, 'your_recent_posts')
                              : Translations.text(context, 'recent_posts'),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (isGuest)
                          Text(Translations.text(context, 'register_to_post'), style: const TextStyle(color: Colors.grey))
                        else if (_posts.isEmpty)
                           Text(
                             _isMyProfile ? Translations.text(context, 'no_posts_yet') : Translations.text(context, 'no_publications'),
                             style: const TextStyle(color: Colors.grey),
                           )
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

  Future<void> _showLanguageDialog(BuildContext context) async {
    final localeProvider = LocaleProviderScope.of(context);
    final selectedLocale = localeProvider.locale;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(Translations.text(context, 'select_language')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<Locale>(
                title: Text(Translations.text(context, 'spanish')),
                value: const Locale('es'),
                groupValue: selectedLocale,
                onChanged: (locale) {
                  if (locale != null) {
                    localeProvider.setLocale(locale);
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
              RadioListTile<Locale>(
                title: Text(Translations.text(context, 'english')),
                value: const Locale('en'),
                groupValue: selectedLocale,
                onChanged: (locale) {
                  if (locale != null) {
                    localeProvider.setLocale(locale);
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(Translations.text(context, 'cancel')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.text(context, 'settings')),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SettingsTile(
            icon: Icons.brightness_6,
            title: Translations.text(context, 'dark_mode'),
            subtitle: Translations.text(context, 'dark_mode_subtitle'),
          ),
          _SettingsTile(
            icon: Icons.language,
            title: Translations.text(context, 'language'),
            subtitle: '${Translations.text(context, 'language_subtitle')} • ${Translations.currentLanguageLabel(context)}',
            onTap: () => _showLanguageDialog(context),
          ),
          _SettingsTile(
            icon: Icons.block,
            title: Translations.text(context, 'blocked_users'),
            subtitle: Translations.text(context, 'blocked_users_subtitle'),
          ),
          _SettingsTile(
            icon: Icons.download,
            title: Translations.text(context, 'downloaded_photos'),
            subtitle: Translations.text(context, 'downloaded_photos_subtitle'),
          ),
          _SettingsTile(
            icon: Icons.history,
            title: Translations.text(context, 'view_history'),
            subtitle: Translations.text(context, 'view_history_subtitle'),
          ),
          _SettingsTile(
            icon: Icons.lock,
            title: Translations.text(context, 'privacy'),
            subtitle: Translations.text(context, 'privacy_subtitle'),
          ),
          _SettingsTile(
            icon: Icons.help_outline,
            title: Translations.text(context, 'help_request'),
            subtitle: Translations.text(context, 'help_request_subtitle'),
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

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
      onTap: onTap,
    );
  }
}

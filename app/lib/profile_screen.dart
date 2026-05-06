import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ProfileScreen extends StatefulWidget {
  final String? userId;
  final VoidCallback? onSetupComplete; // Added for setup flow

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

  int _followers = 0;
  int _following = 0;
  int _postsCount = 0;

  List<String> _posts = [];
  final _supabase = Supabase.instance.client;

  String get _targetUserId => widget.userId ?? _supabase.auth.currentUser!.id;
  bool get _isMyProfile => widget.userId == null || widget.userId == _supabase.auth.currentUser!.id;
  bool get _isSetupMode => widget.onSetupComplete != null;

  @override
  void initState() {
    super.initState();
    if (_isSetupMode) {
      _isEditing = true;
    }
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    setState(() => _isLoading = true);
    try {
      final profileData = await _supabase
          .from('profiles')
          .select()
          .eq('id', _targetUserId)
          .maybeSingle();

      if (profileData != null) {
        _nameController.text = profileData['full_name'] ?? '';
        // Special case: if it's 'usuario', clear it to force user to enter a real name
        if (_nameController.text.toLowerCase() == 'usuario') {
            _nameController.text = '';
        }
        
        _usernameController.text = profileData['username'] ?? '';
        _bioController.text = profileData['bio'] ?? '';
        _locationController.text = profileData['location'] ?? '';
        _websiteController.text = profileData['website'] ?? '';
        _avatarUrl = profileData['avatar_url'];
      }

      final response = await _supabase
          .from('pins')
          .select('image_url')
          .eq('user_id', _targetUserId)
          .order('created_at', ascending: false)
          .limit(9);

      if (mounted) {
        setState(() {
          _posts = (response as List).map((post) => post['image_url'] as String).toList();
          _postsCount = _posts.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAvatar() async {
    if (!_isMyProfile) return;

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

      // Save new avatar to profile
      await _supabase.from('profiles').upsert({
        'id': _targetUserId,
        'avatar_url': newAvatarUrl,
      });

      setState(() => _avatarUrl = newAvatarUrl);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating avatar: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.toLowerCase() == 'usuario') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa tu nombre completo'))
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // REMOVED 'username' from the map to prevent changes and mismatches
      await _supabase.from('profiles').upsert({
        'id': _targetUserId,
        'full_name': name,
        'bio': _bioController.text.trim(),
        'location': _locationController.text.trim(),
        'website': _websiteController.text.trim(),
      });

      if (mounted) {
        if (_isSetupMode) {
          widget.onSetupComplete!();
        } else {
          setState(() => _isEditing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Perfil guardado con éxito'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoField({required String label, required TextEditingController controller}) {
    if (!_isEditing && controller.text.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: !_isEditing,
          decoration: InputDecoration(
            filled: !_isEditing ? true : false,
            fillColor: _isEditing ? null : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          maxLines: label == 'Bio' ? 3 : 1,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Prevent going back if in setup mode
    Widget content = Scaffold(
      appBar: AppBar(
        title: Text(_isSetupMode ? 'Set up your profile' : (_isMyProfile ? 'My profile' : 'Profile')),
        backgroundColor: Colors.redAccent,
        // Hide leading back button if in setup mode
        automaticallyImplyLeading: !_isSetupMode,
        actions: [
          if (_isMyProfile)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _supabase.auth.signOut(),
              tooltip: 'Log Out',
            )
        ],
      ),
      body: _isLoading && _posts.isEmpty && !_isSetupMode
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isSetupMode)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20.0),
                        child: Text(
                          'Welcome! Let\'s start by setting up your profile.',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.redAccent),
                        ),
                      ),
                    Row(
                      children: [
                        // Avatar Section
                        GestureDetector(
                          onTap: _isEditing ? _updateAvatar : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 42,
                                backgroundColor: Colors.redAccent.shade100,
                                backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                                child: _avatarUrl == null 
                                    ? Text(
                                        _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : '?',
                                        style: const TextStyle(fontSize: 32, color: Colors.white),
                                      )
                                    : null,
                              ),
                              if (_isEditing)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
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
                                _nameController.text.isNotEmpty ? _nameController.text : 'Completa tu perfil',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _usernameController.text.isNotEmpty ? '@${_usernameController.text}' : '',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              if (_isMyProfile && !_isSetupMode)
                                ElevatedButton(
                                  onPressed: _isEditing ? _saveProfile : () => setState(() => _isEditing = true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  child: Text(_isEditing ? 'Save Profile' : 'Edit Profile', style: const TextStyle(color: Colors.white)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInfoField(label: 'Display Name *', controller: _nameController),
                    _buildInfoField(label: 'Bio', controller: _bioController),
                    _buildInfoField(label: 'Location', controller: _locationController),
                    _buildInfoField(label: 'Website', controller: _websiteController),
                    
                    if (_isSetupMode) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white) 
                            : const Text('Complete Registration', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                    if (!_isSetupMode) ...[
                        Text(_isMyProfile ? 'Your recent posts' : 'Recent posts', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (_posts.isEmpty)
                           Text(_isMyProfile ? 'You have not uploaded any posts.' : 'No posts available.', style: const TextStyle(color: Colors.grey))
                        else
                          GridView.count(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: _posts.map((postUrl) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(postUrl, fit: BoxFit.cover),
                              );
                            }).toList(),
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
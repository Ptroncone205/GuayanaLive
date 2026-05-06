import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  bool _isLoading = true;

  final TextEditingController _nameController = TextEditingController(text: 'Paulo Guayana');
  final TextEditingController _usernameController = TextEditingController(text: '@paulog');
  final TextEditingController _bioController = TextEditingController(text: 'Amante del diseño y las apps móviles. Compartiendo ideas, fotos y sueños.');
  final TextEditingController _locationController = TextEditingController(text: 'Guayana, Venezuela');
  final TextEditingController _websiteController = TextEditingController(text: 'www.guayanalive.com');

  int _followers = 2380;
  int _following = 182;
  int _postsCount = 0;

  List<String> _posts = [];
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchProfilePosts();
  }

  Future<void> _fetchProfilePosts() async {
    try {
      // Pulling the latest images to display in the profile grid
      final response = await _supabase
          .from('pins')
          .select('image_url')
          .order('created_at', ascending: false)
          .limit(9); // Limit to a 3x3 grid size

      setState(() {
        _posts = (response as List).map((post) => post['image_url'] as String).toList();
        _postsCount = _posts.length; 
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  void _saveProfile() {
    setState(() {
      _isEditing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil actualizado')), 
    );
  }

  Widget _buildStat(String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildInfoField({required String label, required TextEditingController controller}) {
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        backgroundColor: Colors.redAccent,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.redAccent.shade100,
                    child: const Text(
                      'P',
                      style: TextStyle(fontSize: 32, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _usernameController.text,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _isEditing ? _saveProfile : _toggleEditMode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          child: Text(_isEditing ? 'Guardar perfil' : 'Editar perfil'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Publicaciones', _postsCount),
                  _buildStat('Seguidores', _followers),
                  _buildStat('Seguidos', _following),
                ],
              ),
              const SizedBox(height: 24),
              _buildInfoField(label: 'Nombre', controller: _nameController),
              _buildInfoField(label: 'Usuario', controller: _usernameController),
              _buildInfoField(label: 'Biografía', controller: _bioController),
              _buildInfoField(label: 'Ubicación', controller: _locationController),
              _buildInfoField(label: 'Sitio web', controller: _websiteController),
              const SizedBox(height: 12),
              const Text('Publicaciones recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              if (_isLoading)
                 const Center(child: CircularProgressIndicator(color: Colors.redAccent))
              else if (_posts.isEmpty)
                 const Text('No has subido ninguna publicación todavía.', style: TextStyle(color: Colors.grey))
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
                      child: Image.network(
                        postUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 24),
              const Text('Resumen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.redAccent.shade100,
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: const Text(
                  'Perfil personalizable con publicaciones, seguidores, seguidos y datos de usuario. Cambia tu nombre, biografía, ubicación y sitio web para que se vea como una red social real.',
                  style: TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
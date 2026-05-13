import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'camera_screen.dart';
import 'services/groq_service.dart';

class ChatScreen extends StatefulWidget {
  /// If provided, this image will be pre-loaded as a pending attachment
  /// so the user can type a message before sending it to the AI.
  final String? initialImagePath;

  const ChatScreen({super.key, this.initialImagePath});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatMessage {
  final String sender;
  final String type;
  final String text;
  final String? imagePath;

  ChatMessage({
    required this.sender,
    required this.type,
    required this.text,
    this.imagePath,
  });
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final SupabaseClient _supabase = Supabase.instance.client;
  final GroqService _groqService = GroqService();

  bool _isLoading = false;
  String? _pendingImagePath;
  String? _userAvatarUrl;

  final List<ChatMessage> _messages = [
    ChatMessage(
      sender: 'ia',
      type: 'text',
      text:
          'Hola, soy la profesora Florencia, tu asistente IA de GuayanaLive. Puedes hacerme preguntas, o subir una imagen desde tu dispositivo para escanear alguna especie.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserAvatar();
    // Pre-load an image from the camera flow without auto-sending
    if (widget.initialImagePath != null) {
      _pendingImagePath = widget.initialImagePath;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void setPendingImage(String path) {
    setState(() {
      _pendingImagePath = path;
    });
  }

  void abrirCamaraDeseada() {
    _openCamera();
  }

  Future<void> _loadUserAvatar() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await _supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      final avatarUrl = profile?['avatar_url'] as String?;
      if (mounted && avatarUrl != null && avatarUrl.isNotEmpty) {
        setState(() {
          _userAvatarUrl = avatarUrl;
        });
      }
    } catch (_) {}
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _removePendingImage() {
    setState(() {
      _pendingImagePath = null;
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingImagePath == null) || _isLoading) return;

    final sendText = text.isNotEmpty ? text : 'Analiza esta imagen.';

    if (_pendingImagePath != null) {
      final imagePath = _pendingImagePath!;
      setState(() {
        _pendingImagePath = null;
      });
      _messageController.clear();
      _addMessage(
        ChatMessage(
          sender: 'user',
          type: 'image',
          text: sendText,
          imagePath: imagePath,
        ),
      );
      _sendAIResponse(sendText, imagePath: imagePath);
    } else {
      _messageController.clear();
      _addMessage(ChatMessage(sender: 'user', type: 'text', text: sendText));
      _sendAIResponse(sendText);
    }
  }

  Future<void> _sendAIResponse(String userText, {String? imagePath}) async {
    setState(() {
      _isLoading = true;
    });

    _addMessage(
      ChatMessage(sender: 'ia', type: 'text', text: 'Escribiendo...'),
    );

    try {
      Uint8List? imageBytes;

      if (imagePath != null) {
        imageBytes = await XFile(imagePath).readAsBytes();
      }
      final history = _messages
      .where((m) => m.text != 'Escribiendo...')
      .map((m) => {
            'role': m.sender == 'user' ? 'user' : 'assistant',
            'content': m.text,
          })
      .toList();
      // --- LLAMADA AL SERVICIO DE GROQ ---
      final aiReply = await _groqService.getChatResponse(
        userText,
        imageBytes: imageBytes,
        history: history,
      );

      if (!mounted) return;

      setState(() {
        final lastIndex = _messages.lastIndexWhere(
          (m) => m.sender == 'ia' && m.text == 'Escribiendo...',
        );
        if (lastIndex != -1) {
          _messages[lastIndex] = ChatMessage(
            sender: 'ia',
            type: 'text',
            text: aiReply,
          );
        } else {
          _addMessage(ChatMessage(sender: 'ia', type: 'text', text: aiReply));
        }
      });
    } catch (e) {
      if (!mounted) return;
      final errorMessage = 'Error al conectar con la IA: ${e.toString()}';
      setState(() {
        final lastIndex = _messages.lastIndexWhere(
          (m) => m.sender == 'ia' && m.text == 'Escribiendo...',
        );
        if (lastIndex != -1) {
          _messages[lastIndex] = ChatMessage(
            sender: 'ia',
            type: 'text',
            text: errorMessage,
          );
        } else {
          _addMessage(
            ChatMessage(sender: 'ia', type: 'text', text: errorMessage),
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showAttachmentOptions() async {
    return showModalBottomSheet<void>(
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
                title: Text('Adjuntar archivo'),
                subtitle: Text('Selecciona una imagen o abre la cámara'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Elegir desde dispositivo'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner, color: Colors.green),
                title: const Text('Abrir cámara'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _openCamera();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se seleccionó ninguna imagen.')),
        );
        return;
      }
      setState(() {
        _pendingImagePath = pickedFile.path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  Future<void> _openCamera() async {
    final result = await Navigator.of(context).push<CameraResult>(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pendingImagePath = result.imagePath;
    });
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.sender == 'user';
    final bubbleColor = isUser ? Colors.green.shade700 : Colors.grey.shade200;
    final textColor = isUser ? Colors.white : Colors.black87;

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? Colors.green.shade700 : Colors.green.shade900,
      backgroundImage:
          isUser && _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
          ? NetworkImage(_userAvatarUrl!) as ImageProvider
          : (!isUser ? const AssetImage('assets/ia_profile.png') : null),
      child:
          (isUser && (_userAvatarUrl == null || _userAvatarUrl!.isEmpty)) ||
              (!isUser && _userAvatarUrl == null)
          ? Icon(
              isUser ? Icons.person : Icons.auto_awesome,
              size: 16,
              color: Colors.white,
            )
          : null,
    );

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16.0),
      ),
      padding: const EdgeInsets.all(12.0),
      child: message.type == 'image'
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.imagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: kIsWeb
                        ? Image.network(message.imagePath!, fit: BoxFit.cover)
                        : Image.file(
                            File(message.imagePath!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(message.text, style: TextStyle(color: textColor)),
              ],
            )
          : Text(message.text, style: TextStyle(color: textColor)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[avatar, const SizedBox(width: 8)],
          bubble,
          if (isUser) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessage(_messages[index]);
              },
            ),
          ),
          if (_pendingImagePath != null)
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: kIsWeb
                        ? Image.network(
                            _pendingImagePath!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(_pendingImagePath!),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Imagen seleccionada. Escribe un mensaje para enviarla junto con la solicitud.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.green),
                    onPressed: _removePendingImage,
                  ),
                ],
              ),
            ),
          if (_isLoading)
            const LinearProgressIndicator(
              minHeight: 3,
              color: Colors.redAccent,
            ),
          const Divider(height: 1),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 8.0,
              vertical: 10.0,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.green),
                  onPressed: _isLoading ? null : _showAttachmentOptions,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    enabled: !_isLoading,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24.0)),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _isLoading
                      ? Colors.grey
                      : Colors.green.shade700,
                  child: IconButton(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

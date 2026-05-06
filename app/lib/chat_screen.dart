import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'camera_screen.dart';
import 'services/gemini_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
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

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final GeminiService _geminiService = GeminiService();
  bool _isLoading = false;
  final List<ChatMessage> _messages = [
    ChatMessage(
      sender: 'ia',
      type: 'text',
      text: 'Hola, soy tu asistente IA. Puedes escribir tu mensaje, subir una imagen desde tu dispositivo o abrir la cámara.',
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _messageController.clear();
    _addMessage(ChatMessage(sender: 'user', type: 'text', text: text));
    _sendAIResponse(text);
  }

  Future<void> _sendAIResponse(String userText, {String? imagePath}) async {
    setState(() {
      _isLoading = true;
    });

    _addMessage(ChatMessage(sender: 'ia', type: 'text', text: 'Escribiendo...'));

    try {
      final response = await _geminiService.getChatResponse(userText, imagePath: imagePath);
      if (!mounted) return;
      setState(() {
        final lastIndex = _messages.lastIndexWhere((m) => m.sender == 'ia' && m.text == 'Escribiendo...');
        if (lastIndex != -1) {
          _messages[lastIndex] = ChatMessage(sender: 'ia', type: 'text', text: response);
        } else {
          _addMessage(ChatMessage(sender: 'ia', type: 'text', text: response));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final lastIndex = _messages.lastIndexWhere((m) => m.sender == 'ia' && m.text == 'Escribiendo...');
        if (lastIndex != -1) {
          _messages[lastIndex] = ChatMessage(
            sender: 'ia',
            type: 'text',
            text: 'Ocurrió un error al conectar con la IA. Revisa tu clave de Gemini y tu conexión a internet.',
          );
        } else {
          _addMessage(ChatMessage(
            sender: 'ia',
            type: 'text',
            text: 'Ocurrió un error al conectar con la IA. Revisa tu clave de Gemini y tu conexión a internet.',
          ));
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
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir desde dispositivo'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
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
      _addMessage(ChatMessage(
        sender: 'user',
        type: 'image',
        text: 'Imagen adjuntada',
        imagePath: pickedFile.path,
      ));
      _sendAIResponse('Aquí tienes una imagen que adjunté. ¿Qué opinas?', imagePath: pickedFile.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  Future<void> _openCamera() async {
    final imagePath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );
    if (imagePath == null || !mounted) return;
    _addMessage(ChatMessage(
      sender: 'user',
      type: 'image',
      text: 'Foto tomada con la cámara',
      imagePath: imagePath,
    ));
    _sendAIResponse('Aquí tienes una foto que tomé con la cámara. ¿Qué te parece?', imagePath: imagePath);
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.sender == 'user';
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isUser ? Colors.redAccent : Colors.grey.shade200;
    final textColor = isUser ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
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
                              ? Image.network(
                                  message.imagePath!,
                                  fit: BoxFit.cover,
                                )
                              : Image.file(
                                  File(message.imagePath!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        message.text,
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  )
                : Text(
                    message.text,
                    style: TextStyle(color: textColor),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat IA'),
        backgroundColor: Colors.redAccent,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessage(_messages[index]);
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 3),
          const Divider(height: 1),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.redAccent),
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
                  backgroundColor: _isLoading ? Colors.grey : Colors.redAccent,
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

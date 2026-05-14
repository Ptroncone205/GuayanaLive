import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'camera_screen.dart';
import 'services/groq_service.dart';
import 'utils/video_preview_frames.dart';
import 'auth_modal.dart'; // Importación añadida para mostrar el modal
import 'translations.dart';

/// Adjunto listo para enviar a la IA (ruta local y/o bytes en web).
class _PendingAttachment {
  _PendingAttachment({
    required this.mimeType,
    this.path,
    this.bytes,
  }) : assert(path != null || bytes != null);

  final String? path;
  final Uint8List? bytes;
  final String mimeType;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');

  String get uiType {
    if (isImage) return 'image';
    if (isVideo) return 'video';
    if (isAudio) return 'audio';
    return 'text';
  }

  String get fileName {
  if (path != null && path!.isNotEmpty) {
    final normalized = path!.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  if (isImage) return 'image.jpg';
  if (isVideo) return 'video.mp4';
  if (isAudio) return 'audio.mp3';

  return 'file';
}

  Future<Uint8List> readBytes() async {
    if (bytes != null) return bytes!;
    return XFile(path!).readAsBytes();
  }
}

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
  final String? attachmentPath;
  final String? attachmentName;

  ChatMessage({
    required this.sender,
    required this.type,
    required this.text,
    this.attachmentPath,
    this.attachmentName,
  });
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final SupabaseClient _supabase = Supabase.instance.client;
  final GroqService _groqService = GroqService();

  bool _isLoading = false;
  _PendingAttachment? _pendingAttachment;
  String? _userAvatarUrl;

  // --- VARIABLES ESTÁTICAS PARA LÍMITES DE INVITADO ---
  // Estáticas para que el conteo no se borre si el usuario cambia de pestaña
  static int _guestTextCount = 0;
  static int _guestScanCount = 0;

  final List<ChatMessage> _messages = [];

  Widget _compactAttachmentPreview(
  ChatMessage message,
  Color textColor,
) {
  IconData icon;
  String label;

  switch (message.type) {
    case 'image':
      icon = Icons.image;
      label = 'Image';
      break;

    case 'video':
      icon = Icons.videocam;
      label = 'Video';
      break;

    case 'audio':
      icon = Icons.audiotrack;
      label = 'Audio';
      break;

    default:
      icon = Icons.insert_drive_file;
      label = 'File';
  }

  final bool canPreviewImage =
      message.type == 'image' &&
      message.attachmentPath != null;

  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        // Thumbnail or icon
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: canPreviewImage
              ? (kIsWeb
                    ? Image.network(
                        message.attachmentPath!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(message.attachmentPath!),
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ))
              : Container(
                  width: 52,
                  height: 52,
                  color: Colors.black.withOpacity(0.08),
                  child: Icon(
                    icon,
                    color: textColor,
                    size: 28,
                  ),
                ),
        ),

        const SizedBox(width: 12),

        // File info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.attachmentName ?? 'file',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty) {
      _messages.add(
        ChatMessage(
          sender: 'ia',
          type: 'text',
          text: Translations.text(context, 'ai_welcome_message'),
        ),
      );
    } else if (_messages[0].sender == 'ia' && _messages.length == 1) {
      _messages[0] = ChatMessage(
        sender: 'ia',
        type: 'text',
        text: Translations.text(context, 'ai_welcome_message'),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserAvatar();
    if (widget.initialImagePath != null) {
      final p = widget.initialImagePath!;
      _pendingAttachment = _PendingAttachment(
        path: p,
        mimeType: lookupMimeType(p) ?? 'image/jpeg',
      );
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
      _pendingAttachment = _PendingAttachment(
        path: path,
        mimeType: lookupMimeType(path) ?? 'image/jpeg',
      );
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

  void _removePendingAttachment() {
    setState(() {
      _pendingAttachment = null;
    });
  }

  String _defaultPromptForPending(_PendingAttachment p) {
    if (p.isImage) return 'Analiza esta imagen.';
    if (p.isVideo) return 'Analiza este video.';
    if (p.isAudio) return 'Analiza este audio.';
    return 'Analiza este archivo.';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingAttachment == null) || _isLoading) return;

    final bool isGuest = _supabase.auth.currentUser == null;
    if (isGuest) {
      if (_pendingAttachment != null) {
        if (!_pendingAttachment!.isImage) {
          showAuthModal(context);
          return;
        }
        if (_guestScanCount >= 1) {
          showAuthModal(context);
          return;
        }
        _guestScanCount++;
      } else {
        if (_guestTextCount >= 3) {
          showAuthModal(context);
          return;
        }
        _guestTextCount++;
      }
    }

    final pending = _pendingAttachment;
    final sendText = text.isNotEmpty
        ? text
        : (pending != null ? _defaultPromptForPending(pending) : text);

    if (pending != null) {
      setState(() {
        _pendingAttachment = null;
      });
      _messageController.clear();
      _addMessage(
        ChatMessage(
          sender: 'user',
          type: pending.uiType,
          text: sendText,
          attachmentPath: pending.path,
          attachmentName: pending.fileName,
        ),
      );
      _sendAIResponse(sendText, pending: pending);
    } else {
      _messageController.clear();
      _addMessage(ChatMessage(sender: 'user', type: 'text', text: sendText));
      _sendAIResponse(sendText);
    }
  }

  Future<void> _sendAIResponse(
    String userText, {
    _PendingAttachment? pending,
  }) async {
    setState(() {
      _isLoading = true;
    });

    _addMessage(
      ChatMessage(sender: 'ia', type: 'text', text: Translations.text(context, 'typing')),
    );

    try {
      Uint8List? mediaBytes;
      String? mediaMime;
      List<Uint8List> videoFrames = const [];

      if (pending != null) {
        mediaBytes = await pending.readBytes();
        mediaMime = pending.mimeType;
        if (pending.isVideo) {
          videoFrames = await VideoPreviewFrames.extractForAttachment(
            path: pending.path,
            bytes: pending.bytes,
            mimeType: pending.mimeType,
          );
        }
      }

      Uint8List? uploadBytes = mediaBytes;
      if (pending != null &&
          pending.isVideo &&
          mediaBytes != null &&
          mediaBytes.length > GroqService.maxVideoBytesForWhisper) {
        if (videoFrames.length >= 2) {
          uploadBytes = null;
        } else {
          if (!mounted) return;
          setState(() {
              final lastIndex = _messages.lastIndexWhere(
                (m) => m.sender == 'ia' && m.text == Translations.text(context, 'typing'),
              );
              if (lastIndex != -1) {
                _messages[lastIndex] = ChatMessage(
                  sender: 'ia',
                  type: 'text',
                  text: Translations.text(context, 'video_too_large'),
                );
              }
          });
          return;
        }
      }

      final history = _messages
          .where((m) => m.text != Translations.text(context, 'typing'))
          .map(
            (m) => {
              'role': m.sender == 'user' ? 'user' : 'assistant',
              'content': m.text,
            },
          )
          .toList();
      final aiReply = await _groqService.getChatResponse(
        userText,
        mediaBytes: uploadBytes,
        mediaMimeType: mediaMime,
        mediaKind: pending?.uiType,
        videoPreviewJpegFrames: videoFrames.isEmpty ? null : videoFrames,
        history: history,
      );

      if (!mounted) return;

      setState(() {
        final lastIndex = _messages.lastIndexWhere(
          (m) => m.sender == 'ia' && m.text == Translations.text(context, 'typing'),
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
      final errorMessage = '${Translations.text(context, 'error_connecting_ai')}: ${e.toString()}';
      setState(() {
        final lastIndex = _messages.lastIndexWhere(
          (m) => m.sender == 'ia' && m.text == Translations.text(context, 'typing'),
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
    final bool isGuest = _supabase.auth.currentUser == null;

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
              ListTile(
                title: Text(Translations.text(context, 'attach_file')),
                subtitle: Text(
                  isGuest
                      ? Translations.text(context, 'guest_attachment_limit')
                      : Translations.text(context, 'image_video_audio'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: Text(Translations.text(context, 'choose_image')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickImage(ImageSource.gallery);
                },
              ),
              if (!isGuest) ...[
                ListTile(
                  leading: const Icon(Icons.video_library, color: Colors.green),
                  title: Text(Translations.text(context, 'choose_video')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickVideo();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.audio_file, color: Colors.green),
                  title: Text(Translations.text(context, 'choose_audio')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickAudio();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.qr_code_scanner, color: Colors.green),
                title: Text(Translations.text(context, 'open_camera')),
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
          SnackBar(content: Text(Translations.text(context, 'no_image_selected'))),
        );
        return;
      }
      final mime = lookupMimeType(pickedFile.path) ?? 'image/jpeg';
      setState(() {
        _pendingAttachment = _PendingAttachment(path: pickedFile.path, mimeType: mime);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${Translations.text(context, 'error_selecting_image')}: $e')),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (!mounted) return;
      if (picked == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.text(context, 'no_video_selected'))),
        );
        return;
      }
      final mime = lookupMimeType(picked.path) ?? 'video/mp4';
      setState(() {
        _pendingAttachment = _PendingAttachment(path: picked.path, mimeType: mime);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${Translations.text(context, 'error_selecting_video')}: $e')),
      );
    }
  }

  String _mimeFromAudioExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'webm':
        return 'audio/webm';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';
      default:
        return 'audio/mpeg';
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'm4a',
          'wav',
          'ogg',
          'webm',
          'flac',
          'mpeg',
          'mpga',
          'aac',
        ],
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.path != null && f.path!.isNotEmpty) {
        final mime = lookupMimeType(f.path!) ?? _mimeFromAudioExtension(f.extension);
        setState(() {
          _pendingAttachment = _PendingAttachment(path: f.path, mimeType: mime);
        });
      } else if (f.bytes != null) {
        final mime = _mimeFromAudioExtension(f.extension);
        setState(() {
          _pendingAttachment = _PendingAttachment(bytes: f.bytes, mimeType: mime);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${Translations.text(context, 'error_selecting_audio')}: $e')),
      );
    }
  }

  Future<void> _openCamera() async {
    final result = await Navigator.of(context).push<CameraResult>(
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );
    if (result == null || !mounted) return;
    final mime = lookupMimeType(result.imagePath) ?? 'image/jpeg';
    setState(() {
      _pendingAttachment = _PendingAttachment(
        path: result.imagePath,
        mimeType: mime,
      );
    });
  }


  Widget _buildMessage(ChatMessage message) {
    final isUser = message.sender == 'user';
    final bubbleColor = isUser ? Colors.green.shade700 : Colors.grey.shade200;
    final textColor = isUser ? Colors.white : Colors.black87;

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? Colors.green.shade700 : Colors.green.shade900,

      backgroundImage: isUser
          ? (_userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                ? NetworkImage(_userAvatarUrl!)
                : null)
          : const AssetImage('assets/ia_profile.png'),

      child: isUser && (_userAvatarUrl == null || _userAvatarUrl!.isEmpty)
          ? const Icon(Icons.person, size: 16, color: Colors.white)
          : null,
    );

    final bool hasMedia =
        message.type == 'image' ||
        message.type == 'video' ||
        message.type == 'audio';

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16.0),
      ),
      padding: const EdgeInsets.all(12.0),
      child: hasMedia
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _compactAttachmentPreview(message, textColor),

                if (message.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(message.text, style: TextStyle(color: textColor)),
                ],
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

  Widget _pendingPreviewRow() {
    final p = _pendingAttachment!;
    Widget thumb;
    String label;
    if (p.isImage && p.path != null) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: kIsWeb
            ? Image.network(p.path!, width: 64, height: 64, fit: BoxFit.cover)
            : Image.file(
                File(p.path!),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
      );
      label = Translations.text(context, 'image_selected_prompt');
    } else if (p.isVideo) {
      thumb = const Icon(Icons.videocam, size: 48, color: Colors.green);
      label = Translations.text(context, 'video_selected_prompt');
    } else {
      thumb = const Icon(Icons.audiotrack, size: 48, color: Colors.green);
      label = Translations.text(context, 'audio_selected_prompt');
    }

    return Row(
      children: [
        SizedBox(width: 64, height: 64, child: Center(child: thumb)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.green),
          onPressed: _removePendingAttachment,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.text(context, 'virtual_assistant')),
      ),
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
          if (_pendingAttachment != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _pendingPreviewRow(),
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
                    decoration: InputDecoration(
                      hintText: Translations.text(context, 'type_a_message'),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24.0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
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

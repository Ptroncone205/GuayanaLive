import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'translations.dart';

class ChatPartner {
  final String id;
  final String name;
  final String? avatarUrl;

  ChatPartner({required this.id, required this.name, this.avatarUrl});
}

class ChatThread {
  final String id;
  final ChatPartner partner;
  final String lastMessage;
  final DateTime updatedAt;

  ChatThread({
    required this.id,
    required this.partner,
    required this.lastMessage,
    required this.updatedAt,
  });
}

class UserChatScreen extends StatefulWidget {
  const UserChatScreen({super.key});

  @override
  State<UserChatScreen> createState() => _UserChatScreenState();
}

class _UserChatScreenState extends State<UserChatScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentUserId;
  bool _isLoading = true;
  List<ChatPartner> _contacts = [];
  List<ChatThread> _threads = [];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentUserId = null;
        });
      }
      return;
    }

    _currentUserId = user.id;
    await _refreshChatData();
  }

  Future<void> _refreshChatData() async {
    if (_currentUserId == null) return;
    final currentUserId = _currentUserId!;

    setState(() => _isLoading = true);
    try {
      // 1. Obtener contactos directos y personas que sigues
      final contactsRes = await _supabase.from('contacts').select('''
        user_id_1, user_id_2
      ''').or('user_id_1.eq.$currentUserId,user_id_2.eq.$currentUserId');

      final Set<String> contactIdSet = {};
      for (var row in contactsRes as List<dynamic>) {
        final u1 = row['user_id_1'] as String;
        final u2 = row['user_id_2'] as String;
        contactIdSet.add(u1 == currentUserId ? u2 : u1);
      }

      final followRes = await _supabase.from('follows').select('followee_id').eq('follower_id', currentUserId);
      for (var row in followRes as List<dynamic>) {
        final followeeId = row['followee_id'] as String?;
        if (followeeId != null) {
          contactIdSet.add(followeeId);
        }
      }

      final contactIds = contactIdSet.toList();
      List<ChatPartner> loadedContacts = [];
      if (contactIds.isNotEmpty) {
        final profilesRes = await _supabase
            .from('profiles')
            .select('id, username, full_name, avatar_url')
            .inFilter('id', contactIds);
        
        loadedContacts = (profilesRes as List<dynamic>).map((p) {
          return ChatPartner(
            id: p['id'],
            name: p['username'] ?? p['full_name'] ?? 'Usuario',
            avatarUrl: p['avatar_url'],
          );
        }).toList();
      }

      // 2. Obtener hilos de chat activos
      final threadsRes = await _supabase.from('chat_threads').select('''
        id, user1_id, user2_id, last_message, updated_at
      ''').or('user1_id.eq.$currentUserId,user2_id.eq.$currentUserId')
        .order('updated_at', ascending: false);

      List<ChatThread> loadedThreads = [];
      for (var row in threadsRes as List<dynamic>) {
        final u1 = row['user1_id'] as String;
        final u2 = row['user2_id'] as String;
        final partnerId = u1 == currentUserId ? u2 : u1;
        
        // Buscar info del perfil (si es contacto lo tomamos de ahí, si no hacemos query)
        ChatPartner? partner;
        try {
          partner = loadedContacts.firstWhere((c) => c.id == partnerId);
        } catch (_) {
          partner = null;
        }
        if (partner == null) {
          final pRes = await _supabase.from('profiles').select('id, username, full_name, avatar_url').eq('id', partnerId).maybeSingle();
          if (pRes != null) {
            partner = ChatPartner(
              id: pRes['id'],
              name: pRes['username'] ?? pRes['full_name'] ?? 'Usuario',
              avatarUrl: pRes['avatar_url'],
            );
          } else {
            partner = ChatPartner(id: partnerId, name: 'Usuario Desconocido');
          }
        }

        loadedThreads.add(ChatThread(
          id: row['id'],
          partner: partner,
          lastMessage: row['last_message'] ?? '',
          updatedAt: DateTime.parse(row['updated_at']),
        ));
      }

      if (mounted) {
        setState(() {
          _contacts = loadedContacts;
          _threads = loadedThreads;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading chats: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openThread(ChatPartner partner) async {
    if (_currentUserId == null) return;
    final currentUserId = _currentUserId!;
    
    // Verificar si ya existe el hilo
    final existingThread = await _supabase.from('chat_threads')
        .select('id')
        .or('and(user1_id.eq.$currentUserId,user2_id.eq.${partner.id}),and(user1_id.eq.${partner.id},user2_id.eq.$currentUserId)')
        .maybeSingle();

    String threadId;
    if (existingThread != null) {
      threadId = existingThread['id'];
    } else {
      // Crear nuevo hilo
      final insertRes = await _supabase.from('chat_threads').insert({
        'user1_id': currentUserId,
        'user2_id': partner.id,
        'last_message': Translations.text(context, 'chat_started'),
      }).select('id').single();
      threadId = insertRes['id'];
    }

    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => UserChatThreadScreen(
        threadId: threadId,
        currentUserId: _currentUserId!,
        partner: partner,
      ),
    ));
    await _refreshChatData(); // Refrescar al volver
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.text(context, 'chat_between_users')),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _currentUserId != null ? _refreshChatData : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUserId == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          Translations.text(context, 'login_required_chat'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: Colors.green.shade50,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 0 ? Colors.green.shade700 : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  Translations.text(context, 'conversations'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedTab == 0 ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 1 ? Colors.green.shade700 : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  Translations.text(context, 'contacts'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedTab == 1 ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _selectedTab == 0 ? _buildThreadsList() : _buildContactsList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildThreadsList() {
    if (_threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '${Translations.text(context, 'no_conversations_yet')}\n${Translations.text(context, 'select_contact_to_start_chat')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _threads.length,
      separatorBuilder: (context, index) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final thread = _threads[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade200,
            backgroundImage: thread.partner.avatarUrl != null ? NetworkImage(thread.partner.avatarUrl!) : null,
            child: thread.partner.avatarUrl == null ? Text(thread.partner.name.substring(0, 1).toUpperCase()) : null,
          ),
          title: Text(thread.partner.name),
          subtitle: Text(thread.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(
            _formatTime(thread.updatedAt),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          onTap: () => _openThread(thread.partner),
        );
      },
    );
  }

  Widget _buildContactsList() {
    if (_contacts.isEmpty) {
      return Center(child: Text(Translations.text(context, 'no_contacts_yet'), style: const TextStyle(color: Colors.black54)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _contacts.length,
      separatorBuilder: (context, index) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final partner = _contacts[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade200,
            backgroundImage: partner.avatarUrl != null ? NetworkImage(partner.avatarUrl!) : null,
            child: partner.avatarUrl == null ? Text(partner.name.substring(0, 1).toUpperCase()) : null,
          ),
          title: Text(partner.name),
          subtitle: Text(Translations.text(context, 'start_chat_with', {'name': partner.name})),
          onTap: () => _openThread(partner),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    final now = DateTime.now();
    if (now.difference(localTime).inDays >= 1) {
      return '${localTime.day}/${localTime.month}/${localTime.year}';
    }
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }
}

class UserChatThreadScreen extends StatefulWidget {
  final String threadId;
  final ChatPartner partner;
  final String currentUserId;

  const UserChatThreadScreen({
    super.key,
    required this.threadId,
    required this.partner,
    required this.currentUserId,
  });

  @override
  State<UserChatThreadScreen> createState() => _UserChatThreadScreenState();
}

class _UserChatThreadScreenState extends State<UserChatThreadScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  
  bool _isSending = false;

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    
    try {
      // Insertar el mensaje
      await _supabase.from('chat_messages').insert({
        'thread_id': widget.threadId,
        'sender_id': widget.currentUserId,
        'text': text,
      });

      // Actualizar el hilo con el último mensaje
      await _supabase.from('chat_threads').update({
        'last_message': text,
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', widget.threadId);

      _messageController.clear();
    } catch (e) {
      debugPrint('Error enviando mensaje: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green.shade200,
              backgroundImage: widget.partner.avatarUrl != null ? NetworkImage(widget.partner.avatarUrl!) : null,
              child: widget.partner.avatarUrl == null ? Text(widget.partner.name.substring(0, 1).toUpperCase()) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.partner.name)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
      ),
      body: Column(
        children: [
          Expanded(
            // StreamBuilder obtiene y actualiza los mensajes mágicamente en tiempo real
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('chat_messages')
                  .stream(primaryKey: ['id'])
                  .eq('thread_id', widget.threadId)
                  .order('created_at', ascending: true),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(Translations.text(context, 'no_messages_yet', {'name': widget.partner.name}), style: const TextStyle(color: Colors.black54)),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message['sender_id'] == widget.currentUserId;
                    final createdAt = DateTime.parse(message['created_at']).toLocal();

                    return Align(
                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMine ? Colors.green.shade700 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['text'],
                              style: TextStyle(color: isMine ? Colors.white : Colors.black87),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: isMine ? Colors.white70 : Colors.black54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: Translations.text(context, 'type_a_message'),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: _isSending ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, color: Colors.green),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
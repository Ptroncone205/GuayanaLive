import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/like_chat_repository.dart';

class UserChatScreen extends StatefulWidget {
  const UserChatScreen({super.key});

  @override
  State<UserChatScreen> createState() => _UserChatScreenState();
}

class _UserChatScreenState extends State<UserChatScreen> {
  final ChatRepository _repository = InMemoryChatRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentUserId;
  bool _isLoading = true;
  List<ChatPartner> _partners = [];
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

    setState(() => _isLoading = true);
    try {
      final partners = await _repository.fetchAvailablePartners(_currentUserId!);
      final threads = await _repository.fetchThreads(_currentUserId!);
      if (mounted) {
        setState(() {
          _partners = partners;
          _threads = threads;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openThread(ChatPartner partner) async {
    if (_currentUserId == null) return;
    final navigator = Navigator.of(context);
    final thread = await _repository.openThread(_currentUserId!, partner.id);
    await navigator.push(MaterialPageRoute(
      builder: (context) => UserChatThreadScreen(
        repository: _repository,
        thread: thread,
        currentUserId: _currentUserId!,
        partner: partner,
      ),
    ));
    await _refreshChatData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat entre usuarios'),
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
                      children: const [
                        Icon(Icons.lock, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Debes iniciar sesión para usar el chat entre usuarios.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.black54),
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
                                  'Conversaciones',
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
                                  'Contactos',
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
            children: const [
              Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Aún no tienes conversaciones.\nSelecciona un contacto para iniciar un chat.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
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
        final partnerId = thread.participantIds.firstWhere((id) => id != _currentUserId, orElse: () => '');
        final partner = _partners.firstWhere(
          (element) => element.id == partnerId,
          orElse: () => ChatPartner(id: partnerId, name: partnerId),
        );

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade200,
            child: Text(partner.name.substring(0, 1).toUpperCase()),
          ),
          title: Text(partner.name),
          subtitle: Text(thread.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(
            _formatTime(thread.updatedAt),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          onTap: () => _openThread(partner),
        );
      },
    );
  }

  Widget _buildContactsList() {
    if (_partners.isEmpty) {
      return const Center(child: Text('No hay contactos disponibles.', style: TextStyle(color: Colors.black54)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _partners.length,
      separatorBuilder: (context, index) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final partner = _partners[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade200,
            child: Text(partner.name.substring(0, 1).toUpperCase()),
          ),
          title: Text(partner.name),
          subtitle: Text('Inicia una conversación con ${partner.name}'),
          onTap: () => _openThread(partner),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (now.difference(time).inDays >= 1) {
      return '${time.day}/${time.month}/${time.year}';
    }
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class UserChatThreadScreen extends StatefulWidget {
  final ChatRepository repository;
  final ChatThread thread;
  final ChatPartner partner;
  final String currentUserId;

  const UserChatThreadScreen({
    super.key,
    required this.repository,
    required this.thread,
    required this.partner,
    required this.currentUserId,
  });

  @override
  State<UserChatThreadScreen> createState() => _UserChatThreadScreenState();
}

class _UserChatThreadScreenState extends State<UserChatThreadScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSending = false;
  List<ChatMessageModel> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages = await widget.repository.fetchMessages(widget.thread.id);
    if (mounted) {
      setState(() => _messages = messages);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final message = ChatMessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      threadId: widget.thread.id,
      senderId: widget.currentUserId,
      text: text,
      createdAt: DateTime.now(),
    );

    try {
      await widget.repository.sendMessage(widget.thread.id, message);
      _messageController.clear();
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.green.shade200,
              child: Text(widget.partner.name.substring(0, 1).toUpperCase()),
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
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('No hay mensajes aún. Envía el primero a ${widget.partner.name}.', style: const TextStyle(color: Colors.black54)),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMine = message.senderId == widget.currentUserId;
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
                                message.text,
                                style: TextStyle(color: isMine ? Colors.white : Colors.black87),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
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
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
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

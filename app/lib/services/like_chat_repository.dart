import 'package:supabase_flutter/supabase_flutter.dart';

class LikeState {
  final bool isLiked;
  final int likesCount;

  LikeState({required this.isLiked, required this.likesCount});
}

abstract class LikeRepository {
  Future<LikeState> fetchLikeState(dynamic pinId, String? userId, {int defaultLikes = 0});
  Future<LikeState> toggleLike(dynamic pinId, String userId, {int defaultLikes = 0});
}

abstract class ChatRepository {
  Future<List<ChatPartner>> fetchAvailablePartners(String currentUserId);
  Future<List<ChatThread>> fetchThreads(String currentUserId);
  Future<ChatThread> openThread(String currentUserId, String partnerId);
  Future<List<ChatMessageModel>> fetchMessages(String threadId);
  Future<ChatMessageModel> sendMessage(String threadId, ChatMessageModel message);
}

class ChatPartner {
  final String id;
  final String name;
  final String? avatarUrl;

  ChatPartner({required this.id, required this.name, this.avatarUrl});
}

class ChatThread {
  final String id;
  final String title;
  final String lastMessage;
  final DateTime updatedAt;
  final List<String> participantIds;

  ChatThread({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.updatedAt,
    required this.participantIds,
  });
}

class ChatMessageModel {
  final String id;
  final String threadId;
  final String senderId;
  final String text;
  final DateTime createdAt;

  ChatMessageModel({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });
}

class InMemoryLikeRepository implements LikeRepository {
  final Map<String, int> _likesCount = {};
  final Map<String, Set<String>> _likesByPin = {};

  String _normalize(dynamic pinId) => pinId?.toString() ?? '';

  @override
  Future<LikeState> fetchLikeState(dynamic pinId, String? userId, {int defaultLikes = 0}) async {
    final normalizedId = _normalize(pinId);
    final count = _likesCount[normalizedId] ?? defaultLikes;
    final liked = userId != null && _likesByPin[normalizedId]?.contains(userId) == true;
    return LikeState(isLiked: liked, likesCount: count);
  }

  @override
  Future<LikeState> toggleLike(dynamic pinId, String userId, {int defaultLikes = 0}) async {
    final normalizedId = _normalize(pinId);
    final currentLikes = _likesCount[normalizedId] ?? defaultLikes;
    final likedUsers = _likesByPin.putIfAbsent(normalizedId, () => <String>{});
    final isLiked = likedUsers.contains(userId);

    if (isLiked) {
      likedUsers.remove(userId);
      _likesCount[normalizedId] = (currentLikes - 1).clamp(0, double.infinity).toInt();
      return LikeState(isLiked: false, likesCount: _likesCount[normalizedId]!);
    }

    likedUsers.add(userId);
    _likesCount[normalizedId] = currentLikes + 1;
    return LikeState(isLiked: true, likesCount: _likesCount[normalizedId]!);
  }
}

class SupabaseLikeRepository implements LikeRepository {
  final SupabaseClient client;

  SupabaseLikeRepository({required this.client});

  @override
  Future<LikeState> fetchLikeState(dynamic pinId, String? userId, {int defaultLikes = 0}) async {
    bool liked = false;
    int likesCount = defaultLikes;

    try {
      if (userId != null) {
        final row = await client
            .from('pin_likes')
            .select('id')
            .eq('pin_id', pinId)
            .eq('user_id', userId)
            .maybeSingle();
        liked = row != null;
      }
    } catch (_) {
      // Ignorar si la tabla no existe o no se puede consultar.
    }

    try {
      final pinRow = await client
          .from('pins')
          .select('likes_count')
          .eq('id', pinId)
          .maybeSingle();

      if (pinRow != null && pinRow['likes_count'] != null) {
        likesCount = pinRow['likes_count'] as int;
      }
    } catch (_) {
      // Si no hay campo likes_count, mantenemos el valor por defecto.
    }

    return LikeState(isLiked: liked, likesCount: likesCount);
  }

  @override
  Future<LikeState> toggleLike(dynamic pinId, String userId, {int defaultLikes = 0}) async {
    bool currentlyLiked = false;
    int likesCount = defaultLikes;

    try {
      final row = await client
          .from('pin_likes')
          .select('id')
          .eq('pin_id', pinId)
          .eq('user_id', userId)
          .maybeSingle();
      currentlyLiked = row != null;
    } catch (_) {
      currentlyLiked = false;
    }

    if (currentlyLiked) {
      try {
        await client.from('pin_likes').delete().eq('pin_id', pinId).eq('user_id', userId);
      } catch (_) {}
      likesCount = (defaultLikes - 1).clamp(0, double.infinity).toInt();
      try {
        final updated = await client
            .from('pins')
            .update({'likes_count': likesCount})
            .eq('id', pinId)
            .select('likes_count')
            .maybeSingle();
        if (updated != null && updated['likes_count'] != null) {
          likesCount = updated['likes_count'] as int;
        }
      } catch (_) {}
      return LikeState(isLiked: false, likesCount: likesCount);
    }

    try {
      await client.from('pin_likes').insert({'pin_id': pinId, 'user_id': userId});
      likesCount = defaultLikes + 1;
      await client.from('pins').update({'likes_count': likesCount}).eq('id', pinId);
    } catch (_) {
      likesCount = defaultLikes + 1;
    }

    return LikeState(isLiked: true, likesCount: likesCount);
  }
}

class InMemoryChatRepository implements ChatRepository {
  final Map<String, ChatPartner> _partners = {
    'user_2': ChatPartner(id: 'user_2', name: 'Doña Isabel', avatarUrl: null),
    'user_3': ChatPartner(id: 'user_3', name: 'Luis Antonio', avatarUrl: null),
    'user_4': ChatPartner(id: 'user_4', name: 'María Fernanda', avatarUrl: null),
  };

  final Map<String, ChatThread> _threads = {};
  final Map<String, List<ChatMessageModel>> _messages = {};

  @override
  Future<List<ChatPartner>> fetchAvailablePartners(String currentUserId) async {
    if (!_partners.containsKey(currentUserId)) {
      _partners[currentUserId] = ChatPartner(id: currentUserId, name: 'Tú', avatarUrl: null);
    }

    return _partners.values
        .where((partner) => partner.id != currentUserId)
        .toList();
  }

  @override
  Future<List<ChatThread>> fetchThreads(String currentUserId) async {
    return _threads.values
        .where((thread) => thread.participantIds.contains(currentUserId))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  String _buildThreadId(String a, String b) {
    final sorted = [a, b]..sort();
    return sorted.join('_');
  }

  @override
  Future<ChatThread> openThread(String currentUserId, String partnerId) async {
    final threadId = _buildThreadId(currentUserId, partnerId);
    final existing = _threads[threadId];
    if (existing != null) {
      return existing;
    }

    final partner = _partners[partnerId] ?? ChatPartner(id: partnerId, name: 'Usuario desconocido', avatarUrl: null);
    final newThread = ChatThread(
      id: threadId,
      title: partner.name,
      lastMessage: 'Comienza una conversación con ${partner.name}.',
      updatedAt: DateTime.now(),
      participantIds: [currentUserId, partnerId],
    );

    _threads[threadId] = newThread;
    _messages[threadId] = [];

    return newThread;
  }

  @override
  Future<List<ChatMessageModel>> fetchMessages(String threadId) async {
    return List<ChatMessageModel>.from(_messages[threadId] ?? []);
  }

  @override
  Future<ChatMessageModel> sendMessage(String threadId, ChatMessageModel message) async {
    final existing = _threads[threadId];
    if (existing != null) {
      final newMessages = _messages.putIfAbsent(threadId, () => []);
      newMessages.add(message);
      _threads[threadId] = ChatThread(
        id: existing.id,
        title: existing.title,
        lastMessage: message.text,
        updatedAt: message.createdAt,
        participantIds: existing.participantIds,
      );
    }
    return message;
  }
}

class SupabaseChatRepository implements ChatRepository {
  final SupabaseClient client;

  SupabaseChatRepository({required this.client});

  @override
  Future<List<ChatPartner>> fetchAvailablePartners(String currentUserId) async {
    try {
      final profiles = await client
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .neq('id', currentUserId);

      final rows = List<Map<String, dynamic>>.from(profiles as List);
      return rows.map((row) {
        final name = (row['full_name'] as String?)?.trim().isNotEmpty == true
            ? row['full_name'] as String
            : row['username'] as String? ?? 'Usuario';
        return ChatPartner(
          id: row['id'] as String,
          name: name,
          avatarUrl: row['avatar_url'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ChatThread>> fetchThreads(String currentUserId) async {
    try {
      final threads = await client
          .from('chat_thread_participants')
          .select('thread_id, chat_threads(last_message, updated_at, title, participant_ids)')
          .eq('user_id', currentUserId);

      final rows = List<Map<String, dynamic>>.from(threads as List);

      return rows.map((row) {
        final thread = row['chat_threads'] as Map<String, dynamic>?;
        if (thread == null) {
          throw Exception('Formato de hilo inválido');
        }

        return ChatThread(
          id: row['thread_id'] as String,
          title: thread['title'] as String? ?? 'Chat',
          lastMessage: thread['last_message'] as String? ?? '',
          updatedAt: DateTime.parse(thread['updated_at'] as String),
          participantIds: List<String>.from(thread['participant_ids'] as List<dynamic>),
        );
      }).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ChatThread> openThread(String currentUserId, String partnerId) async {
    try {
      final existing = await client
          .from('chat_thread_participants')
          .select('thread_id')
          .inFilter('thread_id', [_buildThreadId(currentUserId, partnerId)])
          .maybeSingle();

      final threadId = _buildThreadId(currentUserId, partnerId);
      if (existing != null) {
        final messages = await fetchMessages(threadId);
        final title = partnerId;
        return ChatThread(
          id: threadId,
          title: title,
          lastMessage: messages.isNotEmpty ? messages.last.text : 'Comienza una conversación',
          updatedAt: messages.isNotEmpty ? messages.last.createdAt : DateTime.now(),
          participantIds: [currentUserId, partnerId],
        );
      }

      await client.from('chat_threads').insert({
        'id': threadId,
        'title': 'Chat privado',
        'last_message': '',
        'updated_at': DateTime.now().toIso8601String(),
        'participant_ids': [currentUserId, partnerId],
      });

      await client.from('chat_thread_participants').insert([
        {'thread_id': threadId, 'user_id': currentUserId},
        {'thread_id': threadId, 'user_id': partnerId},
      ]);

      return ChatThread(
        id: threadId,
        title: 'Chat privado',
        lastMessage: '',
        updatedAt: DateTime.now(),
        participantIds: [currentUserId, partnerId],
      );
    } catch (_) {
      return ChatThread(
        id: _buildThreadId(currentUserId, partnerId),
        title: partnerId,
        lastMessage: 'Chat privado',
        updatedAt: DateTime.now(),
        participantIds: [currentUserId, partnerId],
      );
    }
  }

  @override
  Future<List<ChatMessageModel>> fetchMessages(String threadId) async {
    try {
      final response = await client
          .from('chat_messages')
          .select('id, thread_id, sender_id, text, created_at')
          .eq('thread_id', threadId)
          .order('created_at', ascending: true);

      final rows = List<Map<String, dynamic>>.from(response as List);
      return rows.map((row) => ChatMessageModel(
            id: row['id'].toString(),
            threadId: row['thread_id'] as String,
            senderId: row['sender_id'] as String,
            text: row['text'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ChatMessageModel> sendMessage(String threadId, ChatMessageModel message) async {
    try {
      await client.from('chat_messages').insert({
        'id': message.id,
        'thread_id': threadId,
        'sender_id': message.senderId,
        'text': message.text,
        'created_at': message.createdAt.toIso8601String(),
      });
      await client.from('chat_threads').update({
        'last_message': message.text,
        'updated_at': message.createdAt.toIso8601String(),
      }).eq('id', threadId);
    } catch (_) {}
    return message;
  }

  String _buildThreadId(String a, String b) {
    final sorted = [a, b]..sort();
    return sorted.join('_');
  }
}

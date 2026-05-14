import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'translations.dart';

enum NotificationType { message, follow, like, post }

class NotificationEntry {
  NotificationEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.isRead,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String subtitle;
  final String time;
  bool isRead;

  factory NotificationEntry.fromMap(Map<String, dynamic> map) {
    final rawType = (map['type'] as String?) ?? 'message';
    final createdAt = map['created_at'] as String?;
    return NotificationEntry(
      id: map['id'].toString(),
      type: _typeFromString(rawType),
      title: map['title'] as String? ?? 'Notificación',
      subtitle: map['message'] as String? ?? '',
      isRead: map['is_read'] as bool? ?? false,
      time: createdAt != null
          ? _formatTime(DateTime.parse(createdAt).toLocal())
          : 'Ahora',
    );
  }

  static NotificationType _typeFromString(String value) {
    switch (value) {
      case 'follow':
        return NotificationType.follow;
      case 'like':
        return NotificationType.like;
      case 'post':
        return NotificationType.post;
      default:
        return NotificationType.message;
    }
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Hace ${diff.inHours} hr';
    return '${time.day}/${time.month}/${time.year}';
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<NotificationEntry> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final response = await _supabase
          .from('notifications')
          .select('id, type, title, message, is_read, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final items = List<Map<String, dynamic>>.from(response as List);
      if (mounted) {
        setState(() {
          _notifications = items.map(NotificationEntry.fromMap).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando notificaciones: $e');
      if (mounted) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final unreadIds = _notifications.where((n) => !n.isRead).map((n) => n.id).toList();
    if (unreadIds.isEmpty) return;

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', unreadIds);
    } catch (_) {
      // Ignorar error si no se puede marcar como leído.
    }

    setState(() {
      for (final notification in _notifications) {
        notification.isRead = true;
      }
    });
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.message:
        return Icons.message;
      case NotificationType.follow:
        return Icons.person_add;
      case NotificationType.like:
        return Icons.favorite;
      case NotificationType.post:
        return Icons.notifications;
    }
  }

  Color _iconColorForType(NotificationType type) {
    switch (type) {
      case NotificationType.message:
        return Colors.blue;
      case NotificationType.follow:
        return Colors.green;
      case NotificationType.like:
        return Colors.red;
      case NotificationType.post:
        return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((note) => !note.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.text(context, 'notifications')),
        actions: [
          if (!_isLoading && unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                Translations.text(context, 'mark_as_read'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(Translations.text(context, 'no_new_notifications'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _notifications.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            _iconColorForType(notification.type).withOpacity(0.16),
                        child: Icon(
                          _iconForType(notification.type),
                          color: _iconColorForType(notification.type),
                        ),
                      ),
                      title: Text(notification.title),
                      subtitle: Text(notification.subtitle),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            notification.time,
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (!notification.isRead)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      tileColor: notification.isRead
                          ? Colors.transparent
                          : Theme.of(context).primaryColorLight.withOpacity(0.12),
                      onTap: () async {
                        if (!notification.isRead) {
                          try {
                            await _supabase
                                .from('notifications')
                                .update({'is_read': true})
                                .eq('id', notification.id);
                          } catch (_) {}
                          setState(() => notification.isRead = true);
                        }
                      },
                    );
                  },
                ),
    );
  }
}

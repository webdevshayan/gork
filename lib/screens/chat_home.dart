import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/history_store.dart';
import '../services/locator.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';

/// The Chat tab's HOME: recent threads like WhatsApp — title, last-message
/// snippet, time. Tapping a row pushes the thread full-screen (ChatPage);
/// the input bar composes a NEW thread. An empty home keeps the seeded
/// intro and the fanned GitHub preview cards.
class ChatHome extends StatelessWidget {
  const ChatHome({
    super.key,
    required this.onOpenChat,
    this.onCompose,
  });

  /// Opens an existing thread full-screen (the shell pushes ChatPage).
  final ValueChanged<String> onOpenChat;

  /// Quick compose from the input bar: opens a NEW thread.
  final ValueChanged<String>? onCompose;

  static const List<String> _introLines = [
    "Hey Shayan, I'm gork.",
    "I keep track of life and work, trips and groceries. I pay bills "
        "securely and find opportunities you'll love.",
    "With your permission, I'll connect your email and calendar, catch up "
        "on your life, and learn how I can help.",
  ];

  /// WhatsApp-style list time: clock time for today, a short date before.
  String _timeLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    if (that == today) {
      final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final String m = d.minute.toString().padLeft(2, '0');
      return '$h12:$m ${d.hour < 12 ? 'AM' : 'PM'}';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _snippet(Conversation c) {
    if (c.messages.isEmpty) return 'No messages yet';
    return c.messages.last.content.replaceAll('\n', ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final threads = Locator.history.all()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (threads.isEmpty) return const _EmptyChatHome();
    return ListView(
      key: const ValueKey('chat-thread-list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (final thread in threads)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ThreadRow(
              key: ValueKey('thread-${thread.id}'),
              title: thread.title,
              snippet: _snippet(thread),
              time: _timeLabel(thread.updatedAt),
              onTap: () => onOpenChat(thread.id),
            ),
          ),
      ],
    );
  }
}

/// One recent-thread row: glass card, title + time on top, snippet below.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    super.key,
    required this.title,
    required this.snippet,
    required this.time,
    required this.onTap,
  });

  final String title;
  final String snippet;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassContainer(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: GlassColors.text,
                          ),
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                            fontSize: 12, color: GlassColors.textDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 14, color: GlassColors.textDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: GlassColors.textDim),
          ],
        ),
      ),
    );
  }
}

/// The seeded intro while no threads exist — the same empty-chat composition
/// a fresh thread shows (intro bubbles + the fanned GitHub preview stack).
class _EmptyChatHome extends StatelessWidget {
  const _EmptyChatHome();

  @override
  Widget build(BuildContext context) {
    return const EmptyChat();
  }
}

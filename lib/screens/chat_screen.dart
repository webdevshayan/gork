import 'dart:ui';

import 'package:flutter/material.dart';

import '../providers/providers.dart';
import '../services/history_store.dart';
import '../services/llm_client.dart';
import '../services/locator.dart';
import '../widgets/glass.dart';

class _UiMessage {
  final String role;
  final String content;

  const _UiMessage(this.role, this.content);
}

/// The Chat tab: glass bubbles on the ambient backdrop, connected to the
/// unified chat(). The input lives in the shell's bottom bar, which calls
/// [ChatScreenState.send].
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.conversationId});

  final String? conversationId;

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  List<_UiMessage> _messages = [];
  String _conversationId = '';
  String _title = 'New chat';
  String? _providerId;
  bool _loading = false;
  String? _error;
  List<String> _toolsUsed = [];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefsProvider = Locator.prefs.getString('chat.providerId');
    if (prefsProvider != null && await Locator.chat.hasKey(prefsProvider)) {
      _providerId = prefsProvider;
    } else {
      for (final p in kProviders) {
        if (await Locator.chat.hasKey(p.id)) {
          _providerId = p.id;
          break;
        }
      }
    }

    Conversation? conversation;
    if (widget.conversationId != null) {
      conversation = Locator.history.byId(widget.conversationId!);
    }
    conversation ??= Locator.history.latest;

    if (conversation != null) {
      _conversationId = conversation.id;
      _title = conversation.title;
      _providerId = conversation.providerId;
      _messages = [
        for (final m in conversation.messages) _UiMessage(m.role, m.content),
      ];
    }
    if (mounted) setState(() {});
  }

  /// Public send API — the shell's glass input bar drives this.
  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _loading) return;
    if (_providerId == null) {
      setState(() => _error = 'No provider key yet. Add one in Providers.');
      return;
    }

    setState(() {
      _messages.add(_UiMessage('user', text));
      _error = null;
      _loading = true;
      if (_conversationId.isEmpty) {
        _conversationId = DateTime.now().millisecondsSinceEpoch.toString();
        _title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      }
    });
    _scrollToBottom();

    try {
      final result = await Locator.agent.run(
        providerId: _providerId!,
        userText: text,
        priorMessages: [
          for (final m in _messages.take(_messages.length - 1))
            ChatMessage(m.role, m.content),
        ],
      );
      setState(() {
        _messages.add(_UiMessage('assistant', result.content));
        _toolsUsed = result.toolsUsed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      await Locator.history.save(
        Conversation(
          id: _conversationId,
          title: _title,
          providerId: _providerId!,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          messages: [for (final m in _messages) ChatTurn(m.role, m.content)],
        ),
      );
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickProvider() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: kProviders.length,
            itemBuilder: (context, index) {
              final p = kProviders[index];
              return ListTile(
                title: Text(
                  p.name,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                subtitle: Text(
                  p.isCustom ? 'custom' : p.baseURL,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                trailing: _providerId == p.id ? const Icon(Icons.check) : null,
                onTap: () {
                  setState(() => _providerId = p.id);
                  Locator.prefs.setString('chat.providerId', p.id);
                  Navigator.pop(context);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _newChat() {
    setState(() {
      _messages = [];
      _conversationId = '';
      _title = 'New chat';
      _error = null;
      _toolsUsed = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              GlassContainer(
                radius: 30,
                opacity: 0.35,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickProvider,
                  child: Text(
                    _providerId == null
                        ? 'Pick provider'
                        : kProviders
                              .firstWhere((p) => p.id == _providerId)
                              .name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassContainer(
                radius: 30,
                opacity: 0.35,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _newChat,
                  child: const Text(
                    'New chat',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        if (_toolsUsed.isNotEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tool in _toolsUsed)
                  GlassActionChip(label: 'used: $tool'),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? _EmptyChat(error: _error)
              : _buildMessages(),
        ),
        if (_error != null && _messages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
            ),
          ),
      ],
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final m = _messages[index];
        return _Bubble(text: m.content, isUser: m.role == 'user');
      },
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

/// Spec bubbles: AI = solid white, radius 16, left. User = glass
/// white 0.4, radius 16, right (with its own backdrop blur).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final Widget bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? Colors.white.withValues(alpha: 0.4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isUser
            ? Border.all(color: Colors.white.withValues(alpha: 0.5))
            : null,
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 16, color: Colors.black87),
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: isUser
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: bubble,
                ),
              )
            : bubble,
      ),
    );
  }
}

/// Empty chat: the GitHub link preview card from the spec (small glass card,
/// slightly rotated with a stacked shadow) + guidance.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Transform.rotate(
          angle: -0.02,
          child: GlassContainer(
            width: 260,
            opacity: 0.4,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.code, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'webdevshayan/gork',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Hark Pro clone · open source on GitHub',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          error ??
              'Say something below. Your keys stay on this device. '
                  'gork builds panels and runs tools from chat.',
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          const Text(
            'Tip: pick a provider and add its key first.',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ],
    );
  }
}

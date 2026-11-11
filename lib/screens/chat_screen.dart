import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../providers/providers.dart';
import '../services/history_store.dart';
import '../services/llm_client.dart';
import '../services/locator.dart';
import '../services/memory_store.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';
import 'providers_screen.dart';

class _UiMessage {
  final String role;
  final String content;

  const _UiMessage(this.role, this.content);
}

/// The chat screen: message list + input, connected to the unified chat().
class ChatScreen extends StatefulWidget {
  final String? conversationId;

  const ChatScreen({super.key, this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
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
        for (final m in conversation.messages) _UiMessage(m.role, m.content)
      ];
    }
    if (mounted) setState(() {});
  }

  String _systemPrompt() {
    final memoryBlock = Locator.memory.systemPromptBlock();
    return 'You are gork, the user\u2019s personal AI assistant running on their '
        'Android phone. Be direct, concrete and helpful. '
        'Sensitive actions always ask for confirmation first.$memoryBlock';
  }

  List<ChatMessage> _asChatMessages() => [
        ChatMessage('system', _systemPrompt()),
        for (final m in _messages) ChatMessage(m.role, m.content),
      ];

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    if (_providerId == null) {
      setState(() => _error = 'No provider key yet. Add one in Providers.');
      return;
    }

    _input.clear();
    setState(() {
      _messages.add(_UiMessage('user', text));
      _error = null;
      _loading = true;
      if (_conversationId.isEmpty) {
        _conversationId =
            DateTime.now().millisecondsSinceEpoch.toString();
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
      await Locator.history.save(Conversation(
        id: _conversationId,
        title: _title,
        providerId: _providerId!,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        messages: [
          for (final m in _messages) ChatTurn(m.role, m.content),
        ],
      ));
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
    final palette = paletteOf(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RadiusTokens.xl)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: kProviders.length,
            itemBuilder: (context, index) {
              final p = kProviders[index];
              return ListTile(
                title: Text(p.name, style: TypeScale.body(color: palette.textPrimary)),
                subtitle: Text(p.isCustom ? 'custom' : p.baseURL,
                    style: TypeScale.caption(color: palette.textTertiary)),
                trailing: _providerId == p.id
                    ? Icon(Icons.check, color: palette.primary)
                    : null,
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: _title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Row(
              children: [
                GButton(
                  label: _providerId == null
                      ? 'Pick provider'
                      : kProviders.firstWhere((p) => p.id == _providerId).name,
                  variant: ButtonVariant.secondary,
                  onPressed: _pickProvider,
                ),
                const SizedBox(width: Spacing.sm),
                GButton(
                  label: 'New chat',
                  variant: ButtonVariant.ghost,
                  onPressed: _newChat,
                ),
              ],
            ),
          ),
          if (_toolsUsed.isNotEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  for (final tool in _toolsUsed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: Spacing.xs),
                      decoration: BoxDecoration(
                        color: palette.primary.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(RadiusTokens.full),
                      ),
                      child: Text('used: $tool',
                          style: TypeScale.caption(color: palette.primary)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? GCard(
                    child: Text(
                      'Say something. Your keys stay on this device.',
                      style: TypeScale.body(color: palette.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final isUser = m.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: Spacing.sm),
                          padding: const EdgeInsets.all(Spacing.md),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.85,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? palette.primary
                                : palette.surface,
                            borderRadius: BorderRadius.circular(
                              RadiusTokens.lg,
                            ),
                          ),
                          child: SelectableText(
                            m.content,
                            style: TypeScale.body(
                              color: isUser
                                  ? palette.onPrimary
                                  : palette.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                _error!,
                style: TypeScale.caption(color: palette.error),
              ),
            ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_loading,
                    style: TypeScale.body(color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message gork…',
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(RadiusTokens.md),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                GButton(
                  label: _loading ? '…' : 'Send',
                  onPressed: _loading ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

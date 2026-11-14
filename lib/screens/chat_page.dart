import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/design_tokens.dart';
import '../services/history_store.dart';
import '../widgets/bottom_input_bar.dart';
import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';

/// A pushed, full-screen chat: glass top bar (chevron back + thread title)
/// and its own input bar. Used by the chat home (threads), project folders
/// and search hits — one conversation, one screen, wherever it opens from.
///
/// With [conversationId] null the page creates a brand-new empty thread and
/// delivers [initialMessage] / [pendingAttachment] once the thread exists.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.conversationId,
    this.initialMessage,
    this.pendingAttachment,
    this.backLabel = 'Back',
  });

  /// The thread to open; null composes a new one.
  final String? conversationId;

  /// A message to send right after the thread opens (quick compose).
  final String? initialMessage;

  /// An attachment to land right after the thread opens.
  final ChatAttachment? pendingAttachment;

  /// TalkBack label for the back chevron.
  final String backLabel;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();
  late String _conversationId =
      widget.conversationId ?? _freshConversationId();

  static String _freshConversationId() =>
      'new-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _deliverPending());
  }

  Future<void> _deliverPending() async {
    final state = _chatKey.currentState;
    if (state == null) return;
    if (widget.pendingAttachment != null) {
      await state.attachImage(
        widget.pendingAttachment!.path,
        name: widget.pendingAttachment!.name,
      );
    }
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      await state.send(widget.initialMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        Locator.history.byId(_conversationId)?.title ?? 'New chat';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      GlassBackButton(
                        key: const ValueKey('chat-page-back'),
                        label: widget.backLabel,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: GlassColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ChatScreen(
                    key: _chatKey,
                    conversationId: _conversationId,
                  ),
                ),
                _ChatPageInputBar(chatKey: _chatKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The input bar for the pushed chat screen — same glass bar, wired to the
/// page's ChatScreen through the key the page owns.
class _ChatPageInputBar extends StatefulWidget {
  const _ChatPageInputBar({required this.chatKey});

  final GlobalKey<ChatScreenState> chatKey;

  @override
  State<_ChatPageInputBar> createState() => _ChatPageInputBarState();
}

class _ChatPageInputBarState extends State<_ChatPageInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.chatKey.currentState?.send(text);
  }

  Future<void> _attach() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 82,
      );
      if (picked == null || !mounted) return;
      await widget.chatKey.currentState
          ?.attachImage(picked.path, name: picked.name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not attach that.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomInputBar(
      controller: _controller,
      focusNode: _focus,
      onSend: _send,
      onAttach: _attach,
    );
  }
}

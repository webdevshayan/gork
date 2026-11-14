import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../providers/providers.dart';
import '../services/attachment_context.dart';
import '../services/history_store.dart';
import '../services/llm_client.dart';
import '../services/locator.dart';
import '../services/projects_store.dart';
import '../widgets/glass.dart';
import '../widgets/markdown_view.dart';
import '../constants/design_tokens.dart';

class _UiMessage {
  final String role;
  final String content;
  final int? time;
  final ChatAttachment? attachment;

  const _UiMessage(this.role, this.content, {this.time, this.attachment});
}

/// The Chat tab, pixel-matched to the reference screenshots:
/// white AI bubbles (radius 32, left), glass user bubbles (right), centered
/// date separators, "Read" receipts under answered user bubbles, a floating
/// scroll-down button, the fanned GitHub link-preview stack on an empty chat,
/// and live search filtering driven by the shell's search bar.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.conversationId,
    this.searchOpen = false,
  });

  final String? conversationId;

  /// Whether the shell currently shows the search bar.
  final bool searchOpen;

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
  String? _searchQuery;
  bool _showScrollButton = false;

  /// The seeded intro from the reference: shown when this is a brand-new
  /// conversation (never persisted, replaced by real history once it exists).
  static const List<String> _introMessages = [
    "Hey Shayan, I'm gork.",
    "I keep track of life and work, trips and groceries. I pay bills "
        "securely and find opportunities you'll love.",
    "With your permission, I'll connect your email and calendar, catch up "
        "on your life, and learn how I can help.",
  ];

  @override
  void initState() {
    super.initState();
    _restore();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ChatScreen old) {
    super.didUpdateWidget(old);
    if (widget.conversationId != old.conversationId) {
      // The shell switched conversations (e.g. a chat opened from inside a
      // project folder) — restore that thread, not the previous one.
      _restore();
    }
    if (!widget.searchOpen && old.searchOpen) {
      _searchQuery = null;
      if (mounted) setState(() {});
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final bool nearBottom =
        _scroll.offset >= _scroll.position.maxScrollExtent - 240;
    if (nearBottom != !_showScrollButton) {
      setState(() => _showScrollButton = !nearBottom);
    }
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
      // An explicit conversation (e.g. a chat opened from inside a project)
      // never falls back to the global latest conversation.
      conversation = Locator.history.byId(widget.conversationId!);
      if (conversation == null) {
        _conversationId = widget.conversationId!;
        _title = 'New chat';
      }
    } else {
      conversation = Locator.history.latest;
    }

    if (conversation != null) {
      _conversationId = conversation.id;
      _title = conversation.title;
      // 'none' marks conversations that were never tied to a provider
      // (attachment-only threads) — treat them as "no key yet".
      _providerId =
          conversation.providerId == 'none' ? null : conversation.providerId;
      _messages = [
        for (final m in conversation.messages)
          _UiMessage(m.role, m.content,
              time: m.time, attachment: m.attachment),
      ];
    }
    if (mounted) setState(() {});
  }

  /// History turn → API message. Text files feed the agent their real
  /// content (capped); images ride as vision payloads for multimodal
  /// providers — and when an image cannot load (missing, oversized, unknown
  /// type) its honest marker is all that travels.
  ChatMessage _withAttachment(_UiMessage m) {
    if (m.attachment == null) return ChatMessage(m.role, m.content);
    final image = AttachmentContext.loadImage(m.attachment!);
    return ChatMessage(
      m.role,
      AttachmentContext.describe(m.attachment!),
      images: image == null ? null : [image],
    );
  }

  /// Public send API — the shell's glass input bar drives this.
  Future<void> send(String rawText) async {    final text = rawText.trim();
    if (text.isEmpty || _loading) return;

    // The user's message always lands in the thread, even before any key is
    // configured — the guidance shows underneath it.
    setState(() {
      _messages.add(
        _UiMessage('user', text, time: DateTime.now().millisecondsSinceEpoch),
      );
      _error = null;
      if (_conversationId.isEmpty) {
        _conversationId = DateTime.now().millisecondsSinceEpoch.toString();
        _title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      }
    });
    _scrollToBottom();

    if (_providerId == null) {
      setState(() => _error = 'No provider key yet. Add one in Providers.');
      return;
    }

    setState(() => _loading = true);

    try {
      final result = await Locator.agent.run(
        providerId: _providerId!,
        userText: text,
        priorMessages: [
          for (final m in _messages.take(_messages.length - 1))
            _withAttachment(m),
        ],
      );
      setState(() {
        _messages.add(
          _UiMessage('assistant', result.content,
              time: DateTime.now().millisecondsSinceEpoch),
        );
        _toolsUsed = result.toolsUsed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      await _persist();
      _scrollToBottom();
    }
  }

  /// An image picked from the + menu lands here as a thread message. When
  /// the conversation lives in a project folder, the resource mirrors into
  /// that folder — projects host their files and images at the project level.
  Future<void> attachImage(String path, {String? name}) {
    return _attach(ChatAttachment('image', path, name ?? path.split('/').last));
  }

  /// A picked file (document, note, anything) lands the same way.
  Future<void> attachFile(String path, String name) {
    return _attach(ChatAttachment('file', path, name));
  }

  Future<void> _attach(ChatAttachment attachment) async {
    setState(() {
      _error = null;
      if (_conversationId.isEmpty) {
        _conversationId = DateTime.now().millisecondsSinceEpoch.toString();
        _title = attachment.name;
      }
      _messages.add(
        _UiMessage('user', '',
            time: DateTime.now().millisecondsSinceEpoch,
            attachment: attachment),
      );
    });
    _scrollToBottom();

    // Mirror into the owning project folder (best effort — the thread keeps
    // the attachment even when the folder write fails).
    try {
      final project = Locator.projects.projectOfChat(_conversationId);
      if (project != null) {
        if (attachment.kind == 'image') {
          await Locator.projects.save(project.copyWith(
            images: [
              ...project.images,
              ProjectImage(attachment.name, attachment.path),
            ],
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          String content = '';
          try {
            // Text resources are small; a sync read keeps the mirror atomic
            // and avoids leaving the message loop mid-attach.
            content = File(attachment.path).readAsStringSync();
          } catch (_) {
            // Binary file — the folder card stores the path only.
          }
          await Locator.projects.save(project.copyWith(
            files: [
              ...project.files,
              ProjectFile(attachment.name, content),
            ],
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
        }
      }
    } catch (_) {}
    await _persist();
  }

  /// Writes the thread to history. Attachment-only threads save with the
  /// 'none' provider marker so they restore cleanly.
  Future<void> _persist() async {
    if (_conversationId.isEmpty) return;
    await Locator.history.save(
      Conversation(
        id: _conversationId,
        title: _title,
        providerId: _providerId ?? 'none',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        messages: [
          for (final m in _messages)
            ChatTurn(m.role, m.content,
                time: m.time, attachment: m.attachment),
        ],
      ),
    );
  }

  /// Live search — the shell's search bar drives this. Empty string shows
  /// the filtered (empty result) state; null leaves search mode entirely.
  void search(String? query) {
    setState(() => _searchQuery = (query == null || query.isEmpty)
        ? (query == null ? null : '')
        : query.toLowerCase());
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
                  style: TextStyle(fontSize: 16, color: GlassColors.text),
                ),
                subtitle: Text(
                  p.isCustom ? 'custom' : p.baseURL,
                  style: TextStyle(fontSize: 12, color: GlassColors.textDim),
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

  // ---- rendering -----------------------------------------------------------

  String _dayLabel(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    if (that == today) return 'Today';
    if (that == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday',
    ];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  bool _sameDay(int? a, int? b) {
    if (a == null || b == null) return true;
    final da = DateTime.fromMillisecondsSinceEpoch(a);
    final db = DateTime.fromMillisecondsSinceEpoch(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  Widget _separator(String label) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: 15, color: GlassColors.textDim),
          ),
        ),
      );

  List<Widget> _bubbleList(List<_UiMessage> source) {
    final widgets = <Widget>[];
    for (var i = 0; i < source.length; i++) {
      final m = source[i];
      final prev = i > 0 ? source[i - 1] : null;
      final bool newDay = prev == null || !_sameDay(m.time, prev.time);
      if (newDay && m.time != null) {
        widgets.add(_separator(_dayLabel(m.time!)));
      } else if (prev == null && m.time != null) {
        widgets.add(_separator(_dayLabel(m.time!)));
      }
      widgets.add(_Bubble(
        text: m.content,
        isUser: m.role == 'user',
        attachment: m.attachment,
      ));
      final bool answered = m.role == 'user' &&
          source.indexWhere((x) => x.role == 'assistant', i) > i;
      if (answered) {
        widgets.add(
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8, right: 8),
              child: Text(
                '•••• Read',
                style: TextStyle(fontSize: 12, color: GlassColors.textFaint),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final bool searching = _searchQuery != null;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: searching
                  ? _buildSearchResults()
                  : _messages.isEmpty
                      ? _EmptyChat(error: _error)
                      : _buildMessages(),
            ),
            if (!searching && _toolsUsed.isNotEmpty && !_loading)
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
            if (_error != null && _messages.isNotEmpty && !searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ),
          ],
        ),
        if (!searching && _showScrollButton && _messages.isNotEmpty)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: GlassScrollButton(
                onTap: _scrollToBottom,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessages() {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: _bubbleList(_messages),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchQuery!;
    // Empty query in search mode shows the whole conversation.
    if (query.isEmpty) {
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: _messages.isEmpty
            ? List<Widget>.of(_EmptyChat(error: _error).buildChildren())
            : _bubbleList(_messages),
      );
    }
    final hits = [
      for (final m in _messages)
        if (m.content.toLowerCase().contains(query)) m,
    ];
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        if (hits.isEmpty)
          GlassContainer(
            radius: 24,
            padding: const EdgeInsets.all(20),
            child: Text(
              'No results for "$query".',
              style: TextStyle(fontSize: 16, color: GlassColors.textDim),
            ),
          )
        else ..._bubbleList(hits),
      ],
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

/// Reference bubbles: AI = solid white, radius 32, left. User = glass
/// white 0.4 + backdrop blur, radius 32, right. Attachment turns render the
/// media as a card instead of text.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isUser,
    this.attachment,
  });

  final String text;
  final bool isUser;
  final ChatAttachment? attachment;

  Future<void> _openFilePreview(BuildContext context) async {
    String content = '';
    bool binary = false;
    try {
      // Text resources are small; sync read keeps the sheet atomic.
      content = File(attachment!.path).readAsStringSync();
    } catch (_) {
      binary = true;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              key: const ValueKey('file-preview'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment!.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: GlassColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: binary
                        ? Text(
                            'Binary file — stored on this device, no preview.',
                            style: TextStyle(fontSize: 15, color: GlassColors.textDim),
                          )
                        : SelectableText(
                            content,
                            style: TextStyle(
                                fontSize: 14, color: GlassColors.text),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A picture that no longer resolves keeps looking honest, like the
  /// reference: dark panel, red Error pill, refresh icon.
  Widget _imageWidget() {
    return Image.file(
      File(attachment!.path),
      height: 190,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        key: const ValueKey('attachment-error'),
        height: 190,
        color: const Color(0xFF101216),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Error',
                style: TextStyle(fontSize: 13, color: Color(0xFFF87171)),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.refresh, size: 18, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget bubble;
    if (attachment != null) {
      bubble = Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: GlassColors.fill,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: GlassColors.border),
        ),
        child: attachment!.kind == 'image'
            ? ClipRRect(
                key: const ValueKey('attachment-image'),
                borderRadius: BorderRadius.circular(24),
                child: _imageWidget(),
              )
            : GestureDetector(
                key: const ValueKey('attachment-file'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _openFilePreview(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: GlassColors.fillStrong,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.insert_drive_file_outlined,
                          size: 20, color: GlassColors.text),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          attachment!.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15, color: GlassColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );
    } else {
      bubble = Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          // dark theme: user bubbles are dark glass, assistant bubbles are a
          // solid dark surface so long markdown reads cleanly.
          color: isUser
              ? GlassColors.fill
              : Palette.dark.surface,
          borderRadius: BorderRadius.circular(32),
          border: isUser
              ? Border.all(color: GlassColors.border)
              : Border.all(color: GlassColors.divider),
        ),
        child: isUser
            ? SelectableText(
                text,
                style: TextStyle(fontSize: 16, color: GlassColors.text),
              )
            // Assistant bubbles render safe markdown (no web view, no network).
            : MarkdownView(text),
      );
    }

    return Align(
      alignment: isUser || attachment != null
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: isUser || attachment != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(32),
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

/// Empty chat: the seeded intro sequence, then the fanned GitHub
/// link-preview stack (three slightly rotated cards, like the reference).
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({this.error});

  final String? error;

  static const List<_PreviewCard> _cards = [
    _PreviewCard(
      title: 'Movement 12: Integration framework + GitHub integration',
      footer: 'GitHub · gork PR #12',
      angle: -0.09,
      lift: 44,
    ),
    _PreviewCard(
      title: 'Movement 19: Hark-style glass UI rebuild',
      footer: 'GitHub · gork PR #19',
      angle: 0,
      lift: 0,
    ),
    _PreviewCard(
      title: 'Movement 15: 24/7 handoff — task sync with the daemon',
      footer: 'GitHub · gork PR #15',
      angle: 0.09,
      lift: 44,
    ),
  ];

  List<Widget> buildChildren() {
    return [
      for (final line in ChatScreenState._introMessages)
        _Bubble(text: line, isUser: false),
      const SizedBox(height: 24),
      SizedBox(
        height: 320,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            for (final card in _cards)
              Positioned(
                top: card.lift,
                left: card.angle < 0 ? 0 : (card.angle > 0 ? 24 : 40),
                right: card.angle > 0 ? 0 : (card.angle < 0 ? 24 : 40),
                child: Transform.rotate(
                  angle: card.angle,
                  child: _PreviewCardView(card: card),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        error ?? 'Say something below. Your keys stay on this device.',
        style: TextStyle(
            fontSize: 14, color: GlassColors.textDim),
      ),
      if (error != null) ...[
        const SizedBox(height: 8),
        Text(
          'Tip: add a provider key first (Menu → Security → Providers).',
          style: TextStyle(fontSize: 14, color: GlassColors.text),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: buildChildren());
  }
}

class _PreviewCard {
  const _PreviewCard({
    required this.title,
    required this.footer,
    required this.angle,
    required this.lift,
  });

  final String title;
  final String footer;
  final double angle;
  final double lift;
}

class _PreviewCardView extends StatelessWidget {
  const _PreviewCardView({required this.card});

  final _PreviewCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.code, size: 40, color: GlassColors.text),
          ),
          const SizedBox(height: 10),
          Text(
            card.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: GlassColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.code, size: 12, color: GlassColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  card.footer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: GlassColors.textDim,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

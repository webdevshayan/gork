import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../providers/providers.dart';
import '../services/attachment_context.dart';
import '../services/history_store.dart';
import '../services/llm_client.dart';
import '../services/locator.dart';
import '../services/outbox.dart';
import '../services/profile_info.dart';
import '../services/projects_store.dart';
import '../widgets/error_card.dart';
import '../widgets/glass.dart';
import '../widgets/markdown_view.dart';
import '../constants/design_tokens.dart';

class _UiMessage {
  final String role;
  final String content;
  final int? time;
  final ChatAttachment? attachment;

  /// True when the bubble should enter like it was just sent by a real
  /// person behind the app (the first-run intro sequence).
  final bool animate;

  /// Movement 64 — sent while another reply was still being worked on:
  /// the bubble shows as queued until the batch goes out.
  final bool queued;

  const _UiMessage(this.role, this.content,
      {this.time, this.attachment, this.animate = false,
       this.queued = false});

  /// The queued message went out — it reads as a normal sent message now.
  _UiMessage markSent() => _UiMessage(role, content,
      time: time, attachment: attachment, animate: animate);
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
  Timer? _serverPoll;
  Timer? _introTimer;
  final ScrollController _scroll = ScrollController();
  List<_UiMessage> _messages = [];
  String _conversationId = '';
  String _title = 'New chat';
  String? _providerId;
  bool _loading = false;
  String? _error;

  /// The raw provider body behind [_error] — rendered only inside the
  /// error card's expandable Details view, never as plain chat text.
  String? _errorDetails;
  List<String> _toolsUsed = [];
  String? _searchQuery;
  bool _showScrollButton = false;

  /// Movement 64 — messages typed while a reply is still on its way.
  /// They queue as dimmed bubbles and go out TOGETHER as one batched
  /// request the moment the current reply lands: fewer VPS round-trips,
  /// one coherent answer, like a person who read your follow-ups.
  final List<String> _queued = [];

  @override
  void initState() {
    super.initState();
    _restore();
    _scroll.addListener(_onScroll);
    // Movement 64 — the chat is in front: reply notifications hold off
    // (the answer arrives in the thread instead).
    Locator.notifications.inChat = true;
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
    // History loads FIRST, synchronously, before anything async: the very
    // first frame must show the real thread. Resolving the provider used to
    // happen before this, so slow key checks flashed the seeded intro
    // placeholders before real messages swapped in (the v1.7.x preload bug).
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
      if (mounted) setState(() {});
    }

    // Provider resolution is async and only affects SENDING, never what the
    // user already sees — safe to settle after the thread is on screen.
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
    if (mounted) setState(() {});
    await _syncFromServer();
    // First run of the global chat: the intro plays like a real person
    // sending messages one after another (Movement 53).
    if (widget.conversationId == kGlobalChatId &&
        _messages.isEmpty &&
        mounted &&
        Locator.prefs.getBool('intro.done') != true) {
      await _playIntro();
    }
  }

  /// The first-run intro: ONE request generates every message (on the VPS
  /// when configured, the reference set otherwise), and they then land as
  /// separate bubbles with human-like timing. Persisted along the way so a
  /// killed app resumes exactly where the sequence stopped.
  Future<void> _playIntro() async {
    await Locator.prefs.setBool('intro.done', true);
    final name =
        Locator.prefs.getString('profile.name') ?? kDefaultName;
    final email = Locator.prefs.getString('profile.email');
    final intro = await Locator.intro.fetchIntro(name: name, email: email);
    if (!mounted) return;
    for (var i = 0; i < intro.length; i++) {
      // Human cadence: nobody sends bubbles at metronome intervals.
      // A cancellable timer: disposal kills the sequence cleanly instead
      // of leaving timers pending past the widget tree.
      final beat = Completer<void>();
      _introTimer = Timer(Duration(milliseconds: 750 + (i % 3) * 350), beat.complete);
      await beat.future;
      if (!mounted) return;
      setState(() {
        _messages.add(_UiMessage('assistant', intro[i],
            time: DateTime.now().millisecondsSinceEpoch, animate: true));
      });
      await _persist();
      _scrollToBottom();
    }
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
  ///
  /// Movement 64 — a message typed while a reply is on its way is QUEUED,
  /// never dropped. Queued messages show as dimmed "queued" bubbles and
  /// go out together as ONE request when the current reply lands.
  /// [silent] (the queue drain) adds no bubble — the queued bubbles
  /// themselves are the sent record.
  Future<void> send(String rawText, {bool silent = false}) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    // The user's message always lands in the thread, even before any key is
    // configured — the guidance shows underneath it.
    final bool willQueue = _loading && !silent;
    if (!silent) {
      setState(() {
        _messages.add(
          _UiMessage('user', text,
              time: DateTime.now().millisecondsSinceEpoch,
              queued: willQueue),
        );
        _error = null;
        _errorDetails = null;
        if (_conversationId.isEmpty) {
          _conversationId = DateTime.now().millisecondsSinceEpoch.toString();
          _title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
        }
      });
      _scrollToBottom();
      if (willQueue) {
        _queued.add(text);
        await _persist();
        return;
      }
    }

    // The VPS owns the request when one is configured: the message is
    // enqueued server-side and survives device death / app inactivity. The
    // reply is polled while this screen is open; if it closes (or the device
    // dies), the job keeps running and _restore merges the reply on return.
    if (Locator.outbox.configured) {
      setState(() => _loading = true);
      final entry =
          await Locator.outbox.enqueue(_conversationId, text, awaitAcceptance: true);
      await _persist();
      if (entry.jobId != null) {
        _startServerPoll(entry.jobId!);
      } else {
        setState(() => _loading = false);
      }
      // Context-length-aware room extraction — the VPS distills the
      // conversation into the memory rooms when the transcript grows past
      // the model's usable context. Fire and forget: never blocks the chat.
      unawaited(Locator.memoryRooms.maybeExtract(_conversationId));
      return;
    }

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
          _UiMessage('assistant', _humanize(result.content),
              time: DateTime.now().millisecondsSinceEpoch),
        );
        _toolsUsed = result.toolsUsed;
        _loading = false;
      });
      await _persist();
      _scrollToBottom();
      // The reply landed — whatever the user typed while waiting goes out
      // now, batched into ONE request.
      await _flushQueue();
    } on LlmException catch (e) {
      setState(() {
        _error = e.message;
        _errorDetails = e.details;
        _loading = false;
      });
      await _flushQueue();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _errorDetails = null;
        _loading = false;
      });
      await _flushQueue();
    } finally {
      await _persist();
      _scrollToBottom();
    }
  }

  /// Polls an accepted server job while this screen is open. The poll stops
  /// when the screen is disposed — the JOB does not: it finishes on the VPS.
  void _startServerPoll(String jobId) {
    _serverPoll?.cancel();
    _serverPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final reply = await Locator.outbox.jobResult(jobId);
      if (reply == null || !mounted) return;
      _serverPoll?.cancel();
      _serverPoll = null;
      setState(() {
        _messages.add(
          _UiMessage('assistant', _humanize(reply),
              time: DateTime.now().millisecondsSinceEpoch),
        );
        _loading = false;
      });
      await _persist();
      _scrollToBottom();
      // Reply landed — release the queue as one batched send (Movement 64).
      await _flushQueue();
    });
  }

  /// Movement 64 — the queue drain: every message typed while a reply was
  /// on its way goes out here as ONE batched request (joined with
  /// newlines, exactly as a person would have typed them in sequence).
  /// The dimmed "queued" bubbles flip to normal sent bubbles — the thread
  /// reads like it does in real messaging: three quick messages, ONE reply.
  Future<void> _flushQueue() async {
    if (_queued.isEmpty || !mounted) return;
    final batch = _queued.join('\n');
    _queued.clear();
    setState(() {
      _messages = [
        for (final m in _messages) m.queued ? m.markSent() : m,
      ];
    });
    try {
      await send(batch, silent: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not send your queued messages — check the '
              'connection and send again.';
        });
      }
    }
  }

  /// A raw Dart exception on the VPS side ("HandshakeException: Connection
  /// terminated during handshake") must not land in the thread as if the
  /// agent SAID that. One friendly line instead — the technical text stays
  /// available underneath (collapsed).
  String _humanize(String reply) {
    final m = RegExp(r'^([A-Za-z_]+(?:Exception|Error)):\s*(.+)$',
            multiLine: false)
        .firstMatch(reply.trim());
    if (m == null) return reply;
    return 'I hit a snag on my side mid-task — the connection dropped '
        'before I could finish. Send that again and I will pick it up '
        'from where it broke.';
  }

  /// Catch-up on restore: merge any replies the VPS produced while this
  /// screen (or the whole device) was away. A per-conversation watermark
  /// keeps the merge idempotent.
  Future<void> _syncFromServer() async {
    if (!Locator.outbox.configured || _conversationId.isEmpty) return;
    final serverMsgs = await Locator.outbox.pullMessages(_conversationId);
    if (serverMsgs.isEmpty || !mounted) return;
    final wmKey = 'outbox.sync.${_conversationId}';
    final prefs = Locator.prefs;
    final watermark = prefs.getInt(wmKey) ?? 0;
    bool changed = false;
    for (var i = watermark; i < serverMsgs.length; i++) {
      final m = serverMsgs[i];
      if (m['role'] != 'assistant') continue;
      if (_messages.any((u) => u.role == 'assistant' && u.content == m['content'])) {
        continue; // already merged by the live poll
      }
      setState(() {
        _messages.add(_UiMessage('assistant', _humanize(m['content']!),
            time: DateTime.now().millisecondsSinceEpoch));
      });
      changed = true;
    }
    await prefs.setInt(wmKey, serverMsgs.length);
    if (changed) {
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
      _errorDetails = null;
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
  /// Test hook: how many messages the visible state holds.
  @visibleForTesting
  int get messageCount => _messages.length;

  /// Test hook: is the search-results branch showing?
  @visibleForTesting
  bool get searching => _searchQuery != null;

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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: GlassContainer(
            radius: 24,
            strong: true,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(vertical: 8),
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
      _errorDetails = null;
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  bool _sameDay(int? a, int? b) {
    if (a == null || b == null) return true;
    final da = DateTime.fromMillisecondsSinceEpoch(a);
    final db = DateTime.fromMillisecondsSinceEpoch(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  /// Time-only stamp under a bubble: 'h:mm a', deterministic, no intl.
  String _timeLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final String min = d.minute.toString().padLeft(2, '0');
    return '$h12:$min ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// The centered glass date badge — Google-Messages-style: it scrolls WITH
  /// its day group instead of pinning, so the only badge on screen is the one
  /// for the messages being viewed (never a stale pinned badge above).
  Widget _dateBadge(String label) => Center(
        child: GlassContainer(
          radius: 20,
          strong: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: GlassColors.textDim),
          ),
        ),
      );

  Widget _withStamp(_UiMessage m) {
    final Widget bubble = _Bubble(
      text: m.content,
      isUser: m.role == 'user',
      attachment: m.attachment,
      dimmed: m.queued,
    );
    final bool left = !(m.role == 'user' || m.attachment != null);
    return _BubbleEntrance(
      animate: m.animate,
      child: Column(
        crossAxisAlignment:
            left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          bubble,
          // Movement 64 — the follow-up the user typed while a reply was on
          // its way: a small "queued" tag under the dimmed bubble.
          if (m.queued)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.schedule, size: 12,
                      color: GlassColors.textFaint),
                  const SizedBox(width: 4),
                  Text('queued',
                      style: TextStyle(
                          fontSize: 11, color: GlassColors.textFaint)),
                ],
              ),
            ),
          if (m.time != null)
            Padding(
              padding: EdgeInsets.only(
                  bottom: 8, left: left ? 4 : 0, right: left ? 0 : 4),
              child: Text(
                _timeLabel(m.time!),
                style: TextStyle(fontSize: 11, color: GlassColors.textFaint),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Messages grouped by calendar day, in order. Days with no timestamp fall
  /// into an unlabeled leading group (no badge).
  List<_DayGroup> _groupedByDay(List<_UiMessage> source) {
    final groups = <_DayGroup>[];
    for (final m in source) {
      final String label = m.time == null ? '' : _dayLabel(m.time!);
      if (groups.isEmpty || groups.last.label != label) {
        groups.add(_DayGroup(label, [m]));
      } else {
        groups.last.messages.add(m);
      }
    }
    return groups;
  }

  /// Inline-badge thread renderer: one badge per day that scrolls with its
  /// messages (only one visible at a time), stamps under every bubble,
  /// 16dp side padding keeps bubbles off the screen edges, no Read receipts.
  List<Widget> _threadSlivers(List<_UiMessage> source) {
    final slivers = <Widget>[];
    for (final g in _groupedByDay(source)) {
      if (g.label.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(child: _dateBadge(g.label)));
      }
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Column(
            children: [for (final m in g.messages) _withStamp(m)],
          ),
        ),
      ));
    }
    return slivers;
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
                      ? EmptyChat(error: _error, errorDetails: _errorDetails)
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
                child: ErrorDetailsCard(
                    summary: _error!, details: _errorDetails),
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
    return CustomScrollView(
      controller: _scroll,
      // Movement 55: the viewport clips — scrolled bubbles must not paint
      // behind the top bar and its nav pill (the bleed in the screenshots).
      clipBehavior: Clip.hardEdge,
      slivers: [
        const SliverPadding(padding: EdgeInsets.symmetric(vertical: 16)),
        ..._threadSlivers(_messages),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  Widget _buildSearchResults() {
    final query = _searchQuery!;
    // Empty query in search mode shows the whole conversation.
    if (query.isEmpty) {
      return _messages.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: EmptyChat(error: _error, errorDetails: _errorDetails)
                  .buildChildren(),
            )
          : CustomScrollView(
              controller: _scroll,
              clipBehavior: Clip.hardEdge,
              slivers: [
                const SliverPadding(padding: EdgeInsets.symmetric(vertical: 16)),
                ..._threadSlivers(_messages),
                const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
              ],
            );
    }
    final hits = [
      for (final m in _messages)
        if (m.content.toLowerCase().contains(query)) m,
    ];
    return CustomScrollView(
      controller: _scroll,
      clipBehavior: Clip.hardEdge,
      slivers: [
        const SliverPadding(padding: EdgeInsets.symmetric(vertical: 16)),
        if (hits.isEmpty)
          SliverToBoxAdapter(
            child: GlassContainer(
              radius: 24,
              padding: const EdgeInsets.all(20),
              child: Text(
                'No results for "$query".',
                style: TextStyle(fontSize: 16, color: GlassColors.textDim),
              ),
            ),
          )
        else ..._threadSlivers(hits),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  @override
  void dispose() {
    _serverPoll?.cancel(); // local polling only — server work is never cancelled
    _introTimer?.cancel(); // a disposed screen never finishes the intro
    _scroll.dispose();
    // The chat is no longer in front — finished replies may notify again.
    Locator.notifications.inChat = false;
    super.dispose();
  }
}

/// How a bubble enters when it was just sent by a real person behind the
/// app: fades in, rises a little and settles with a soft overshoot — used
/// by the first-run intro sequence (Movement 53).
class _BubbleEntrance extends StatefulWidget {
  const _BubbleEntrance({required this.child, this.animate = false});

  final Widget child;
  final bool animate;

  @override
  State<_BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<_BubbleEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
      )..forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final curved =
        CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Google-Messages-style bubbles: solid theme-aware fills, no glass blur.
/// The person's bubble is ink (black in light mode, near-white in dark) with
/// the label on the opposite side; the assistant's is the quiet surface so
/// long markdown reads cleanly. Sender-side corner is tighter (6) like the
/// reference app; attachments render as rounded media cards.
class _Bubble extends StatelessWidget {  const _Bubble({
    required this.text,
    required this.isUser,
    this.attachment,
    this.dimmed = false,
  });

  final String text;
  final bool isUser;
  final ChatAttachment? attachment;

  /// Movement 64 — a queued follow-up: rendered softer until it goes out.
  final bool dimmed;

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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: GlassContainer(
            radius: 24,
            strong: true,
            margin: const EdgeInsets.all(12),
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
      final Palette palette = paletteOf(context);
      bubble = Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
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
      final Palette palette = paletteOf(context);
      bubble = Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          // Google Messages fills: the person's bubble is ink (black in light
          // mode, near-white in dark), the assistant's is the surface so
          // markdown always sits on a calm, theme-aware plate.
          color: isUser ? palette.primary : palette.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isUser ? 22 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 22),
          ),
        ),
        child: isUser
            ? SelectableText(
                text,
                style: TextStyle(fontSize: 16, color: palette.onPrimary),
              )
            // Assistant bubbles render safe markdown (no web view, no network)
            // inside a SelectionArea — AI responses are selectable too.
            : SelectionArea(child: MarkdownView(text)),
      );
    }

    return Align(
      alignment: isUser || attachment != null
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        child: dimmed ? Opacity(opacity: 0.55, child: bubble) : bubble,
      ),
    );
  }
}

/// Empty chat: the fanned GitHub link-preview stack (three slightly rotated
/// cards, like the reference). The INTRO is dynamic now (Movement 53) — it
/// plays as real animated bubbles, never as static seeds here.
class EmptyChat extends StatelessWidget {
  const EmptyChat({this.error, this.errorDetails});

  final String? error;
  final String? errorDetails;

  static const List<_PreviewCard> _cards = [
    _PreviewCard(
      title: 'Movement 12: Integration framework + GitHub integration',
      footer: 'GitHub · gork PR #12',
      angle: -0.09,
      lift: 44,
    ),
    _PreviewCard(
      title: 'Movement 19: Gork-style glass UI rebuild',
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
      if (error != null) ...[
        ErrorDetailsCard(summary: error!, details: errorDetails),
        Text(
          'Tip: add a provider key first (Menu → Security → Providers).',
          style: TextStyle(fontSize: 14, color: GlassColors.text),
        ),
      ] else
        Text(
          'Say something below. Your keys stay on this device.',
          style: TextStyle(
              fontSize: 14, color: GlassColors.textDim),
        ),
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

class _DayGroup {
  _DayGroup(this.label, this.messages);

  final String label;
  final List<_UiMessage> messages;
}

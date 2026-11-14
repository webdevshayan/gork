import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';
import 'hark_home.dart';
import 'menu_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'projects_surface.dart';
import 'search_screen.dart';
import '../constants/design_tokens.dart';

enum HarkTab { home, chat, projects }

/// What the + (attachment) menu offers.
enum AttachKind { camera, photos, files }

/// The glass shell, pixel-matched to the reference screenshots:
/// ambient backdrop + top bar (context button / nav pill / avatar) + dynamic
/// body + pinned bottom input. The left button changes per surface
/// (Home = +, Chat = search, Projects/Menu = ☰); the ☰ opens the full
/// profile/menu surface where no tab is selected.
class HarkShell extends StatefulWidget {
  const HarkShell({super.key});

  @override
  State<HarkShell> createState() => _HarkShellState();
}

class _HarkShellState extends State<HarkShell> {
  HarkTab _tab = HarkTab.home;
  bool _onMenu = false;
  bool _attachOpen = false;
  HarkTab _lastCoreTab = HarkTab.home;
  String? _chatConversationId;
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();

  void _selectTab(HarkTab tab) {
    setState(() {
      _tab = tab;
      _onMenu = false;
      _attachOpen = false;
      if (tab != HarkTab.projects) _lastCoreTab = tab;
    });
  }

  void _openMenu() => setState(() {
        _onMenu = true;
        _attachOpen = false;
      });

  void _closeMenu() => setState(() {
        _onMenu = false;
        _tab = _lastCoreTab;
      });

  void _toggleAttach() => setState(() => _attachOpen = !_attachOpen);

  /// Real attachments: Camera / Photos pick an image, Files picks any file.
  /// The content lands in the active conversation (switching to Chat first
  /// when the input is used from Home or Projects). Nothing is uploaded —
  /// paths stay on the device.
  Future<void> _pickAttachment(AttachKind kind) async {
    setState(() => _attachOpen = false);
    try {
      switch (kind) {
        case AttachKind.camera:
        case AttachKind.photos:
          final picked = await ImagePicker().pickImage(
            source: kind == AttachKind.camera
                ? ImageSource.camera
                : ImageSource.gallery,
            maxWidth: 1280,
            imageQuality: 82,
          );
          if (picked == null) return;
          _deliverAttachment(
              (state) => state.attachImage(picked.path, name: picked.name));
        case AttachKind.files:
          final result = await FilePicker.platform.pickFiles(withData: false);
          final file = result?.files.single;
          if (file == null || file.path == null) return;
          _deliverAttachment(
              (state) => state.attachFile(file.path!, file.name));
      }
    } catch (e) {
      debugPrint('attach failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not attach that.')),
        );
      }
    }
  }

  /// Delivers an attachment to the chat thread, entering the Chat tab first
  /// when the input bar was used from Home or Projects.
  void _deliverAttachment(void Function(ChatScreenState) deliver) {
    if (_tab != HarkTab.chat || _onMenu) {
      _selectTab(HarkTab.chat);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = _chatKey.currentState;
        if (state != null) deliver(state);
      });
    } else {
      final state = _chatKey.currentState;
      if (state != null) deliver(state);
    }
  }

  /// The glass input bar works on every tab: submitting from Home/Projects
  /// jumps to Chat and delivers the message to the assistant.
  void _sendFromInput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    setState(() => _attachOpen = false);
    if (_tab != HarkTab.chat || _onMenu) {
      _selectTab(HarkTab.chat);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatKey.currentState?.send(trimmed);
      });
    } else {
      _chatKey.currentState?.send(trimmed);
    }
  }

  /// ONE verb in the top-left: search. Scope follows the tab (home =
  /// everything, chat = the active conversation, projects = projects).
  IconData get _leftIcon {
    if (_onMenu) return Icons.arrow_back_ios_new;
    return Icons.search;
  }

  /// Opens a chat that lives inside a project folder: any pushed workspace
  /// detail is dismissed and the shell switches to the Chat tab carrying
  /// that conversation.
  /// A chat that lives inside a project opens as ITS OWN pushed full-screen
  /// route (with the thread title and a chevron back) — it never collapses
  /// back into the shell's Chat tab.
  void _openProjectChat(String conversationId) {
    Navigator.of(context).push(_slideUpRoute(
      _ChatPage(
        conversationId: conversationId,
        onOpenChat: _openProjectChat,
      ),
    ));
  }

  void _onLeftButton() {
    if (_onMenu) {
      _closeMenu();
      return;
    }
    _openSearch();
  }

  /// The scoped search overlay — slides up from the bottom and covers the
  /// screen (its own backdrop hides the content behind it).
  void _openSearch() {
    final SearchScope scope = switch (_tab) {
      HarkTab.chat => SearchScope.chat,
      HarkTab.projects => SearchScope.projects,
      HarkTab.home => SearchScope.all,
    };
    final String? conversationId = _tab == HarkTab.chat
        ? (_chatConversationId ?? Locator.history.latest?.id)
        : null;
    Navigator.of(context).push(_slideUpRoute(SearchScreen(
      onOpenChat: _openProjectChat,
      initialScope: scope,
      conversationId: conversationId,
    )));
  }

  /// Full-screen overlay route: rises from the bottom edge (ease-out), not
  /// the default Material fade — the search feels like a sheet over the app.
  Route<T> _slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
              parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );

  void _onAvatarTap() {
    if (_onMenu) {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => const _AvatarSheet(),
      );
      return;
    }
    _openMenu();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showInput = !_onMenu;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  tab: _tab,
                  onMenu: _onMenu,
                  leftIcon: _leftIcon,
                  onLeftButton: _onLeftButton,
                  onSelect: _selectTab,
                  onAvatar: _onAvatarTap,
                ),
                Expanded(
                  child: _onMenu
                      ? MenuScreen(
                          onBack: _closeMenu,
                          onOpenChat: _openProjectChat,
                        )
                      : _tab == HarkTab.home
                      ? const HarkHome()
                      : _tab == HarkTab.chat
                      ? ChatScreen(
                          key: _chatKey,
                          // Changing the conversation makes ChatScreen
                          // restore its own thread via didUpdateWidget.
                          conversationId: _chatConversationId,
                          searchOpen: false,
                        )
                      : ProjectsSurface(onOpenChat: _openProjectChat),
                ),
                if (showInput)
                  BottomInputBar(
                    controller: _input,
                    focusNode: _inputFocus,
                    onSend: _sendFromInput,
                    onAttach: _toggleAttach,
                  ),
              ],
            ),
          ),
          if (_attachOpen && !_onMenu)
            Positioned(
              left: 16,
              right: 16,
              bottom: 96,
              child: Align(
                alignment: Alignment.centerRight,
                child: _AttachMenu(
                  onDismiss: _toggleAttach,
                  onPick: _pickAttachment,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.tab,
    required this.onMenu,
    required this.leftIcon,
    required this.onLeftButton,
    required this.onSelect,
    required this.onAvatar,
  });

  final HarkTab tab;
  final bool onMenu;
  final IconData leftIcon;
  final VoidCallback onLeftButton;
  final ValueChanged<HarkTab> onSelect;
  final VoidCallback onAvatar;

  static const List<(String, HarkTab)> _tabs = [
    ('Home', HarkTab.home),
    ('Chat', HarkTab.chat),
    ('Projects', HarkTab.projects),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassIconButton(
            key: const ValueKey('left-button'),
            icon: leftIcon,
            // The label follows the verb: search on core tabs, back on the
            // settings surface.
            semanticLabel: onMenu ? 'Back' : 'Search',
            onTap: onLeftButton,
          ),
          GlassContainer(
            key: const ValueKey('nav-pill'),
            radius: 30,
            opacity: 0.35,
            padding: const EdgeInsets.all(4),
            child: _slidingPill(),
          ),
          const _Avatar(),
        ],
      ),
    );
  }

  double _labelWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 32; // 16px horizontal padding per side
  }

  /// The highlight SLIDES between tabs (AnimatedPositioned) instead of each
  /// chip repainting; the active label is black on the near-white chip.
  Widget _slidingPill() {
    int activeIndex = -1;
    for (var i = 0; i < _tabs.length; i++) {
      if (!onMenu && tab == _tabs[i].$2) activeIndex = i;
    }
    double left = 0;
    for (var i = 0; i < activeIndex; i++) {
      left += _labelWidth(_tabs[i].$1);
    }
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        AnimatedPositioned(
          key: const ValueKey('nav-highlight'),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: activeIndex < 0 ? 0 : left,
          top: 0,
          bottom: 0,
          width: activeIndex < 0
              ? 0
              : _labelWidth(_tabs[activeIndex].$1),
          child: Container(
            decoration: BoxDecoration(
              color: GlassColors.chip,
              borderRadius: BorderRadius.circular(26),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, chipTab) in _tabs)
              Semantics(
                // The pill is a real tab control: button + selected flags
                // so screen readers announce the active tab.
                button: true,
                selected: !onMenu && tab == chipTab,
                child: GestureDetector(
                key: ValueKey('tab-${label.toLowerCase()}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(chipTab),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: !onMenu && tab == chipTab
                        ? GlassColors.textOnChip
                        : GlassColors.textDim,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Text(label),
                  ),
                ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  Widget _fallback() => Container(
        color: GlassColors.text,
        alignment: Alignment.center,
        child: const Icon(Icons.person_outline, size: 24, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: avatarPath,
      builder: (context, path, _) {
        return GestureDetector(
          key: const ValueKey('avatar'),
          behavior: HitTestBehavior.opaque,
          onTap: context
              .findAncestorStateOfType<_HarkShellState>()
              ?._onAvatarTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: ClipOval(
              // No photo provided -> just the icon. Fully offline.
              child: (path == null || path.isEmpty)
                  ? _fallback()
                  : Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Avatar actions (profile tapped while the settings surface is open):
/// choose a real photo from the gallery (stored offline on the device) or
/// remove it — the avatar then falls back to the person icon.
class _AvatarSheet extends StatelessWidget {
  const _AvatarSheet();

  Future<void> _choose(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );
      if (picked == null) return;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/gork-avatar.jpg');
      await file.writeAsBytes(await picked.readAsBytes());
      await Locator.prefs.setString('profile.photoPath', file.path);
      avatarPath.value = file.path;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load that image.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topRight,
          child: GlassContainer(
            radius: 24,
            opacity: 0.65,
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassMenuRow(
                  key: const ValueKey('choose-photo'),
                  icon: Icons.image_outlined,
                  label: 'Choose photo...',
                  trailing: const SizedBox.shrink(),
                  onTap: () {
                    Navigator.pop(context);
                    _choose(context);
                  },
                ),
                Divider(color: GlassColors.divider, height: 1),
                GlassMenuRow(
                  key: const ValueKey('remove-photo'),
                  icon: Icons.delete_outline,
                  label: 'Remove photo',
                  trailing: const SizedBox.shrink(),
                  onTap: () {
                    Navigator.pop(context);
                    Locator.prefs.remove('profile.photoPath');
                    avatarPath.value = null;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile photo removed.')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned glass input bar, pixel-matched: hint "Message Hark", + and mic
/// on the right; the mic becomes a black send circle when there is text.
class BottomInputBar extends StatelessWidget {
  const BottomInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final bool hasText = value.text.trim().isNotEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: GlassContainer(
            key: const ValueKey('input-bar'),
            radius: 30,
            strong: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSend,
                    // The message area auto-resizes with the text instead of
                    // clipping long messages.
                    minLines: 1,
                    maxLines: 6,
                    style: TextStyle(
                      fontSize: 17,
                      color: GlassColors.text,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Message Hark',
                      hintStyle: TextStyle(
                        fontSize: 17,
                        color: GlassColors.textDim,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('attach-button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onAttach,
                  child: Padding(
                    // 14, not 10: this box must match the mic's 52dp box —
                    // the row is END-aligned (bottom-pinned for multi-line),
                    // and a shorter box made the + ride ~4dp below the mic
                    // on a single line.
                    padding: EdgeInsets.all(14),
                    child: Icon(Icons.add, size: 24, color: GlassColors.textDim),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: hasText
                      ? GestureDetector(
                          key: const ValueKey('send-button'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSend(controller.text),
                          child: Container(
                            key: const ValueKey('send-circle'),
                            width: 44,
                            height: 44,
                            margin: const EdgeInsets.fromLTRB(0, 0, 4, 4),
                            decoration: BoxDecoration(
                              // dark theme: light circle, dark arrow.
                              color: GlassColors.text,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_upward,
                              size: 22,
                              color: Colors.black,
                            ),
                          ),
                        )
                      : Padding(
                          key: ValueKey('mic-icon'),
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.mic_none,
                            size: 24,
                            color: GlassColors.textDim,
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
}

/// The + dropdown on Home: add a file, an image, or a new panel — a more
/// opaque glass dropdown right under the left button, like the reference.
class _AttachMenu extends StatelessWidget {
  const _AttachMenu({required this.onDismiss, required this.onPick});

  final VoidCallback onDismiss;
  final ValueChanged<AttachKind> onPick;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      key: const ValueKey('attach-menu'),
      radius: 24,
      opacity: 0.6,
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, Icons.photo_camera_outlined, 'Camera', AttachKind.camera),
          Divider(color: GlassColors.divider, height: 1),
          _row(context, Icons.image_outlined, 'Photos', AttachKind.photos),
          Divider(color: GlassColors.divider, height: 1),
          _row(context, Icons.folder_outlined, 'Files', AttachKind.files),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    AttachKind kind,
  ) {
    return GlassMenuRow(
      icon: icon,
      label: label,
      onTap: () {
        onDismiss();
        onPick(kind);
      },
    );
  }
}
/// A pushed, full-screen chat for conversations that live inside a project:
/// glass top bar (chevron back + thread title) and its own input bar. The
/// page OWNS the ChatScreen state key so the input bar sends to THIS thread.
class _ChatPage extends StatefulWidget {
  const _ChatPage({required this.conversationId, required this.onOpenChat});

  final String conversationId;
  final ValueChanged<String> onOpenChat;

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();

  @override
  Widget build(BuildContext context) {
    final String title =
        Locator.history.byId(widget.conversationId)?.title ?? 'New chat';
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
                        label: 'Back to workspace',
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
                    conversationId: widget.conversationId,
                  ),
                ),
                _ChatPageInputBar(
                  chatKey: _chatKey,
                ),
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


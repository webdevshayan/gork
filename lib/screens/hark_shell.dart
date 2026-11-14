import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/history_store.dart';
import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';
import 'hark_home.dart';
import 'menu_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'chat_home.dart';
import 'chat_page.dart';
import 'projects_surface.dart';
import 'search_screen.dart';
import '../widgets/bottom_input_bar.dart';
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

class _HarkShellState extends State<HarkShell> with WidgetsBindingObserver {
  HarkTab _tab = HarkTab.home;
  bool _onMenu = false;
  bool _attachOpen = false;
  HarkTab _lastCoreTab = HarkTab.home;
  String? _chatConversationId;
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

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
              ChatAttachment('image', picked.path, picked.name));
        case AttachKind.files:
          final result = await FilePicker.platform.pickFiles(withData: false);
          final file = result?.files.single;
          if (file == null || file.path == null) return;
          _deliverAttachment(ChatAttachment('file', file.path!, file.name));
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

  /// An attachment composes a NEW thread full-screen (paths stay on-device;
  /// when the thread belongs to a project folder the page mirrors it there).
  void _deliverAttachment(ChatAttachment attachment) {
    Navigator.of(context).push(_slideUpRoute(
      ChatPage(pendingAttachment: attachment, backLabel: 'Back'),
    ));
  }

  /// The glass input bar composes: submitting opens a NEW thread full-screen
  /// with the message already flying (WhatsApp compose semantics).
  void _sendFromInput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    setState(() => _attachOpen = false);
    Navigator.of(context).push(_slideUpRoute(
      ChatPage(initialMessage: trimmed, backLabel: 'Back'),
    ));
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
  /// route (thread title + chevron back) — it never collapses into a tab.
  void _openProjectChat(String conversationId) {
    setState(() => _chatConversationId = conversationId);
    Navigator.of(context).push(_slideUpRoute(
      ChatPage(conversationId: conversationId, backLabel: 'Back to workspace'),
    ));
  }

  /// A thread tapped on the chat home.
  void _openThread(String conversationId) {
    setState(() => _chatConversationId = conversationId);
    Navigator.of(context).push(_slideUpRoute(
      ChatPage(conversationId: conversationId, backLabel: 'Back to chats'),
    ));
  }

  /// Quick compose from the chat home's input bar.
  void _composeNew(String text) => _sendFromInput(text);

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
  void initState() {
    super.initState();
    // Foreground again → flush pending server-queued messages. Requests the
    // VPS already accepted were never paused or cancelled by app state.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Locator.outbox.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                      ? ChatHome(onOpenChat: _openThread, onCompose: _composeNew)
                      : ProjectsSurface(
                          onOpenChat: _openProjectChat,
                          onAfterPush: () => setState(() {}),
                        ),
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

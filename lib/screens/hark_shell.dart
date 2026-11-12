import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';
import 'hark_home.dart';
import 'menu_screen.dart';
import 'panels_screen.dart';
import 'projects_surface.dart';

enum HarkTab { home, chat, projects }

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
  bool _searchOpen = false;
  bool _attachOpen = false;
  HarkTab _lastCoreTab = HarkTab.home;
  final TextEditingController _input = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();

  void _selectTab(HarkTab tab) {
    setState(() {
      _tab = tab;
      _onMenu = false;
      _searchOpen = false;
      _attachOpen = false;
      if (tab != HarkTab.projects) _lastCoreTab = tab;
    });
  }

  void _openMenu() => setState(() {
        _onMenu = true;
        _searchOpen = false;
        _attachOpen = false;
      });

  void _closeMenu() => setState(() {
        _onMenu = false;
        _tab = _lastCoreTab;
      });

  void _toggleSearch() {
    if (_tab != HarkTab.chat) {
      _selectTab(HarkTab.chat);
    }
    setState(() {
      _searchOpen = !_searchOpen;
      _attachOpen = false;
      if (_searchOpen) {
        _searchCtrl.clear();
        _chatKey.currentState?.search('');
      } else {
        _chatKey.currentState?.search(null);
      }
    });
  }

  void _toggleAttach() => setState(() => _attachOpen = !_attachOpen);

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

  IconData get _leftIcon {
    if (_onMenu) return Icons.segment;
    switch (_tab) {
      case HarkTab.home:
        return Icons.add;
      case HarkTab.chat:
        return Icons.search;
      case HarkTab.projects:
        return Icons.segment;
    }
  }

  void _onLeftButton() {
    if (_onMenu) {
      _closeMenu();
      return;
    }
    switch (_tab) {
      case HarkTab.home:
        // "+" on Home = create a new panel, same as the pill below the card.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PanelsScreen()),
        );
        return;
      case HarkTab.chat:
        _toggleSearch();
        return;
      case HarkTab.projects:
        _openMenu();
        return;
    }
  }

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
    _searchCtrl.dispose();
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
                      ? MenuScreen(onBack: _closeMenu)
                      : _tab == HarkTab.home
                      ? const HarkHome()
                      : _tab == HarkTab.chat
                      ? ChatScreen(
                          key: _chatKey,
                          searchOpen: _searchOpen,
                        )
                      : const ProjectsSurface(),
                ),
                if (showInput)
                  !_searchOpen
                      ? BottomInputBar(
                          controller: _input,
                          focusNode: _inputFocus,
                          onSend: _sendFromInput,
                          onAttach: _toggleAttach,
                        )
                      : _SearchBar(
                          controller: _searchCtrl,
                          onClose: _toggleSearch,
                          onChanged: (q) => _chatKey.currentState?.search(q),
                        ),
              ],
            ),
          ),
          if (_attachOpen && !_searchOpen)
            Positioned(
              left: 16,
              right: 16,
              bottom: 96,
              child: Align(
                alignment: Alignment.centerRight,
                child: _AttachMenu(onDismiss: _toggleAttach),
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassIconButton(key: const ValueKey('left-button'), icon: leftIcon, onTap: onLeftButton),
          GlassContainer(
            key: const ValueKey('nav-pill'),
            radius: 30,
            opacity: 0.35,
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tabChip('Home', HarkTab.home),
                _tabChip('Chat', HarkTab.chat),
                _tabChip('Projects', HarkTab.projects),
              ],
            ),
          ),
          const _Avatar(),
        ],
      ),
    );
  }

  Widget _tabChip(String label, HarkTab chipTab) {
    final bool isSelected = !onMenu && tab == chipTab;
    return GestureDetector(
      key: ValueKey('tab-${label.toLowerCase()}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(chipTab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  static const String _faceUrl =
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e'
      '?auto=format&fit=crop&w=200&q=80';

  Widget _fallback() => Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Text(
          'S',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: photoRemoved,
      builder: (context, removed, _) {
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
              child: removed
                  ? _fallback()
                  : Image.network(
                      _faceUrl,
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

/// Avatar actions on the menu surface: choose / remove the profile photo.
class _AvatarSheet extends StatelessWidget {
  const _AvatarSheet();

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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Photo picker arrives with the attachments movement.',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(color: Colors.black12, height: 1),
                GlassMenuRow(
                  key: const ValueKey('remove-photo'),
                  icon: Icons.delete_outline,
                  label: 'Remove photo',
                  trailing: const SizedBox.shrink(),
                  onTap: () {
                    Navigator.pop(context);
                    Locator.prefs.setBool('profile.photoRemoved', true);
                    photoRemoved.value = true;
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
            opacity: 0.35,
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSend,
                    style: const TextStyle(
                      fontSize: 17,
                      color: Colors.black87,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Message Hark',
                      hintStyle: TextStyle(
                        fontSize: 17,
                        color: Colors.black54,
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
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.add, size: 24, color: Colors.black54),
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
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_upward,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Padding(
                          key: ValueKey('mic-icon'),
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.mic_none,
                            size: 24,
                            color: Colors.black54,
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

/// Search bar replacing the input bar (Chat tab, 🔍): frosted pill with the
/// query + clear button, plus a round close button on the right.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onClose,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: GlassContainer(
              key: const ValueKey('search-bar'),
              radius: 30,
              opacity: 0.45,
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 22, color: Colors.black54),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: onChanged,
                      style: const TextStyle(
                        fontSize: 17,
                        color: Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        hintStyle: TextStyle(
                          fontSize: 17,
                          color: Colors.black54,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        key: const ValueKey('search-clear'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          controller.clear();
                          onChanged('');
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            key: const ValueKey('search-close'),
            icon: Icons.close,
            onTap: () {
              controller.clear();
              onChanged('');
              onClose();
            },
          ),
        ],
      ),
    );
  }
}

/// The + attachment menu from the screenshots: Camera / Photos / Files in a
/// more opaque glass dropdown above the input bar.
class _AttachMenu extends StatelessWidget {
  const _AttachMenu({required this.onDismiss});

  final VoidCallback onDismiss;

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
          _row(context, Icons.photo_camera_outlined, 'Camera'),
          const Divider(color: Colors.black12, height: 1),
          _row(context, Icons.image_outlined, 'Photos'),
          const Divider(color: Colors.black12, height: 1),
          _row(context, Icons.folder_outlined, 'Files'),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label) {
    return GlassMenuRow(
      icon: icon,
      label: label,
      onTap: () {
        onDismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label attachments land in the next movement.')),
        );
      },
    );
  }
}

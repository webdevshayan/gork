import 'dart:io';
import 'dart:ui';

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
  bool _homeMenuOpen = false;
  bool _attachOpen = false;
  HarkTab _lastCoreTab = HarkTab.home;
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final GlobalKey<ChatScreenState> _chatKey = GlobalKey<ChatScreenState>();

  void _selectTab(HarkTab tab) {
    setState(() {
      _tab = tab;
      _onMenu = false;
      _homeMenuOpen = false;
      _attachOpen = false;
      if (tab != HarkTab.projects) _lastCoreTab = tab;
    });
  }

  void _openMenu() => setState(() {
        _onMenu = true;
        _homeMenuOpen = false;
        _attachOpen = false;
      });

  void _closeMenu() => setState(() {
        _onMenu = false;
        _tab = _lastCoreTab;
      });

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
    if (_onMenu) return Icons.arrow_back_ios_new;
    switch (_tab) {
      case HarkTab.home:
        return Icons.add;
      case HarkTab.chat:
        return Icons.settings_outlined;
      case HarkTab.projects:
        return Icons.arrow_back_ios_new;
    }
  }

  /// The left button is contextual: on Home it toggles the add-dropdown,
  /// on Chat it opens the settings surface, on Projects it goes back
  /// (wired into the project hierarchy), and the settings surface itself
  /// gets a plain back button.
  void _onLeftButton() {
    if (_onMenu) {
      _closeMenu();
      return;
    }
    switch (_tab) {
      case HarkTab.home:
        setState(() => _homeMenuOpen = !_homeMenuOpen);
        return;
      case HarkTab.chat:
        _openMenu();
        return;
      case HarkTab.projects:
        // At the projects root there is nothing above to go back to.
        break;
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
                          searchOpen: false,
                        )
                      : const ProjectsSurface(),
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
                child: _AttachMenu(onDismiss: _toggleAttach),
              ),
            ),
          if (_homeMenuOpen && !_onMenu)
            Positioned(
              key: const ValueKey('home-menu-anchor'),
              top: 76,
              left: 16,
              child: _HomeMenu(
                onDismiss: () => setState(() => _homeMenuOpen = false),
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

  Widget _fallback() => Container(
        color: Colors.black87,
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
                const Divider(color: Colors.black12, height: 1),
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
                    // The message area auto-resizes with the text instead of
                    // clipping long messages.
                    minLines: 1,
                    maxLines: 6,
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

/// The + dropdown on Home: add a file, an image, or a new panel — a more
/// opaque glass dropdown right under the left button, like the reference.
class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      key: const ValueKey('home-menu'),
      radius: 24,
      opacity: 0.6,
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, Icons.insert_drive_file_outlined, 'Add file'),
          const Divider(color: Colors.black12, height: 1),
          _row(context, Icons.image_outlined, 'Add image'),
          const Divider(color: Colors.black12, height: 1),
          _row(context, Icons.dashboard_outlined, 'New panel'),
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
        if (label == 'New panel') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PanelsScreen()),
          );
          return;
        }
        // File & image picking land with the project-resources movement.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label attaches inside a project — open one first.',
            ),
          ),
        );
      },
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

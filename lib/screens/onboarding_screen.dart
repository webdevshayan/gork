import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/profile_info.dart';
import '../widgets/ambient_backdrop.dart' show avatarPath;
import '../widgets/g_button.dart';
import '../widgets/screen.dart';
import 'gork_shell.dart';
import 'google_accounts_screen.dart';
import 'providers_screen.dart';

/// First-run onboarding: five pages, then the flag is set forever.
/// Shown by [OnboardingGate] until 'onboarding.done' is true.
///
/// Movement 64 — two new pages:
///   * Google setup, in the order that actually works: the Cloud Console
///     recipe first, then upload credentials, then Connect with Google
///     (the full flow lives on GoogleAccountsScreen — this page just
///     walks there).
///   * Profile: pick a photo, edit the name — the EMAIL is Google's and
///     stays read-only everywhere.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  final TextEditingController _name = TextEditingController();
  int _page = 0;

  static const _pages = 5;

  @override
  void initState() {
    super.initState();
    initProfile();
    _name.text = profileName.value;
  }

  Future<void> _next() async {
    if (_page < _pages - 1) {
      // Leaving the profile page: persist the name the user edited.
      if (_page == 3 && _name.text.trim().isNotEmpty) {
        await saveProfile(name: _name.text.trim(), email: profileEmail.value);
      }
      await _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      if (_name.text.trim().isNotEmpty) {
        await saveProfile(name: _name.text.trim(), email: profileEmail.value);
      }
      await Locator.prefs.setBool('onboarding.done', true);
      widget.onFinished();
    }
  }

  Future<void> _openProviders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProvidersScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openGoogle() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoogleAccountsScreen()),
    );
    if (mounted) setState(() {});
  }

  /// Same mechanism as the shell's avatar sheet: a fresh, uniquely-named
  /// file per upload (busts ImageCache), the old one deleted right after.
  Future<void> _choosePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );
      if (picked == null) return;
      final dir = await getApplicationSupportDirectory();
      final file = File(
          '${dir.path}/gork-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(await picked.readAsBytes());
      final String? old = Locator.prefs.getString('profile.photoPath');
      if (old != null && old != file.path) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
      await Locator.prefs.setString('profile.photoPath', file.path);
      avatarPath.value = file.path;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load that image.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (i, page) in [
                  _welcome(palette),
                  _setup(palette),
                  _google(palette),
                  _profile(palette),
                  _done(palette),
                ].indexed)
                  _PageEntrance(
                    key: ValueKey('onboard-page-$i'),
                    child: page,
                  ),
              ],
            ),
          ),
          // Movement 69 — animated progress dots: the active dot stretches,
          // the rest stay round. You always know where you are.
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages; i++)
                  AnimatedContainer(
                    key: ValueKey('onboard-dot-$i'),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? palette.textPrimary
                          : palette.textTertiary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                if (_page > 0)
                  Expanded(
                    child: GButton(
                      label: 'Back',
                      variant: ButtonVariant.ghost,
                      onPressed: () => _controller.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      expands: true,
                    ),
                  ),
                if (_page > 0) const SizedBox(width: Spacing.sm),
                Expanded(
                  child: GButton(
                    label: _page == _pages - 1 ? 'Start using gork' : 'Next',
                    onPressed: _next,
                    expands: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome(Palette palette) => Padding(
    padding: const EdgeInsets.all(Spacing.xl),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('gork', style: TypeScale.display(color: palette.textPrimary)),
        const SizedBox(height: Spacing.md),
        Text(
          'Your personal AI assistant. Bring your own key — '
          'everything stays on your phone.',
          style: TypeScale.body(color: palette.textSecondary),
        ),
          ],
        ),
      ),
    ),
  );

  Widget _setup(Palette palette) => Padding(
    padding: const EdgeInsets.all(Spacing.xl),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect a provider',
          style: TypeScale.title(color: palette.textPrimary),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'Pick OpenAI, OpenRouter, Gemini, Anthropic or your own '
          'OpenAI-compatible endpoint, and paste your API key. '
          'Keys are encrypted on this device only.',
          style: TypeScale.body(color: palette.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'You can also connect GitHub, Slack, Strava, Spotify, Gmail '
          'and PayPal later from Integrations.',
          style: TypeScale.bodySmall(color: palette.textTertiary),
        ),
        const SizedBox(height: Spacing.lg),
        GButton(
          label: 'Open Providers',
          variant: ButtonVariant.secondary,
          onPressed: _openProviders,
          expands: true,
        ),
          ],
        ),
      ),
    ),
  );

  /// Google setup in the ORDER that works: the Cloud Console recipe →
  /// upload credentials → Connect with Google. The full flow (with the
  /// upload button and the exact redirect URI) lives one tap away.
  Widget _google(Palette palette) => Padding(
    padding: const EdgeInsets.all(Spacing.xl),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Google, on your server',
          style: TypeScale.title(color: palette.textPrimary),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'One tap signs you in and connects Gmail, Docs and YouTube at '
          'once — the login runs on YOUR server. Three steps, in order:',
          style: TypeScale.body(color: palette.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        for (final (i, step) in const [
          'Set your VPS address once in Cloud Computer (it can even run '
              'on this phone — http://127.0.0.1:8787).',
          'Create the Cloud Console OAuth client and upload its '
              'credentials.json — the guide is on the Google screen.',
          'Connect with Google — consent once in your browser.',
        ].indexed) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}.',
                    style: TypeScale.bodySmall(
                        color: palette.textPrimary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(step,
                      style: TypeScale.bodySmall(
                          color: palette.textSecondary)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        GButton(
          label: 'Open Google setup',
          variant: ButtonVariant.secondary,
          onPressed: _openGoogle,
          expands: true,
        ),
          ],
        ),
      ),
    ),
  );

  /// Profile: the photo and the name are YOURS; the email comes from
  /// Google and is read-only everywhere (sign in once and it fills in).
  Widget _profile(Palette palette) => Padding(
    padding: const EdgeInsets.all(Spacing.xl),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This is you',
          style: TypeScale.title(color: palette.textPrimary),
        ),
        const SizedBox(height: Spacing.lg),
        Center(
          child: ValueListenableBuilder<String?>(
            valueListenable: avatarPath,
            builder: (context, path, _) {
              final fallback = CircleAvatar(
                radius: 44,
                backgroundColor: palette.textTertiary.withValues(alpha: 0.3),
                child: Icon(Icons.person_outline,
                    size: 40, color: palette.textSecondary),
              );
              return GestureDetector(
                key: const ValueKey('onboarding-avatar'),
                onTap: _choosePhoto,
                child: Stack(
                  children: [
                    (path == null)
                        ? fallback
                        : CircleAvatar(
                            radius: 44,
                            backgroundImage: FileImage(File(path)),
                          ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: palette.textPrimary,
                        child: Icon(Icons.camera_alt_outlined,
                            size: 16, color: palette.background),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Spacing.lg),
        TextField(
          key: const ValueKey('onboarding-name'),
          controller: _name,
          style: TypeScale.body(color: palette.textPrimary),
          decoration: InputDecoration(
            labelText: 'Your name',
            labelStyle: TypeScale.bodySmall(color: palette.textTertiary),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: Spacing.md),
        ValueListenableBuilder<String>(
          valueListenable: profileEmail,
          builder: (context, email, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('onboarding-email'),
                  controller: TextEditingController(text: email),
                  readOnly: true,
                  enabled: false,
                  style: TypeScale.body(color: palette.textSecondary),
                  decoration: InputDecoration(
                    labelText: 'Email (from Google)',
                    labelStyle:
                        TypeScale.bodySmall(color: palette.textTertiary),
                    border: const OutlineInputBorder(),
                    suffixIcon: Icon(Icons.lock_outline,
                        size: 18, color: palette.textTertiary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The email is read-only — connect Google and it fills in '
                  'automatically. The name stays yours to edit.',
                  style: TypeScale.bodySmall(color: palette.textTertiary),
                ),
              ],
            );
          },
        ),
          ],
        ),
      ),
    ),
  );

  Widget _done(Palette palette) => Padding(
    padding: const EdgeInsets.all(Spacing.xl),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You are set', style: TypeScale.title(color: palette.textPrimary)),
        const SizedBox(height: Spacing.md),
        Text(
          'Chat, Projects, Tasks, Panels, Inbox and Cloud Computer '
          'are all on the home screen. gork works 24/7 when you '
          'connect the companion daemon.',
          style: TypeScale.body(color: palette.textSecondary),
        ),
          ],
        ),
      ),
    ),
  );
}

/// Decides between onboarding and home based on the saved flag.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late bool _done = Locator.prefs.getBool('onboarding.done') ?? false;

  @override
  Widget build(BuildContext context) {
    // Non-const — same reason as the home: in app.dart. A const shell is
    // skipped on ancestor rebuilds and never re-reads GlassColors.
    if (_done) return GorkShell();
    return OnboardingScreen(onFinished: () => setState(() => _done = true));
  }
}

/// Movement 69 — every onboarding page ENTERS: fades in, rises and settles
/// with a soft overshoot. Re-keyed per page so swiping back and forth
/// replays it — the setup feels alive instead of snapping.
class _PageEntrance extends StatefulWidget {
  const _PageEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<_PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<_PageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.10),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../widgets/g_button.dart';
import '../widgets/screen.dart';
import 'home_screen.dart';
import 'providers_screen.dart';

/// First-run onboarding: three pages, then the flag is set forever.
/// Shown by [OnboardingGate] until 'onboarding.done' is true.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = 3;

  Future<void> _next() async {
    if (_page < _pages - 1) {
      await _controller.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      await Locator.prefs.setBool('onboarding.done', true);
      widget.onFinished();
    }
  }

  Future<void> _openProviders() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ProvidersScreen()));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
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
                _welcome(palette),
                _setup(palette),
                _done(palette),
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
                          curve: Curves.easeOut),
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
      );

  Widget _setup(Palette palette) => Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect a provider',
                style: TypeScale.title(color: palette.textPrimary)),
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
      );

  Widget _done(Palette palette) => Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are set',
                style: TypeScale.title(color: palette.textPrimary)),
            const SizedBox(height: Spacing.md),
            Text(
              'Chat, Projects, Tasks, Panels, Inbox and Cloud Computer '
              'are all on the home screen. gork works 24/7 when you '
              'connect the companion daemon.',
              style: TypeScale.body(color: palette.textSecondary),
            ),
          ],
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
  late bool _done =
      Locator.prefs.getBool('onboarding.done') ?? false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const HomeScreen();
    return OnboardingScreen(
      onFinished: () => setState(() => _done = true),
    );
  }
}

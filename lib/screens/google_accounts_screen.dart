import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/google_accounts.dart';
import '../services/google_oauth_service.dart';
import '../services/integrations.dart';
import 'package:file_picker/file_picker.dart';

import '../services/credential_uploader.dart';
import '../services/locator.dart';
import '../services/profile_info.dart';
import 'cloud_computer_screen.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/g_button.dart';
import '../widgets/glass.dart';

/// Account selection: every connected Google account, the active one
/// marked. One tap on an account = one click that binds ALL Google
/// services to it.
///
/// Movement 62 — accounts connect with ONE TAP: the user's VPS is the
/// login server (its sealed credentials.json is the OAuth client); the
/// consent page opens in the browser once and covers every tool — Gmail,
/// Docs, YouTube — and the refresh token is sealed on the VPS. Pasting a
/// token by hand stays available as "Add manually".
class GoogleAccountsScreen extends StatefulWidget {
  const GoogleAccountsScreen(
      {super.key, this.store, this.report, this.uploader, this.oauth});

  /// Injectable for tests; defaults to the keystore-backed store.
  final GoogleAccountStore? store;
  final void Function(String summary)? report;

  /// Injectable for tests; defaults to the keystore-backed uploader.
  final GoogleCredentialsUploader? uploader;

  /// Injectable for tests; defaults to the VPS-backed OAuth service.
  final GoogleOAuthService? oauth;

  @override
  State<GoogleAccountsScreen> createState() =>
      _GoogleAccountsScreenState();
}

class _GoogleAccountsScreenState extends State<GoogleAccountsScreen> {
  List<GoogleAccount> _legacyAccounts = const [];
  List<Map<String, dynamic>> _vpsAccounts = const [];
  String? _activeEmail;
  bool _connecting = false;
  bool _oauthBusy = false;
  String? _oauthStatus;
  bool? _credsOnVps;

  GoogleCredentialsUploader get _uploader =>
      widget.uploader ?? GoogleCredentialsUploader();

  GoogleOAuthService get _oauth =>
      widget.oauth ?? GoogleOAuthService();

  GoogleAccountStore get _store =>
      widget.store ??
      GoogleAccountStore(
        store: Locator.store,
        verifier: GoogleAccountStore.gmailVerifier,
        vault: IntegrationVault(Locator.store),
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _store.accounts().then((a) async {
      if (!mounted) return;
      setState(() => _legacyAccounts = a);
      _activeEmail = (await _store.active())?.email;
      if (mounted) setState(() {});
    });
    if (_oauth.configured) {
      _oauth.accounts().then((a) {
        if (mounted) setState(() => _vpsAccounts = a);
      });
    }
    if (_uploader.configured) {
      _uploader.hasCredentials().then((v) {
        if (mounted) setState(() => _credsOnVps = v);
      });
    } else {
      _credsOnVps = null;
    }
  }

  /// THE one-tap connect: consent in the browser once, every tool bound,
  /// refresh token sealed on the VPS. No token pasting, no playground.
  ///
  /// Movement 65 — the loopback flow is tried first (it needs nothing but
  /// the already-registered redirect URI). If the browser never called back
  /// — Android killed the process while it was fullscreen, the classic "I
  /// signed in and NOTHING happened" — the user is offered the deep-link
  /// flow, which survives process death.
  Future<void> _connectWithGoogle() => _connectFlow(deepLink: false);

  Future<void> _connectFlow({required bool deepLink}) async {
    setState(() {
      _oauthBusy = true;
      _oauthStatus = deepLink
          ? 'Waiting for Google to send you back into the app…'
          : 'Opening the Google sign-in…';
    });
    try {
      final account = deepLink
          ? await _oauth.connectViaDeepLink()
          : await _oauth.connect();
      if (!mounted) return;
      await _handleConnected(account);
    } catch (e) {
      if (!mounted) return;
      final message = e
          .toString()
          .replaceFirst(RegExp(r'^(StateError|Bad state):\s*'), '')
          .replaceFirst(RegExp(r'^(Exception|IntegrationException):\s*'), '');
      setState(() {
        _oauthBusy = false;
        _oauthStatus = null;
      });
      // The deep-link rescue applies only when the loopback attempt got as
      // far as the browser (not a config problem, not a user cancel).
      final rescueable = !deepLink &&
          !message.contains('cancelled') &&
          !message.contains('No VPS') &&
          !message.contains('no credentials.json');
      if (rescueable) {
        await _offerDeepLinkRescue(message);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  /// Success path shared by both redirect flows: seed the profile from the
  /// Google identity (Movement 64) and announce the tools that landed.
  Future<void> _handleConnected(Map<String, dynamic> account) async {
    final tools = (account['tools'] as List?)?.join(', ') ?? 'none';
    final summary =
        'Connected ${account['name']} (${account['email']}) — $tools';
    // Movement 64 — the Google identity seeds the profile: the email is
    // Google's (read-only everywhere), the name pre-fills and stays
    // editable on the profile pages.
    await saveProfile(
      name: (account['name'] as String?) ?? profileName.value,
      email: (account['email'] as String?) ?? profileEmail.value,
    );
    widget.report?.call(summary);
    setState(() {
      _oauthBusy = false;
      _oauthStatus = null;
    });
    _reload();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(summary)));
  }

  /// The "signed in, never came back" rescue: explain WHY (Android killed
  /// the app while the browser was open), name the one Console edit, and
  /// offer the deep-link flow that survives it.
  Future<void> _offerDeepLinkRescue(String message) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GlassColors.fill,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
        ),
        title: Text('The sign-in never came back',
            style: TextStyle(color: GlassColors.text)),
        content: Text(
          '$message\n\n'
          'This happens when Android closes gork while the browser is '
          'open — the sign-in listener died with it. The deep-link '
          'redirect survives: Google hands the code straight to the app.\n\n'
          'One-time, if not done yet — Cloud Console → Credentials → your '
          'OAuth client → Authorized redirect URIs, add exactly:\n'
          '${GoogleOAuthService.kDeepLinkUri}',
          style: TextStyle(height: 1.4, color: GlassColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Close',
                style: TextStyle(color: GlassColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Sign in with deep link',
                style: TextStyle(color: GlassColors.text)),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await _connectFlow(deepLink: true);
    }
  }

  /// The Cloud Console credentials JSON travels to the VPS vault exactly
  /// once; nothing is ever read back (status boolean only).
  ///
  /// Movement 56: the picker used FileType.custom + ['json'], which filters
  /// by MIME. Files downloaded from a browser often carry
  /// application/octet-stream, so the system document picker hid them and
  /// "no file could be uploaded". Pick ANY file, then validate the
  /// extension here in Dart.
  /// Movement 59 (screenshot bug): with no VPS configured this used to
  /// open the picker, upload nothing, and surface the raw exception
  /// ("Upload failed: Bad state: …"). Now the VPS is checked FIRST and the
  /// user is offered a direct jump to the Security screen; remaining
  /// failures speak human, not Dart.
  Future<void> _uploadCredentials() async {
    if (!_uploader.configured) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: GlassColors.fill,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RadiusTokens.lg),
          ),
          title: Text('Set up your VPS first',
              style: TextStyle(color: GlassColors.text)),
          content: Text(
            'Credentials are sealed on your VPS, so gork needs the VPS '
            'address before it can store anything. One address and one '
            'secret in Cloud Computer unlock this upload — and chat, '
            'tasks and the vault too.',
            style: TextStyle(color: GlassColors.textDim),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Not now',
                  style: TextStyle(color: GlassColors.textDim)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Set up the VPS',
                  style: TextStyle(color: GlassColors.text)),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudComputerScreen()),
        );
      }
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(withData: false);
      if (picked == null || picked.files.single.path == null) return;
      final file = picked.files.single;
      if (!file.name.toLowerCase().endsWith('.json')) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(
              'That is not a .json file — pick the credentials file '
              'downloaded from Google Cloud Console.')));
        return;
      }
      await _uploader.upload(file.path!);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content:
            Text('Credentials sealed on the VPS — never read back, only a status.')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      // Speak human: strip Dart's exception prefixes and translate the
      // known cases; anything else shows the message without "Bad state:".
      String message;
      final text = e.toString();
      if (text.contains('SocketException') || text.contains('ClientException')) {
        message = 'Could not reach the VPS — check the address in Cloud '
            'Computer and your connection.';
      } else if (text.contains('the VPS refused the upload')) {
        // Movement 61: an old daemon 404s the credentials endpoint — name
        // the one-command fix instead of a vague "make sure it is up to
        // date". The update preserves config, keys, tasks and the vault.
        message = 'The VPS daemon is older than this app or not running. '
            'On the VPS run: gork daemon update — your API keys, tasks and '
            'vault are kept — then try again.';
      } else {
        message = text
            .replaceFirst(RegExp(r'^Bad state:\s*'), '')
            .replaceFirst(RegExp(r'^Invalid argument(\([^)]*\))?:\s*'), '');
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// THE one click: active account + every Google service bound.
  Future<void> _connect(GoogleAccount acct) async {
    setState(() => _connecting = true);
    try {
      final connected = await _store.connectAll(acct.email);
      setState(() => _activeEmail = acct.email);
      final summary =
          'Connected ${connected.join(', ')} via ${acct.email}';
      widget.report?.call(summary);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(summary)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Connect failed: $e')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _addAccount() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GlassColors.fillStrong,
        title: Text('Add Google account',
            style: TextStyle(color: GlassColors.text)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: GlassColors.text),
          decoration: InputDecoration(
            hintText: 'paste the OAuth access token',
            hintStyle: TextStyle(color: GlassColors.textFaint),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final acct = await _store.addAccount(controller.text.trim());
      setState(_reload);
      await _connect(acct);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('Could not add account: $e')));
    }
  }

  /// The accounts card: VPS-connected accounts first (name + email + the
  /// tools their consent covers), then legacy paste-token accounts.
  Widget _buildAccountsCard() {
    if (_vpsAccounts.isNotEmpty) {
      return GlassContainer(
        radius: 28,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < _vpsAccounts.length; i++) ...[
              if (i > 0) Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: ValueKey('vps-account-${_vpsAccounts[i]['email']}'),
                icon: Icons.verified_user_outlined,
                label: '${_vpsAccounts[i]['name']} · ${_vpsAccounts[i]['email']}',
                trailing: _toolChips(_vpsAccounts[i]['tools'] as List? ?? const []),
                onTap: null,
              ),
            ],
          ],
        ),
      );
    }
    if (_legacyAccounts.isNotEmpty) {
      return GlassContainer(
        radius: 28,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < _legacyAccounts.length; i++) ...[
              if (i > 0) Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: ValueKey('account-${_legacyAccounts[i].email}'),
                icon: _legacyAccounts[i].email == _activeEmail
                    ? Icons.verified_user_outlined
                    : Icons.account_circle_outlined,
                label: _legacyAccounts[i].email,
                trailing: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : GlassRadio(
                        selected: _legacyAccounts[i].email == _activeEmail),
                onTap: () => _connect(_legacyAccounts[i]),
              ),
            ],
          ],
        ),
      );
    }
    return GlassContainer(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Text(
        'No Google account connected yet. One tap below signs you in — '
        'it connects Gmail, Docs and YouTube at once, and the login runs '
        'on YOUR server.',
        style: TextStyle(fontSize: 14, color: GlassColors.textDim),
      ),
    );
  }

  /// The tool chips: Gmail / Docs / YouTube — read from the consented
  /// scopes; a tool is only "connected" when Google granted it.
  Widget _toolChips(List<dynamic> tools) {
    if (tools.isEmpty) {
      return const SizedBox(width: 0, height: 0);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        for (final tool in tools)
          Container(
            key: ValueKey('tool-$tool'),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GlassColors.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tool.toString().toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: GlassColors.textOnChip),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  children: [
                    GlassBackButton(
                      key: const ValueKey('google-back'),
                      label: 'Back',
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Google',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: GlassColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'One account, every Google service. Tap an account to '
                  'connect it everywhere.',
                  style: TextStyle(fontSize: 14, color: GlassColors.textDim),
                ),
                const SizedBox(height: 24),
                _buildAccountsCard(),
                const SizedBox(height: 16),

                // Movement 64 — the setup ORDER matches reality: FIRST the
                // step-by-step Cloud Console guide, THEN the upload button,
                // and only then Connect with Google. The consent request
                // needs those credentials AND the one registered redirect
                // URI — asking the user to connect before any of that
                // existed just produced Google's 400 redirect_uri_mismatch.
                _buildCloudConsoleCard(),
                const SizedBox(height: 16),
                GButton(
                  key: const ValueKey('google-connect'),
                  label: _oauthBusy ? 'Waiting for Google…' : 'Connect with Google',
                  onPressed: _oauthBusy ? null : _connectWithGoogle,
                  expands: true,
                ),
                if (_oauthStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _oauthStatus!,
                    key: const ValueKey('google-oauth-status'),
                    style: TextStyle(
                        fontSize: 13, color: GlassColors.textDim),
                  ),
                ],
                const SizedBox(height: 16),
                GButton(
                  key: const ValueKey('google-add'),
                  label: 'Add manually',
                  onPressed: _addAccount,
                  variant: ButtonVariant.secondary,
                  expands: true,
                ),

                const SizedBox(height: 8),
                Text(
                  'One-time setup — it stays connected until you remove it. '
                  'The sign-in token is sealed on your VPS; connector tokens '
                  'stay encrypted on this device.',
                  style: TextStyle(fontSize: 12, color: GlassColors.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The Google Cloud Console card: the exact recipe to CREATE the
  /// credentials (before there is anything to upload), the upload action,
  /// and the one redirect URI to register. Movement 64.
  Widget _buildCloudConsoleCard() {
    return GlassContainer(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Google Cloud Console',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: GlassColors.text)),
          const SizedBox(height: 4),
          Text(
            'First time? Create the credentials Google signs in against — '
            'once, then upload them here.',
            style: TextStyle(fontSize: 13, color: GlassColors.textDim),
          ),
          const SizedBox(height: 10),
          for (final (i, step) in const [
            'console.cloud.google.com → create a project (any name).',
            'APIs & Services → Library → enable Gmail, Google Docs '
                'and YouTube Data API.',
            'OAuth consent screen → External → add your own account '
                'under Test users.',
            'Credentials → Create credentials → OAuth client ID → '
                'Web application.',
            'Authorized redirect URIs — BOTH, exactly: '
                '${GoogleOAuthService.kRedirectUri} and '
                '${GoogleOAuthService.kDeepLinkUri}',
            'Download the JSON and upload it below.',
          ].indexed) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: GlassColors.chip,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: GlassColors.textOnChip)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(step,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: GlassColors.textDim)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            key: const ValueKey('gconsole-upload'),
            behavior: HitTestBehavior.opaque,
            onTap: _uploadCredentials,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text('Upload credentials.json',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
          if (_credsOnVps != null) ...[
            const SizedBox(height: 8),
            Text(
              _credsOnVps!
                  ? 'Credentials sealed on the VPS ✓ — Connect with Google below.'
                  : 'No credentials stored yet — upload before connecting.',
              key: const ValueKey('gconsole-status'),
              style: TextStyle(
                  fontSize: 13,
                  color: _credsOnVps!
                      ? GlassColors.text
                      : GlassColors.textDim),
            ),
          ],
        ],
      ),
    );
  }
}

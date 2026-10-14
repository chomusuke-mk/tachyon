import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/utils/permission_utils.dart';

/// Shows [child] once every required permission is granted. Until then it
/// displays a simple screen to request them. When permissions transition from
/// missing to granted, the default music folder is registered (only if the
/// folder list was never set) and the library is scanned.
class PermissionsGate extends StatefulWidget {
  final Widget child;
  final bool initiallyGranted;

  const PermissionsGate({
    super.key,
    required this.child,
    this.initiallyGranted = true,
  });

  @override
  State<PermissionsGate> createState() => _PermissionsGateState();
}

class _PermissionsGateState extends State<PermissionsGate>
    with WidgetsBindingObserver {
  late bool _allGranted = widget.initiallyGranted;
  final Map<AppPermission, bool> _granted = {};
  final Map<AppPermission, bool> _permanentlyDenied = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_allGranted) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_allGranted) _refresh();
  }

  Future<void> _refresh() async {
    for (final permission in AppPermission.values) {
      _granted[permission] = await PermissionUtils.isGranted(permission);
      _permanentlyDenied[permission] = !_granted[permission]!
          ? await PermissionUtils.isPermanentlyDenied(permission)
          : false;
    }
    if (!mounted) return;
    if (_granted.values.every((g) => g)) {
      await _onAllGranted();
    } else {
      setState(() {});
    }
  }

  Future<void> _onAllGranted() async {
    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    await settings.ensureDefaultMusicDirectory();
    if (!mounted) return;
    setState(() => _allGranted = true);
    library.loadLibrary(autoScan: true);
  }

  Future<void> _onAction(AppPermission permission) async {
    if (_busy) return;
    _busy = true;
    try {
      if (_permanentlyDenied[permission] ?? false) {
        await PermissionUtils.openSettings();
      } else {
        await PermissionUtils.request(permission);
        await _refresh();
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allGranted) return widget.child;

    final strings = context.watch<LocaleController>().localeStrings;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer,
                          scheme.tertiaryContainer,
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.library_music_rounded,
                      size: 44,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    strings.permTitle,
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.permSubtitle,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _PermissionCard(
                    icon: Icons.audio_file_rounded,
                    title: strings.permMusicTitle,
                    description: strings.permMusicDesc,
                    granted: _granted[AppPermission.music] ?? false,
                    permanentlyDenied:
                        _permanentlyDenied[AppPermission.music] ?? false,
                    onPressed: () => _onAction(AppPermission.music),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool permanentlyDenied;
  final VoidCallback onPressed;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.permanentlyDenied,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: granted
              ? scheme.primary.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (permanentlyDenied && !granted) ...[
              const SizedBox(height: 10),
              Text(
                strings.permDeniedHint,
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: granted
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strings.permGranted,
                          style: textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    )
                  : FilledButton.tonal(
                      onPressed: onPressed,
                      child: Text(
                        permanentlyDenied
                            ? strings.permOpenSettings
                            : strings.permGrantAccess,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

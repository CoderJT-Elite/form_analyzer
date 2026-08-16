import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_colors.dart';
import '../../core/app_constants.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';

class ProfileScreen extends StatefulWidget {
  // Accepted for symmetry with the other tabs (MainNavigationWrapper passes
  // the same callback to all four); unused here since the big avatar below
  // already makes this the profile screen — a second one in the header would
  // just duplicate it.
  final VoidCallback? onProfileTap;

  const ProfileScreen({super.key, this.onProfileTap});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final StorageService _storageService = StorageService();
  List<WorkoutSession>? _sessions;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _voiceCoachingEnabled = true;
  bool _hapticFeedbackEnabled = true;
  String? _profilePicturePath;
  bool _isTakingPhoto = false;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _storageService.loadSessions();
      final voiceEnabled = await _storageService.isVoiceCoachingEnabled();
      final hapticsEnabled = await _storageService.isHapticFeedbackEnabled();
      final picturePath = await _storageService.getProfilePicturePath();
      final displayName = await _storageService.getDisplayName();
      setState(() {
        _sessions = data;
        _voiceCoachingEnabled = voiceEnabled;
        _hapticFeedbackEnabled = hapticsEnabled;
        _profilePicturePath = picturePath;
        _displayName = displayName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    // Everything is stored on-device, so this is a genuine local reload.
    // It used to sit behind an 1800ms delay labelled "simulate secure network
    // sync", which was theatre — there is no network and never was.
    HapticFeedback.mediumImpact();
    setState(() => _isSyncing = true);
    await _loadData();
    if (mounted) setState(() => _isSyncing = false);
    HapticFeedback.lightImpact();
  }

  int get _totalReps =>
      _sessions?.fold<int>(0, (s, e) => s + e.totalReps) ?? 0;
  int get _totalSessions => _sessions?.length ?? 0;
  double get _avgForm {
    final ratings = (_sessions ?? [])
        .where((s) => s.overallRating != null)
        .map((s) => s.overallRating!)
        .toList();
    if (ratings.isEmpty) return 0;
    return ratings.reduce((a, b) => a + b) / ratings.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        backgroundColor: AppColors.surface,
        color: AppColors.accentCyan,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR PROFILE',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PROFILE',
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(80),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentCyan,
                      ),
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      // The floating blurred nav bar sits on top of this
                      // scroll view (extendBody: true). 60 wasn't enough to
                      // clear its own height plus the device's safe-area
                      // inset, so the last row was stuck half-hidden behind
                      // it with no way to scroll further.
                      MediaQuery.paddingOf(context).bottom + 100,
                    ),
                    child: Column(
                      children: [
                        _buildAvatarSection(),
                        const SizedBox(height: 32),
                        _buildLifetimeStats(),
                        const SizedBox(height: 32),
                        _buildSettingsList(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    // No accounts, so no email here — just a photo and name the user can set
    // themselves (stored on-device only, like everything else) and the
    // testing-status badge.
    final hasPhoto = _profilePicturePath != null;

    return Column(
      children: [
        GestureDetector(
          onTap: _isTakingPhoto ? null : _takeProfilePhoto,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accentCyan,
                      AppColors.accentMagenta,
                    ],
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.surface,
                    backgroundImage: hasPhoto
                        ? FileImage(File(_profilePicturePath!))
                        : null,
                    child: hasPhoto
                        ? null
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Image.asset(
                              'assets/icons/avatar_placeholder.png',
                            ),
                          ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.accentCyan,
                  shape: BoxShape.circle,
                ),
                child: _isTakingPhoto
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt_rounded,
                        size: 14,
                        color: Colors.black,
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _editDisplayName,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _displayName ?? 'ADD YOUR NAME',
                style: GoogleFonts.outfit(
                  color: _displayName != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.edit_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentCyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.accentCyan.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSyncing) ...[
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentCyan,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'SYNCING...',
                  style: GoogleFonts.outfit(
                    color: AppColors.accentCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ] else
                Text(
                  'BETA TESTER',
                  style: GoogleFonts.outfit(
                    color: AppColors.accentCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLifetimeStats() {
    return Column(
      children: [
        const SectionLabel(text: 'LIFETIME STATS'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.accentCyan,
                      size: 18,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _totalSessions.toString(),
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      'WORKOUTS',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      color: AppColors.accentMagenta,
                      size: 18,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _totalReps.toString(),
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      'TOTAL REPS',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: AppColors.accentGold,
                      size: 18,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _avgForm > 0
                          ? _avgForm.toStringAsFixed(1)
                          : '--',
                      style: GoogleFonts.outfit(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      'AVG FORM',
                      style: GoogleFonts.outfit(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsList() {
    // Every row here does something. These used to be three decorative rows
    // with an empty onTap, including a "Privacy & Security" entry that led
    // nowhere even though a privacy policy was already published.
    final items = <(IconData, String, Future<void> Function())>[
      (Icons.ios_share_rounded, 'Back Up My Data', _exportData),
      (Icons.download_rounded, 'Restore From Backup', _importData),
      (Icons.security_rounded, 'Privacy Policy', _openPrivacyPolicy),
      (Icons.health_and_safety_outlined, 'Health & Safety', _showDisclaimer),
    ];

    return Column(
      children: [
        const SectionLabel(text: 'SETTINGS'),
        const SizedBox(height: 16),
        _buildToggleSetting(
          icon: Icons.record_voice_over_rounded,
          title: 'Voice Coaching',
          value: _voiceCoachingEnabled,
          onChanged: (value) async {
            await _storageService.setVoiceCoachingEnabled(value);
            if (mounted) setState(() => _voiceCoachingEnabled = value);
          },
        ),
        _buildToggleSetting(
          icon: Icons.vibration_rounded,
          title: 'Haptic Feedback',
          value: _hapticFeedbackEnabled,
          onChanged: (value) async {
            await _storageService.setHapticFeedbackEnabled(value);
            if (mounted) setState(() => _hapticFeedbackEnabled = value);
          },
        ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              onTap: () => unawaited(item.$3()),
              child: Row(
                children: [
                  Icon(item.$1, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 16),
                  Text(
                    item.$2,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Write the user's data to a file and hand it to the system share sheet.
  Future<void> _exportData() async {
    try {
      final json = await _storageService.exportToJson();
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${directory.path}/form-analyzer-backup-$stamp.json');
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: ['form-analyzer-backup-$stamp.json'],
          subject: 'Form Analyzer backup',
        ),
      );
    } catch (e) {
      _showMessage('Could not create a backup: $e');
    }
  }

  /// Pick a previously exported file and merge it back in.
  Future<void> _importData() async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose a Form Analyzer backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty) return;

      final file = picked.first;
      final contents = utf8.decode(await file.readAsBytes());

      final result = await _storageService.importFromJson(contents);
      await _loadData();
      _showMessage(result.summary);
    } on FormatException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Could not restore that file: $e');
    }
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(
          'Your Name',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: GoogleFonts.inter(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. Jordan'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (result == null) return;

    final trimmed = result.trim();
    await _storageService.setDisplayName(trimmed.isEmpty ? null : trimmed);
    if (mounted) {
      setState(() => _displayName = trimmed.isEmpty ? null : trimmed);
    }
  }

  /// Opens the front camera for a selfie and saves it as the local profile
  /// photo. Copied into app storage under a fixed name so retaking overwrites
  /// the old one instead of accumulating files.
  Future<void> _takeProfilePhoto() async {
    setState(() => _isTakingPhoto = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final savedPath = '${directory.path}/profile_picture.jpg';
      await File(picked.path).copy(savedPath);

      // Retaking a photo overwrites the same path, but FileImage caches by
      // path, not file content — without this, both the header avatar and
      // this screen keep showing the old bytes until the app restarts.
      PaintingBinding.instance.imageCache.evict(FileImage(File(savedPath)));

      await _storageService.setProfilePicturePath(savedPath);
      if (mounted) setState(() => _profilePicturePath = savedPath);
    } catch (e) {
      _showMessage('Could not take a photo: $e');
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(AppConstants.privacyPolicyUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showMessage('Could not open ${AppConstants.privacyPolicyUrl}');
    }
  }

  Future<void> _showDisclaimer() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(
          'Health & Safety',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          AppConstants.healthDisclaimer,
          style: GoogleFonts.inter(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildToggleSetting({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.accentCyan,
            ),
          ],
        ),
      ),
    );
  }

}

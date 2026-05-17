import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../models/exercise_model.dart';
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

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
      setState(() {
        _sessions = data;
        _voiceCoachingEnabled = voiceEnabled;
        _hapticFeedbackEnabled = hapticsEnabled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRefresh() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSyncing = true);
    // Simulate secure network sync
    await Future.delayed(const Duration(milliseconds: 1800));
    await _loadData();
    setState(() => _isSyncing = false);
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
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 60),
                    child: Column(
                      children: [
                        _buildAvatarSection(),
                        const SizedBox(height: 32),
                        _buildLifetimeStats(),
                        const SizedBox(height: 32),
                        _buildSettingsList(),
                        const SizedBox(height: 24),
                        _buildDangerZone(),
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
    return Column(
      children: [
        Stack(
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
                child: const CircleAvatar(
                  radius: 50,
                  backgroundColor: AppColors.surface,
                  child: Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: AppColors.textTertiary,
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
              child: const Icon(
                Icons.edit_rounded,
                size: 14,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'ATHLETE',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'athlete@formanalyzer.app',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 13,
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
    final items = [
      (Icons.person_outline_rounded, 'Personal Information'),
      (Icons.security_rounded, 'Privacy & Security'),
      (Icons.help_outline_rounded, 'Help Center'),
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
              onTap: () {},
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
              activeColor: AppColors.accentCyan,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.badRed,
          side: BorderSide(
            color: AppColors.badRed.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          'SIGN OUT',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

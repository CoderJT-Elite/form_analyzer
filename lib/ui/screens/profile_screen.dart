import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
<<<<<<< Updated upstream
<<<<<<< Updated upstream
import '../../services/storage_service.dart';
import '../widgets/glass_container.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final StorageService _storage = StorageService();
  List<String> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final history = await _storage.loadHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  int get _squatSessions =>
      _history.where((e) => e.toUpperCase().contains('SQUAT')).length;

  int get _pushupSessions =>
      _history.where((e) => e.toUpperCase().contains('PUSH')).length;

  @override
=======
=======
>>>>>>> Stashed changes
import '../widgets/glass_container.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
<<<<<<< Updated upstream
<<<<<<< Updated upstream
            expandedHeight: 160,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(
                start: 72,
                bottom: 16,
              ),
              title: Text(
                'PROFILE',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accentCyan.withAlpha(51),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.accentCyan.withAlpha(30),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.accentCyan,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accentCyan),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  _buildHistorySection(),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'TOTAL',
            value: _history.length.toString(),
            icon: Icons.bar_chart_rounded,
            color: AppColors.accentCyan,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'SQUATS',
            value: _squatSessions.toString(),
            icon: Icons.fitness_center_rounded,
            color: AppColors.goodGreen,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'PUSH-UPS',
            value: _pushupSessions.toString(),
            icon: Icons.horizontal_rule_rounded,
            color: AppColors.warnOrange,
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WORKOUT HISTORY',
          style: GoogleFonts.outfit(
            color: Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No workouts yet.\nStart your first session!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 14,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _history.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = _history[index];
              final isSquat = item.toUpperCase().contains('SQUAT');
              return GlassContainer(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      isSquat
                          ? Icons.fitness_center_rounded
                          : Icons.horizontal_rule_rounded,
                      color: isSquat
                          ? AppColors.goodGreen
                          : AppColors.warnOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
=======
=======
>>>>>>> Stashed changes
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.accentCyan.withOpacity(0.2),
                      AppColors.background,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.accentCyan.withOpacity(0.1),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: AppColors.accentCyan,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ATHLETE',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes
                      ),
                    ),
                  ],
                ),
<<<<<<< Updated upstream
<<<<<<< Updated upstream
              );
            },
          ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                await _storage.clearHistory();
                await _loadData();
              },
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.badRed,
              ),
              label: const Text(
                'Clear History',
                style: TextStyle(color: AppColors.badRed),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
=======
=======
>>>>>>> Stashed changes
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('SETTINGS'),
                  const SizedBox(height: 16),
                  _buildSettingTile(
                    'Voice Feedback',
                    'Enable AI voice coaching',
                    Icons.record_voice_over_rounded,
                    true,
                  ),
                  _buildSettingTile(
                    'Metric Units',
                    'Use KG/CM instead of LB/IN',
                    Icons.straighten_rounded,
                    true,
                  ),
                  _buildSettingTile(
                    'Haptic Feedback',
                    'Vibrate on rep detection',
                    Icons.vibration_rounded,
                    true,
                  ),

                  const SizedBox(height: 32),
                  _buildSectionHeader('ACCOUNT'),
                  const SizedBox(height: 16),
                  _buildSettingTile(
                    'Privacy Policy',
                    null,
                    Icons.privacy_tip_rounded,
                    false,
                  ),
                  _buildSettingTile(
                    'Terms of Service',
                    null,
                    Icons.description_rounded,
                    false,
                  ),

                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      'FORM ANALYZER v1.0.0',
                      style: GoogleFonts.inter(
                        color: Colors.white24,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes
            ),
          ),
        ],
      ),
    );
  }
<<<<<<< Updated upstream
<<<<<<< Updated upstream
=======
=======
>>>>>>> Stashed changes

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        color: Colors.white70,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildSettingTile(
    String title,
    String? subtitle,
    IconData icon,
    bool hasSwitch,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accentCyan, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (hasSwitch)
              Switch(
                value: true,
                onChanged: (v) {},
                activeColor: AppColors.accentCyan,
                activeTrackColor: AppColors.accentCyan.withOpacity(0.2),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }
<<<<<<< Updated upstream
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes
}

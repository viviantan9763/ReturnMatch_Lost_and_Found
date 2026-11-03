import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';

import '../../constants/app_colors.dart';
import '../../widgets/student/student_shell.dart';

import 'report_lost_screen.dart';
import 'report_found_screen.dart';
import 'search_item_screen.dart';
import 'match_details_screen.dart';
import 'my_claims_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  List<Map<String, dynamic>> _matches = [];
  bool _loadingMatches = true;
  String? _matchesError;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    if (mounted) {
      setState(() {
        _loadingMatches = true;
        _matchesError = null;
      });
    }
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/matches/my'),
        headers: AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception('Unable to load matches (HTTP ${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = (data['matches'] as List<dynamic>? ?? []);
      if (!mounted) return;
      setState(() {
        _matches = rows
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loadingMatches = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _matchesError = error.toString();
        _loadingMatches = false;
      });
    }
  }

  String _score(dynamic raw) {
    final value = double.tryParse(raw?.toString() ?? '');
    if (value == null || !value.isFinite) return 'N/A';
    final percent = value <= 1 ? value * 100 : value;
    return '${percent.clamp(0, 100).toStringAsFixed(1)}%';
  }

  // =========================================================
  // NAVIGATION
  // =========================================================

  void _goTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return StudentShell(
      selectedPage: StudentPage.home,
      title: 'Home',
      child: Container(
        color: AppColors.background,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _welcomePanel(),

                      const SizedBox(height: 18),

                      _searchBar(context),

                      const SizedBox(height: 24),

                      // =======================================
                      // QUICK ACTIONS
                      // =======================================
                      const _SectionHeading(
                        title: 'Quick Actions',
                        subtitle: 'Common lost-and-found services',
                      ),

                      const SizedBox(height: 12),

                      _quickActions(context, constraints.maxWidth),

                      const SizedBox(height: 28),

                      // =======================================
                      // CLAIM WORKFLOW
                      // =======================================
                      const _SectionHeading(
                        title: 'Claim & Collection Process',
                        subtitle:
                            'Secure ownership verification for found items',
                      ),

                      const SizedBox(height: 12),

                      _claimProcessPanel(),

                      const SizedBox(height: 28),

                      // =======================================
                      // AI MATCH
                      // =======================================
                      const _SectionHeading(
                        title: 'AI Match Suggestions',
                        subtitle:
                            'Potential found-item matches based on your reports',
                      ),

                      const SizedBox(height: 12),

                      _matchSuggestions(context),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // =========================================================
  // WELCOME PANEL
  // =========================================================

  Widget _welcomePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.studentPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(width: 16),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to ReturnMatch',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                SizedBox(height: 7),

                Text(
                  'Report, search and claim lost property with AI-assisted item matching.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // SEARCH BAR
  // =========================================================

  Widget _searchBar(BuildContext context) {
    return TextField(
      readOnly: true,
      onTap: () {
        _goTo(context, const SearchItemScreen());
      },
      decoration: InputDecoration(
        hintText: 'Search by item name, category or location',
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.studentPrimary),
        suffixIcon: const Icon(Icons.tune, color: AppColors.textSecondary),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.studentPrimary),
        ),
      ),
    );
  }

  // =========================================================
  // QUICK ACTIONS
  // =========================================================

  Widget _quickActions(BuildContext context, double width) {
    final actions = [
      (
        'Report Lost Item',
        'Create a lost-item report',
        Icons.search_off_outlined,
        const ReportLostScreen(),
      ),
      (
        'Report Found Item',
        'Register a found item',
        Icons.inventory_2_outlined,
        const ReportFoundScreen(),
      ),
      (
        'Search Matches',
        'Search AI-assisted matches',
        Icons.manage_search_outlined,
        const SearchItemScreen(),
      ),
      (
        'My Claims',
        'Review your claim requests',
        Icons.verified_user_outlined,
        const MyClaimsScreen(),
      ),
    ];

    final columns = width >= 760 ? 4 : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: width >= 760 ? 1.35 : 1.25,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];

        return _actionCard(
          context: context,
          title: action.$1,
          subtitle: action.$2,
          icon: action.$3,
          page: action.$4,
        );
      },
    );
  }

  Widget _actionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget page,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _goTo(context, page);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.studentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: AppColors.studentPrimary, size: 21),
            ),

            const Spacer(),

            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // CLAIM PROCESS
  // =========================================================

  Widget _claimProcessPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _processStep(
            number: '1',
            icon: Icons.edit_document,
            title: 'Submit Claim',
            subtitle: 'Provide a claim reason and ownership details.',
          ),

          _processDivider(),

          _processStep(
            number: '2',
            icon: Icons.security_outlined,
            title: 'Security Verification',
            subtitle: 'Answer item-specific security questions.',
          ),

          _processDivider(),

          _processStep(
            number: '3',
            icon: Icons.admin_panel_settings_outlined,
            title: 'Administrator Review',
            subtitle: 'An administrator verifies the ownership evidence.',
          ),

          _processDivider(),

          _processStep(
            number: '4',
            icon: Icons.password_outlined,
            title: 'OTP Collection',
            subtitle: 'Approved claims receive a one-time collection code.',
          ),

          _processDivider(),

          _processStep(
            number: '5',
            icon: Icons.check_circle_outline,
            title: 'Item Collected',
            subtitle: 'Admin verifies the OTP and completes the collection.',
          ),
        ],
      ),
    );
  }

  Widget _processStep({
    required String number,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.studentSoft,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.studentPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),

        const SizedBox(width: 12),

        Icon(icon, size: 22, color: AppColors.studentPrimary),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _processDivider() {
    return Container(
      height: 18,
      margin: const EdgeInsets.only(left: 16),
      alignment: Alignment.centerLeft,
      child: Container(width: 2, height: 18, color: AppColors.border),
    );
  }

  // =========================================================
  // REAL AI MATCH SUGGESTIONS
  // =========================================================

  Widget _matchSuggestions(BuildContext context) {
    if (_loadingMatches) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_matchesError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Unable to load AI match suggestions.'),
              const SizedBox(height: 8),
              Text(_matchesError!, style: const TextStyle(fontSize: 12)),
              TextButton.icon(
                onPressed: _loadMatches,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'No AI match suggestions yet. Report a lost item to receive potential matches.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        for (final match in _matches.take(5)) _matchCard(context, match),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loadMatches,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Refresh matches'),
          ),
        ),
      ],
    );
  }

  Widget _matchCard(BuildContext context, Map<String, dynamic> match) {
    final matchId = int.tryParse('${match['match_id'] ?? ''}');
    final foundName = (match['found_item_name'] ?? 'Found item').toString();
    final lostName = (match['lost_item_name'] ?? 'Lost item').toString();
    final highValue = '${match['found_value_tier']}'.toUpperCase() == 'HIGH';
    final location = (match['found_location'] ?? 'Location unavailable')
        .toString();
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: matchId == null
            ? null
            : () => _goTo(context, MatchDetailsScreen(matchId: matchId)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.studentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.studentPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      foundName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Matches your lost report: $lostName',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (highValue)
                      const Text(
                        'Enhanced ownership verification required',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.deepOrange,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(
                    _score(match['overall_similarity']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.studentPrimary,
                    ),
                  ),
                  const Text('AI score', style: TextStyle(fontSize: 10)),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// SECTION HEADING
// ===========================================================

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

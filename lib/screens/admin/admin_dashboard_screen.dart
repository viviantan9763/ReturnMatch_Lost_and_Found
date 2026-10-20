import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';
import 'claim_review_screen.dart';
import 'otp_collection_screen.dart';
import 'item_management_screen.dart';
import 'audit_log_screen.dart';
import 'retention_screen.dart';
import 'disposal_record_screen.dart';
import 'create_admin_screen.dart';
import 'system_settings_screen.dart';
import 'high_value_review_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState
    extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  int? _totalItems;
  int? _foundItems;
  int? _awaitingReceipt;
  int? _highValueItems;
  int? _pendingClaims;
  int? _retentionDue;
  int? _auditLogs;

  // ============================================================
  // INIT

  // ============================================================
  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // ============================================================
  // LOAD DASHBOARD DATA

  // ============================================================
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await Future.wait([
        _loadItems(),
        _loadClaims(),
        _loadRetention(),
        _loadAuditLogs(),
      ]);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  // ============================================================
  // ITEMS
  // GET /api/items

  // ============================================================
  Future<void> _loadItems() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/items',
        ),
        headers:
            AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(
            response,
            fallback:
                'Failed to load item statistics.',
          ),
        );
      }
      final decoded =
          jsonDecode(response.body);
      List<dynamic> items = [];
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['items'] is List) {
        items =
            decoded['items'] as List<dynamic>;
      }
      int found = 0;
      int awaitingReceipt = 0;
      int highValue = 0;
      for (final rawItem in items) {
        final item =
            Map<String, dynamic>.from(
          rawItem as Map,
        );
        final itemType =
            item['item_type']
                    ?.toString()
                    .toUpperCase() ??
                '';
        final custodyStatus =
            item['custody_status']
                    ?.toString()
                    .toUpperCase() ??
                '';
        final valueTier =
            item['value_tier']
                    ?.toString()
                    .toUpperCase() ??
                'MEDIUM';
        if (itemType == 'FOUND') {
          found++;
        }
        if (itemType == 'FOUND' &&
            custodyStatus ==
                'NOT_RECEIVED') {
          awaitingReceipt++;
        }
        if (valueTier == 'HIGH') {
          highValue++;
        }
      }
      if (!mounted) return;
      setState(() {
        _totalItems = items.length;
        _foundItems = found;
        _awaitingReceipt =
            awaitingReceipt;
        _highValueItems = highValue;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _totalItems = null;
        _foundItems = null;
        _awaitingReceipt = null;
        _highValueItems = null;
      });
    }
  }

  // ============================================================
  // CLAIMS
  // GET /api/claims

  // ============================================================
  Future<void> _loadClaims() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/claims',
        ),
        headers:
            AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception();
      }
      final decoded =
          jsonDecode(response.body);
      List<dynamic> claims = [];
      if (decoded is List) {
        claims = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['claims'] is List) {
        claims =
            decoded['claims'] as List<dynamic>;
      }
      int pending = 0;
      for (final rawClaim in claims) {
        final claim =
            Map<String, dynamic>.from(
          rawClaim as Map,
        );
        final status =
            claim['claim_status']
                    ?.toString()
                    .toUpperCase() ??
                '';
        if (status == 'PENDING' ||
            status ==
                'VERIFICATION_REQUIRED') {
          pending++;
        }
      }
      if (!mounted) return;
      setState(() {
        _pendingClaims = pending;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingClaims = null;
      });
    }
  }

  // ============================================================
  // RETENTION
  // GET /api/retention

  // ============================================================
  Future<void> _loadRetention() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/retention',
        ),
        headers:
            AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception();
      }
      final decoded =
          jsonDecode(response.body);
      List<dynamic> records = [];
      if (decoded is List) {
        records = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['records'] is List) {
          records =
              decoded['records']
                  as List<dynamic>;
        } else if (decoded['retentions']
            is List) {
          records =
              decoded['retentions']
                  as List<dynamic>;
        } else if (decoded['retention']
            is List) {
          records =
              decoded['retention']
                  as List<dynamic>;
        }
      }
      int due = 0;
      for (final rawRecord in records) {
        final record =
            Map<String, dynamic>.from(
          rawRecord as Map,
        );
        final status =
            record['retention_status']
                    ?.toString()
                    .toUpperCase() ??
                '';
        if (status == 'DUE') {
          due++;
        }
      }
      if (!mounted) return;
      setState(() {
        _retentionDue = due;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retentionDue = null;
      });
    }
  }

  // ============================================================
  // AUDIT LOG
  // GET /api/audit-logs

  // ============================================================
  Future<void> _loadAuditLogs() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AuthService.baseUrl}/audit-logs',
        ),
        headers:
            AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        throw Exception();
      }
      final decoded =
          jsonDecode(response.body);
      List<dynamic> logs = [];
      if (decoded is List) {
        logs = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['logs'] is List) {
          logs =
              decoded['logs'] as List<dynamic>;
        } else if (decoded['audit_logs']
            is List) {
          logs =
              decoded['audit_logs']
                  as List<dynamic>;
        }
      }
      if (!mounted) return;
      setState(() {
        _auditLogs = logs.length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _auditLogs = null;
      });
    }
  }

  // ============================================================
  // NAVIGATION

  // ============================================================
  void _goTo(Widget page) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  // ============================================================
  // PAGE

  // ============================================================
  @override

  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage:
          AdminPage.dashboard,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh:
              _loadDashboardData,
          child: SingleChildScrollView(
            physics:
                const AlwaysScrollableScrollPhysics(),
            padding:
                const EdgeInsets.all(30),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(
                  maxWidth: 1150,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    _pageHeader(),
                    const SizedBox(
                      height: 28,
                    ),
                    if (_errorMessage !=
                        null) ...[
                      _errorPanel(),
                      const SizedBox(
                        height: 20,
                      ),
                    ],
                    _overviewSection(),
                    const SizedBox(
                      height: 32,
                    ),
                    _sectionHeading(
                      title:
                          'Administrative Functions',
                      subtitle:
                          'Access ReturnMatch management and verification tools.',
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    _functionsGrid(),
                    const SizedBox(
                      height: 32,
                    ),
                    _sectionHeading(
                      title:
                          'System Attention',
                      subtitle:
                          'Current records that may require administrator attention.',
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    _attentionSection(),
                    const SizedBox(
                      height: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PAGE HEADER

  // ============================================================

  Widget _pageHeader() {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Administration Dashboard',
                style: TextStyle(
                  color:
                      AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              const Text(
                'Monitor ReturnMatch operations, claims, item custody and retention activity.',
                style: TextStyle(
                  color:
                      AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: _isLoading
              ? null
              : _loadDashboardData,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons.refresh_rounded,
                  size: 19,
                ),
          label: const Text(
            'Refresh',
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          style:
              OutlinedButton.styleFrom(
            foregroundColor:
                AppColors.adminPrimary,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 17,
              vertical: 15,
            ),
            side: const BorderSide(
              color: AppColors.border,
            ),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // OVERVIEW

  // ============================================================

  Widget _overviewSection() {
    return LayoutBuilder(
      builder:
          (context, constraints) {
        final cards = [
          _OverviewData(
            title: 'Total Items',
            value: _totalItems,
            icon:
                Icons.inventory_2_outlined,
            onTap: () {
              _goTo(
                const ItemManagementScreen(),
              );
            },
          ),
          _OverviewData(
            title: 'Pending Claims',
            value: _pendingClaims,
            icon: Icons
                .pending_actions_outlined,
            onTap: () {
              _goTo(
                const ClaimReviewScreen(),
              );
            },
          ),
          _OverviewData(
            title: 'Awaiting Receipt',
            value:
                _awaitingReceipt,
            icon:
                Icons.move_to_inbox_outlined,
            onTap: () {
              _goTo(
                const ItemManagementScreen(),
              );
            },
          ),
          _OverviewData(
            title: 'Retention Due',
            value:
                _retentionDue,
            icon:
                Icons.event_busy_outlined,
            onTap: () {
              _goTo(
                const RetentionMonitorScreen(),
              );
            },
          ),
        ];
        if (constraints.maxWidth <
            760) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map(
                  (card) =>
                      SizedBox(
                    width:
                        (constraints.maxWidth -
                                12) /
                            2,
                    child:
                        _overviewCard(
                      card,
                    ),
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: [
            for (int i = 0;
                i < cards.length;
                i++) ...[
              Expanded(
                child:
                    _overviewCard(
                  cards[i],
                ),
              ),
              if (i !=
                  cards.length - 1)
                const SizedBox(
                  width: 14,
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _overviewCard(
    _OverviewData data,
  ) {
    return InkWell(
      onTap: data.onTap,
      borderRadius:
          BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color:
                    AppColors.adminSoft,
                borderRadius:
                    BorderRadius.circular(
                  9,
                ),
              ),
              child: Icon(
                data.icon,
                color:
                    AppColors.adminPrimary,
                size: 23,
              ),
            ),
            const SizedBox(
              width: 14,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    _isLoading
                        ? '...'
                        : data.value
                                ?.toString() ??
                            '—',
                    style:
                        const TextStyle(
                      color: AppColors
                          .textPrimary,
                      fontSize: 24,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    data.title,
                    style:
                        const TextStyle(
                      color: AppColors
                          .textSecondary,
                      fontSize: 12.5,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons
                  .chevron_right_rounded,
              color: AppColors
                  .textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FUNCTIONS

  // ============================================================

  Widget _functionsGrid() {
    return LayoutBuilder(
      builder:
          (context, constraints) {
        int columns;
        if (constraints.maxWidth >=
            950) {
          columns = 3;
        } else if (constraints
                .maxWidth >=
            620) {
          columns = 2;
        } else {
          columns = 1;
        }
        final functions = [
          _FunctionData(
            title: 'High-Value Report Review',
            description:
                'Approve or reject high-value lost and found reports before publication.',
            icon: Icons.verified_outlined,
            onTap: () {
              // Keep Dashboard in the stack so AppBar back arrow works.
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HighValueReviewScreen(),
                ),
              );
            },
          ),
          _FunctionData(
            title:
                'Item Management',
            description:
                'Review lost and found reports, custody status and item classification.',
            icon:
                Icons.inventory_2_outlined,
            onTap: () {
              _goTo(
                const ItemManagementScreen(),
              );
            },
          ),
          _FunctionData(
            title: 'Claim Review',
            description:
                'Review ownership claims, security answers and verification requirements.',
            icon:
                Icons.verified_user_outlined,
            onTap: () {
              _goTo(
                const ClaimReviewScreen(),
              );
            },
          ),
          _FunctionData(
            title: 'OTP Collection',
            description:
                'Look up approved claims by OTP and confirm item handover.',
            icon: Icons.pin_outlined,
            onTap: () {
              _goTo(const OtpCollectionScreen());
            },
          ),
          _FunctionData(
            title: 'Retention',
            description:
                'Monitor physically received items and retention due dates.',
            icon:
                Icons.schedule_outlined,
            onTap: () {
              _goTo(
                const RetentionMonitorScreen(),
              );
            },
          ),
          _FunctionData(
            title:
                'Disposal Records',
            description:
                'Manage due items and maintain disposal and reversal records.',
            icon:
                Icons.delete_outline_rounded,
            onTap: () {
              _goTo(
                const DisposalRecordScreen(),
              );
            },
          ),
          _FunctionData(
            title: 'Audit Log',
            description:
                'Review administrator actions and important system workflow events.',
            icon:
                Icons.fact_check_outlined,
            onTap: () {
              _goTo(
                const AuditLogScreen(),
              );
            },
          ),
          _FunctionData(
            title:
                'System Settings',
            description:
                'Configure retention policy and system-wide classification rules.',
            icon:
                Icons.settings_outlined,
            onTap: () {
              _goTo(
                const SystemSettingsScreen(),
              );
            },
          ),
          _FunctionData(
            title:
                'Admin Management',
            description:
                'Create and manage authorized administrator access.',
            icon: Icons
                .manage_accounts_outlined,
            onTap: () {
              _goTo(
                const CreateAdminScreen(),
              );
            },
          ),
        ];
        return GridView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              functions.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                columns,
            crossAxisSpacing:
                14,
            mainAxisSpacing:
                14,
            childAspectRatio:
                columns == 1
                    ? 3.2
                    : columns == 2
                        ? 2.0
                        : 1.85,
          ),
          itemBuilder:
              (context, index) {
            return _functionCard(
              functions[index],
            );
          },
        );
      },
    );
  }

  Widget _functionCard(
    _FunctionData data,
  ) {
    return InkWell(
      onTap: data.onTap,
      borderRadius:
          BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration:
                      BoxDecoration(
                    color: AppColors
                        .adminSoft,
                    borderRadius:
                        BorderRadius
                            .circular(
                      8,
                    ),
                  ),
                  child: Icon(
                    data.icon,
                    color: AppColors
                        .adminPrimary,
                    size: 22,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons
                      .arrow_forward_rounded,
                  size: 19,
                  color: AppColors
                      .textSecondary,
                ),
              ],
            ),
            const Spacer(),
            Text(
              data.title,
              style:
                  const TextStyle(
                color: AppColors
                    .textPrimary,
                fontSize: 15,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              data.description,
              maxLines: 3,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  const TextStyle(
                color: AppColors
                    .textSecondary,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ATTENTION

  // ============================================================

  Widget _attentionSection() {
    return LayoutBuilder(
      builder:
          (context, constraints) {
        final cards = [
          _AttentionData(
            title:
                'Items Awaiting Receipt',
            value:
                _awaitingReceipt,
            description:
                'Found items reported but not yet physically received by the office.',
            icon:
                Icons.move_to_inbox_outlined,
            onTap: () {
              _goTo(
                const ItemManagementScreen(),
              );
            },
          ),
          _AttentionData(
            title:
                'Claims Requiring Attention',
            value:
                _pendingClaims,
            description:
                'Pending or verification-required claims awaiting administrative review.',
            icon: Icons
                .verified_user_outlined,
            onTap: () {
              _goTo(
                const ClaimReviewScreen(),
              );
            },
          ),
          _AttentionData(
            title:
                'Retention Due',
            value:
                _retentionDue,
            description:
                'Stored items that have reached the end of their retention period.',
            icon:
                Icons.event_busy_outlined,
            onTap: () {
              _goTo(
                const RetentionMonitorScreen(),
              );
            },
          ),
        ];
        if (constraints.maxWidth <
            800) {
          return Column(
            children: [
              for (final card
                  in cards) ...[
                _attentionCard(
                  card,
                ),
                const SizedBox(
                  height: 12,
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            for (int i = 0;
                i < cards.length;
                i++) ...[
              Expanded(
                child:
                    _attentionCard(
                  cards[i],
                ),
              ),
              if (i !=
                  cards.length - 1)
                const SizedBox(
                  width: 14,
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _attentionCard(
    _AttentionData data,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(
                  color:
                      AppColors.adminSoft,
                  borderRadius:
                      BorderRadius
                          .circular(
                    8,
                  ),
                ),
                child: Icon(
                  data.icon,
                  color: AppColors
                      .adminPrimary,
                  size: 21,
                ),
              ),
              const Spacer(),
              Text(
                _isLoading
                    ? '...'
                    : data.value
                            ?.toString() ??
                        '—',
                style:
                    const TextStyle(
                  color: AppColors
                      .textPrimary,
                  fontSize: 23,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            data.title,
            style:
                const TextStyle(
              color:
                  AppColors.textPrimary,
              fontSize: 14,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            data.description,
            style:
                const TextStyle(
              color: AppColors
                  .textSecondary,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          TextButton.icon(
            onPressed:
                data.onTap,
            style:
                TextButton.styleFrom(
              padding:
                  EdgeInsets.zero,
              foregroundColor:
                  AppColors
                      .adminPrimary,
            ),
            iconAlignment:
                IconAlignment.end,
            icon: const Icon(
              Icons
                  .arrow_forward_rounded,
              size: 17,
            ),
            label: const Text(
              'View Details',
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION HEADING

  // ============================================================

  Widget _sectionHeading({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              const TextStyle(
            color:
                AppColors.textPrimary,
            fontSize: 18,
            fontWeight:
                FontWeight.w800,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          subtitle,
          style:
              const TextStyle(
            color:
                AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ERROR PANEL

  // ============================================================

  Widget _errorPanel() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.red.withValues(
          alpha: 0.05,
        ),
        borderRadius:
            BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons
                .error_outline_rounded,
            color:
                Colors.red.shade700,
            size: 21,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              _errorMessage ??
                  'Some dashboard information could not be loaded.',
              style: TextStyle(
                color:
                    Colors.red.shade700,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed:
                _loadDashboardData,
            child:
                const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS

  // ============================================================
  static String _extractMessage(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final body =
          jsonDecode(response.body);
      if (body
              is Map<String, dynamic> &&
          body['message'] != null) {
        return body['message']
            .toString();
      }
    } catch (_) {}
    return fallback;
  }
}

// ============================================================
// DATA CLASSES

// ============================================================

class _OverviewData {
  final String title;
  final int? value;
  final IconData icon;
  final VoidCallback onTap;
  const _OverviewData({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });
}

class _FunctionData {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  const _FunctionData({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });
}

class _AttentionData {
  final String title;
  final int? value;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  const _AttentionData({
    required this.title,
    required this.value,
    required this.description,
    required this.icon,
    required this.onTap,
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  static const Color adminBlue = AppColors.adminPrimary;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  bool _isLoading = true;
  String? _errorMessage;
  String _selectedType = 'ALL';
  String _searchQuery = '';
  List<Map<String, dynamic>> _logs = [];

  final List<String> _types = const [
    'ALL',
    'CLAIMS',
    'OTP',
    'ITEMS',
    'RETENTION',
    'DISPOSAL',
    'ADMIN',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/audit-logs'),
        headers: AuthService.authenticatedHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(response, fallback: 'Failed to load audit logs.'),
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawLogs = body['logs'];

      if (rawLogs is! List) {
        throw Exception('Invalid audit log data returned by server.');
      }

      final logs = rawLogs
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    final query = _searchQuery.trim().toLowerCase();

    return _logs.where((log) {
      final type = _logType(log);
      if (_selectedType != 'ALL' && type != _selectedType) {
        return false;
      }

      if (query.isEmpty) return true;

      final haystack = [
        log['log_id'],
        log['action_type'],
        log['action_details'],
        log['admin_name'],
        log['item_id'],
        log['item_name'],
        log['claim_id'],
        log['claim_status'],
        log['claim_reason'],
      ].map(_text).join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  int _countType(String type) =>
      _logs.where((log) => _logType(log) == type).length;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.audit,
      child: Container(
        color: background,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pageHeader(),
                const SizedBox(height: 22),
                _summarySection(),
                const SizedBox(height: 20),
                _toolbar(),
                const SizedBox(height: 16),
                Expanded(child: _content()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.adminSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.fact_check_outlined,
            color: adminBlue,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit Log',
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Immutable administrative and system activity history.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadLogs,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _summarySection() {
    final cards = [
      _summaryCard(
        'Total Logs',
        _logs.length.toString(),
        Icons.receipt_long_outlined,
      ),
      _summaryCard(
        'Claim Actions',
        _countType('CLAIMS').toString(),
        Icons.verified_user_outlined,
      ),
      _summaryCard(
        'Retention Actions',
        _countType('RETENTION').toString(),
        Icons.schedule_outlined,
      ),
      _summaryCard(
        'Disposal Actions',
        _countType('DISPOSAL').toString(),
        Icons.delete_outline_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
                ? 2
                : 1;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.4 : 2.7,
          children: cards,
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.adminSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: adminBlue, size: 21),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search action, admin, item or claim',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: background,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          );

          final filter = DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: InputDecoration(
              labelText: 'Activity Type',
              isDense: true,
              filled: true,
              fillColor: background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            items: _types
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type == 'ALL'
                        ? 'All Activity'
                        : _formatStatus(type)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedType = value);
              }
            },
          );

          if (constraints.maxWidth < 650) {
            return Column(
              children: [search, const SizedBox(height: 10), filter],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              SizedBox(width: 220, child: filter),
            ],
          );
        },
      ),
    );
  }

  Widget _content() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: adminBlue),
      );
    }

    if (_errorMessage != null) {
      return _messageState(
        icon: Icons.error_outline_rounded,
        title: 'Unable to Load Audit Log',
        message: _errorMessage!,
        action: TextButton.icon(
          onPressed: _loadLogs,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (_filteredLogs.isEmpty) {
      return _messageState(
        icon: Icons.fact_check_outlined,
        title: 'No Audit Records',
        message: _logs.isEmpty
            ? 'No audit events have been recorded yet.'
            : 'No audit records match the selected filter or search.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _filteredLogs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _logCard(_filteredLogs[index]),
      ),
    );
  }

  Widget _logCard(Map<String, dynamic> log) {
    final type = _logType(log);
    final actionType = _fallback(log['action_type'], 'UNKNOWN_ACTION');
    final color = _typeColor(type);
    final claimId = _text(log['claim_id']).trim();
    final itemId = _text(log['item_id']).trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_typeIcon(type), color: color, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _formatStatus(actionType),
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _typeChip(type, color),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _fallback(log['action_details'], 'No details recorded.'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 7,
                  children: [
                    _meta(
                      Icons.person_outline_rounded,
                      _fallback(log['admin_name'], 'System'),
                    ),
                    if (itemId.isNotEmpty)
                      _meta(
                        Icons.inventory_2_outlined,
                        _text(log['item_name']).trim().isEmpty
                            ? 'Item #$itemId'
                            : 'Item #$itemId • ${_text(log['item_name'])}',
                      ),
                    if (claimId.isNotEmpty)
                      _meta(Icons.tag_outlined, 'Claim #$claimId'),
                    _meta(
                      Icons.schedule_outlined,
                      _formatDateTime(log['timestamp']),
                    ),
                  ],
                ),
                if (claimId.isNotEmpty &&
                    _text(log['claim_status']).trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Current Claim Status: ${_formatStatus(_text(log['claim_status']))}',
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_text(log['claim_reason']).trim().isNotEmpty)
                          Text(
                            'Reason: ${_text(log['claim_reason'])}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String type, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _formatStatus(type),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              Icon(icon, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _logType(Map<String, dynamic> log) {
    final action = _text(log['action_type']).toUpperCase();

    if (action.contains('OTP')) return 'OTP';
    if (action.contains('RETENTION')) return 'RETENTION';
    if (action.contains('DISPOSAL')) return 'DISPOSAL';
    if (action.contains('ADMIN')) return 'ADMIN';
    if (action.contains('CLAIM') ||
        action.contains('VERIFICATION') ||
        action.contains('SECURITY_ANSWER')) {
      return 'CLAIMS';
    }
    return 'ITEMS';
  }

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'CLAIMS':
        return Icons.verified_user_outlined;
      case 'OTP':
        return Icons.password_outlined;
      case 'RETENTION':
        return Icons.schedule_outlined;
      case 'DISPOSAL':
        return Icons.delete_outline_rounded;
      case 'ADMIN':
        return Icons.manage_accounts_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  static Color _typeColor(String type) {
    switch (type) {
      case 'CLAIMS':
        return AppColors.success;
      case 'OTP':
        return adminBlue;
      case 'RETENTION':
        return AppColors.warning;
      case 'DISPOSAL':
        return AppColors.danger;
      case 'ADMIN':
        return adminBlue;
      default:
        return AppColors.textSecondary;
    }
  }

  static String _extractMessage(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  static String _text(dynamic value) => value?.toString() ?? '';

  static String _fallback(dynamic value, String fallback) {
    final text = _text(value).trim();
    return text.isEmpty ? fallback : text;
  }

  static String _formatStatus(String value) {
    final text = value.trim();
    if (text.isEmpty) return '—';
    return text
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  static String _formatDateTime(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

class RetentionMonitorScreen extends StatefulWidget {
  const RetentionMonitorScreen({super.key});

  @override
  State<RetentionMonitorScreen> createState() =>
      _RetentionMonitorScreenState();
}

class _RetentionMonitorScreenState extends State<RetentionMonitorScreen> {
  static const Color adminBlue = AppColors.adminPrimary;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  bool _isLoading = true;
  String? _errorMessage;
  String _selectedStatus = 'ALL';
  String _searchQuery = '';
  int _newlyDueCount = 0;

  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _disposals = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final responses = await Future.wait([
        http.get(
          Uri.parse('${AuthService.baseUrl}/retention'),
          headers: AuthService.authenticatedHeaders(),
        ),
        http.get(
          Uri.parse('${AuthService.baseUrl}/disposals'),
          headers: AuthService.authenticatedHeaders(),
        ),
      ]);

      final retentionResponse = responses[0];
      final disposalResponse = responses[1];

      if (retentionResponse.statusCode != 200) {
        throw Exception(
          _extractMessage(
            retentionResponse,
            fallback: 'Failed to load retention records.',
          ),
        );
      }

      if (disposalResponse.statusCode != 200) {
        throw Exception(
          _extractMessage(
            disposalResponse,
            fallback: 'Failed to load disposal records.',
          ),
        );
      }

      final retentionBody =
          jsonDecode(retentionResponse.body) as Map<String, dynamic>;
      final disposalBody =
          jsonDecode(disposalResponse.body) as Map<String, dynamic>;

      final rawRecords = retentionBody['records'];
      final rawDisposals = disposalBody['records'];

      if (rawRecords is! List || rawDisposals is! List) {
        throw Exception('Invalid retention data returned by server.');
      }

      final records = rawRecords
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final disposals = rawDisposals
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _records = records;
        _disposals = disposals;
        _newlyDueCount = int.tryParse(
              retentionBody['newly_due_count']?.toString() ?? '',
            ) ??
            0;
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

  List<Map<String, dynamic>> get _filteredRecords {
    final query = _searchQuery.trim().toLowerCase();

    return _records.where((record) {
      final status = _text(record['retention_status']).toUpperCase();
      if (_selectedStatus != 'ALL' && status != _selectedStatus) {
        return false;
      }

      if (query.isEmpty) return true;

      final haystack = [
        record['retention_id'],
        record['item_id'],
        record['item_name'],
        record['storage_location'],
        record['location'],
      ].map(_text).join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  int _count(String status) => _records
      .where((record) =>
          _text(record['retention_status']).toUpperCase() == status)
      .length;

  Map<String, dynamic>? _activeDisposalForItem(dynamic itemId) {
    final id = _text(itemId);
    for (final disposal in _disposals) {
      if (_text(disposal['item_id']) != id) continue;
      final status = _text(disposal['disposal_status']).toUpperCase();
      if (status == 'PENDING' || status == 'COMPLETED') {
        return disposal;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.retention,
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
                if (_newlyDueCount > 0) ...[
                  const SizedBox(height: 14),
                  _newlyDueNotice(),
                ],
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
            Icons.schedule_outlined,
            color: adminBlue,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Retention Monitoring',
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Track physically received items through their retention lifecycle.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadData,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _summarySection() {
    final cards = [
      _summaryCard(
        'Active',
        _count('ACTIVE').toString(),
        Icons.inventory_2_outlined,
        AppColors.success,
      ),
      _summaryCard(
        'Due',
        _count('DUE').toString(),
        Icons.event_busy_outlined,
        AppColors.danger,
      ),
      _summaryCard(
        'Completed',
        _count('COMPLETED').toString(),
        Icons.task_alt_rounded,
        adminBlue,
      ),
      _summaryCard(
        'Total Records',
        _records.length.toString(),
        Icons.receipt_long_outlined,
        AppColors.textSecondary,
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

  Widget _summaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 21),
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

  Widget _newlyDueNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$_newlyDueCount retention record(s) reached the due date and were automatically updated to DUE.',
              style: const TextStyle(
                color: textDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
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
              hintText: 'Search item, record or storage location',
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
            initialValue: _selectedStatus,
            decoration: InputDecoration(
              labelText: 'Status',
              isDense: true,
              filled: true,
              fillColor: background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
              DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
              DropdownMenuItem(value: 'DUE', child: Text('Due')),
              DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
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
              SizedBox(width: 210, child: filter),
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
        title: 'Unable to Load Retention Records',
        message: _errorMessage!,
        action: TextButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (_filteredRecords.isEmpty) {
      return _messageState(
        icon: Icons.inventory_2_outlined,
        title: 'No Retention Records',
        message: _records.isEmpty
            ? 'Retention records will appear after a found item is physically received by the Lost & Found Office.'
            : 'No records match the selected filter or search.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _filteredRecords.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _retentionCard(_filteredRecords[index]),
      ),
    );
  }

  Widget _retentionCard(Map<String, dynamic> record) {
    final status = _text(record['retention_status']).toUpperCase();
    final itemName = _fallback(record['item_name'], 'Unknown Item');
    final statusColor = _statusColor(status);
    final disposal = _activeDisposalForItem(record['item_id']);
    final disposalStatus =
        disposal == null ? '' : _text(disposal['disposal_status']).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.adminSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_itemIcon(itemName), color: adminBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Retention #${_fallback(record['retention_id'], '—')} • Item #${_fallback(record['item_id'], '—')}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(status, statusColor),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 13),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _detail('Start Date', _formatDate(record['retention_start_date'])),
              _detail('Due Date', _formatDate(record['retention_due_date'])),
              _detail(
                'Storage Location',
                _fallback(record['storage_location'], 'Not recorded'),
              ),
              _detail(
                'Value Tier',
                _formatStatus(_fallback(record['value_tier'], 'MEDIUM')),
              ),
              _detail(
                'Custody',
                _formatStatus(_fallback(record['custody_status'], '—')),
              ),
              _detail(
                'Item Status',
                _formatStatus(_fallback(record['item_status'], '—')),
              ),
            ],
          ),
          if (disposal != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.adminSoft,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'Disposal record #${_fallback(disposal['disposal_id'], '—')} • ${_formatStatus(disposalStatus)}',
                style: const TextStyle(
                  color: adminBlue,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (status == 'DUE') ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: disposalStatus == 'PENDING' ||
                        disposalStatus == 'COMPLETED'
                    ? null
                    : () => _createDisposal(record),
                style: FilledButton.styleFrom(
                  backgroundColor: adminBlue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(
                  disposalStatus == 'PENDING'
                      ? 'Disposal Pending'
                      : disposalStatus == 'COMPLETED'
                          ? 'Disposal Completed'
                          : 'Create Disposal Record',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createDisposal(Map<String, dynamic> record) async {
    final itemId = int.tryParse(_text(record['item_id']));
    if (itemId == null) {
      _showMessage('Invalid item ID.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create Disposal Record?'),
          content: Text(
            '${_fallback(record['item_name'], 'This item')} has reached its retention due date. A PENDING disposal record will be created for administrative processing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: adminBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create Record'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/disposals/$itemId'),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      if (response.statusCode != 201) {
        _showMessage(
          _extractMessage(
            response,
            fallback: 'Failed to create disposal record.',
          ),
          isError: true,
        );
        return;
      }

      _showMessage('Disposal record created successfully.');
      await _loadData();
    } catch (error) {
      _showMessage('Unable to connect to server: $error', isError: true);
    }
  }

  Widget _detail(String label, String value) {
    return SizedBox(
      width: 185,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: textDark,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
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

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.adminDark,
      ),
    );
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

  static String _formatDate(dynamic value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year}';
  }

  static Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return AppColors.success;
      case 'DUE':
        return AppColors.danger;
      case 'COMPLETED':
        return adminBlue;
      default:
        return AppColors.textSecondary;
    }
  }

  static IconData _itemIcon(String itemName) {
    final name = itemName.toLowerCase();
    if (name.contains('laptop') || name.contains('macbook')) {
      return Icons.laptop_mac_rounded;
    }
    if (name.contains('phone') || name.contains('mobile')) {
      return Icons.smartphone_rounded;
    }
    if (name.contains('wallet')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (name.contains('watch')) return Icons.watch_rounded;
    if (name.contains('key')) return Icons.key_rounded;
    if (name.contains('bottle')) return Icons.water_drop_outlined;
    return Icons.inventory_2_outlined;
  }
}

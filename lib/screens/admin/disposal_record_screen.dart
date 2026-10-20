import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

class DisposalRecordScreen extends StatefulWidget {
  const DisposalRecordScreen({super.key});

  @override
  State<DisposalRecordScreen> createState() =>
      _DisposalRecordScreenState();
}

class _DisposalRecordScreenState extends State<DisposalRecordScreen> {
  static const Color adminBlue = AppColors.adminPrimary;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  bool _isLoading = true;
  String? _errorMessage;
  String _selectedStatus = 'ALL';
  String _searchQuery = '';
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/disposals'),
        headers: AuthService.authenticatedHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(
            response,
            fallback: 'Failed to load disposal records.',
          ),
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawRecords = body['records'];

      if (rawRecords is! List) {
        throw Exception('Invalid disposal data returned by server.');
      }

      final records = rawRecords
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _records = records;
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
      final status = _text(record['disposal_status']).toUpperCase();
      if (_selectedStatus != 'ALL' && status != _selectedStatus) {
        return false;
      }

      if (query.isEmpty) return true;

      final haystack = [
        record['disposal_id'],
        record['item_id'],
        record['item_name'],
        record['admin_name'],
        record['disposal_method'],
        record['remarks'],
      ].map(_text).join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  int _count(String status) => _records
      .where((record) =>
          _text(record['disposal_status']).toUpperCase() == status)
      .length;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.disposal,
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
            Icons.delete_outline_rounded,
            color: adminBlue,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Disposal Records',
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Process pending disposal records and preserve disposal history.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadRecords,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _summarySection() {
    final cards = [
      _summaryCard(
        'Pending',
        _count('PENDING').toString(),
        Icons.pending_actions_outlined,
        AppColors.warning,
      ),
      _summaryCard(
        'Completed',
        _count('COMPLETED').toString(),
        Icons.task_alt_rounded,
        AppColors.success,
      ),
      _summaryCard(
        'Cancelled',
        _count('CANCELLED').toString(),
        Icons.cancel_outlined,
        AppColors.textSecondary,
      ),
      _summaryCard(
        'Reversed',
        _count('REVERSED').toString(),
        Icons.restore_rounded,
        adminBlue,
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
              hintText: 'Search record, item, admin or method',
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
              DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
              DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
              DropdownMenuItem(value: 'CANCELLED', child: Text('Cancelled')),
              DropdownMenuItem(value: 'REVERSED', child: Text('Reversed')),
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
        title: 'Unable to Load Disposal Records',
        message: _errorMessage!,
        action: TextButton.icon(
          onPressed: _loadRecords,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (_filteredRecords.isEmpty) {
      return _messageState(
        icon: Icons.delete_outline_rounded,
        title: 'No Disposal Records',
        message: _records.isEmpty
            ? 'Disposal records will appear after a due retention record is sent for disposal processing.'
            : 'No records match the selected filter or search.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _filteredRecords.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _recordCard(_filteredRecords[index]),
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> record) {
    final status = _text(record['disposal_status']).toUpperCase();
    final statusColor = _statusColor(status);
    final itemName = _fallback(record['item_name'], 'Unknown Item');

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
                      'Disposal #${_fallback(record['disposal_id'], '—')} • Item #${_fallback(record['item_id'], '—')}',
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
              _detail(
                'Method',
                _formatMethod(_fallback(record['disposal_method'], '—')),
              ),
              _detail(
                'Processed By',
                _fallback(record['admin_name'], '—'),
              ),
              _detail(
                'Disposal Date',
                _formatDateTime(record['disposal_date']),
              ),
              _detail(
                'Value Tier',
                _formatStatus(_fallback(record['value_tier'], 'MEDIUM')),
              ),
              _detail(
                'Item Type',
                _formatStatus(_fallback(record['item_type'], '—')),
              ),
            ],
          ),
          if (_text(record['remarks']).trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'Remarks: ${_text(record['remarks'])}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (status == 'PENDING' || status == 'COMPLETED') ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  if (status == 'PENDING') ...[
                    OutlinedButton.icon(
                      onPressed: () => _cancelDisposal(record),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _completeDisposal(record),
                      style: FilledButton.styleFrom(
                        backgroundColor: adminBlue,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.task_alt_rounded, size: 17),
                      label: const Text('Complete Disposal'),
                    ),
                  ],
                  if (status == 'COMPLETED')
                    OutlinedButton.icon(
                      onPressed: () => _reverseDisposal(record),
                      icon: const Icon(Icons.restore_rounded, size: 17),
                      label: const Text('Restore to Retention'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _completeDisposal(Map<String, dynamic> record) async {
    final disposalId = int.tryParse(_text(record['disposal_id']));
    if (disposalId == null) {
      _showMessage('Invalid disposal ID.', isError: true);
      return;
    }

    String method = 'RECYCLING';
    final remarksController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Complete Disposal'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fallback(record['item_name'], 'Item'),
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: 'Disposal Method',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'RECYCLING',
                          child: Text('Recycling'),
                        ),
                        DropdownMenuItem(
                          value: 'DONATION',
                          child: Text('Donation'),
                        ),
                        DropdownMenuItem(
                          value: 'GENERAL_DISPOSAL',
                          child: Text('General Disposal'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => method = value);
                        }
                      },
                    ),
                    const SizedBox(height: 13),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
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
                  child: const Text('Confirm Completion'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      remarksController.dispose();
      return;
    }

    final remarks = remarksController.text.trim();
    remarksController.dispose();

    await _updateDisposalStatus(
      disposalId: disposalId,
      status: 'COMPLETED',
      method: method,
      remarks: remarks,
    );
  }

  Future<void> _cancelDisposal(Map<String, dynamic> record) async {
    final disposalId = int.tryParse(_text(record['disposal_id']));
    if (disposalId == null) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Disposal Record?'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will mark disposal #$disposalId as CANCELLED. The audit history will remain unchanged.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Pending'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cancel Disposal'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      controller.dispose();
      return;
    }

    final remarks = controller.text.trim();
    controller.dispose();

    await _updateDisposalStatus(
      disposalId: disposalId,
      status: 'CANCELLED',
      remarks: remarks,
    );
  }

  Future<void> _updateDisposalStatus({
    required int disposalId,
    required String status,
    String? method,
    String? remarks,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse(
          '${AuthService.baseUrl}/disposals/$disposalId/status',
        ),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'status': status,
          if (method != null) 'disposal_method': method,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        }),
      );

      if (response.statusCode != 200) {
        _showMessage(
          _extractMessage(
            response,
            fallback: 'Failed to update disposal record.',
          ),
          isError: true,
        );
        return;
      }

      _showMessage(
        status == 'COMPLETED'
            ? 'Disposal completed successfully.'
            : 'Disposal cancelled successfully.',
      );
      await _loadRecords();
    } catch (error) {
      _showMessage('Unable to connect to server: $error', isError: true);
    }
  }

  Future<void> _reverseDisposal(Map<String, dynamic> record) async {
    final disposalId = int.tryParse(_text(record['disposal_id']));
    if (disposalId == null) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restore to Retention?'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Use this only when the disposal was marked completed by mistake and the physical item is still held by the Lost & Found Office. A new retention record will be created; the old history will not be overwritten.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason for reversal *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
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
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  _showMessage(
                    'Reason for reversal is required.',
                    isError: true,
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Restore Item'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      controller.dispose();
      return;
    }

    final reason = controller.text.trim();
    controller.dispose();

    try {
      final response = await http.post(
        Uri.parse(
          '${AuthService.baseUrl}/disposals/$disposalId/reverse',
        ),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reason': reason}),
      );

      if (response.statusCode != 200) {
        _showMessage(
          _extractMessage(
            response,
            fallback: 'Failed to reverse disposal.',
          ),
          isError: true,
        );
        return;
      }

      _showMessage(
        'Disposal reversed and a new retention period was created.',
      );
      await _loadRecords();
    } catch (error) {
      _showMessage('Unable to connect to server: $error', isError: true);
    }
  }

  Widget _detail(String label, String value) {
    return SizedBox(
      width: 180,
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

  static String _formatMethod(String value) {
    if (value == '—') return value;
    return _formatStatus(value);
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

  static Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return AppColors.warning;
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.textSecondary;
      case 'REVERSED':
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

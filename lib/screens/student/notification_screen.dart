import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';

/// Real notifications for the currently logged-in user.
/// GET   /api/notifications
/// PATCH /api/notifications/read-all
/// PATCH /api/notifications/:id/read
/// This page deliberately does not contain prototype or fake records.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _updatingAll = false;
  bool _unreadOnly = false;
  final Set<int> _updatingIds = {};
  String? _error;
  int _unreadCount = 0;

  Color get _primary => widget.isAdmin
      ? AppColors.adminPrimary
      : AppColors.studentPrimary;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  String _responseMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/notifications'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(_responseMessage(
          response,
          response.statusCode == 401
              ? 'Please log in again.'
              : 'Could not load notifications (${response.statusCode}).',
        ));
      }

      final data = jsonDecode(response.body);
      if (data is! Map || data['notifications'] is! List) {
        throw Exception('Unexpected notification data from server.');
      }

      final notifications = (data['notifications'] as List)
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      final count = int.tryParse('${data['unread_count'] ?? 0}') ?? 0;

      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _unreadCount = count;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  bool _isUnread(Map<String, dynamic> item) {
    final value = item['is_read'];
    return value == 0 || value == false || value?.toString() == '0';
  }

  int? _idOf(Map<String, dynamic> item) =>
      int.tryParse('${item['notification_id']}');

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (!_isUnread(item)) return;
    final id = _idOf(item);
    if (id == null || _updatingIds.contains(id)) return;

    setState(() => _updatingIds.add(id));
    try {
      final response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/notifications/$id/read'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(_responseMessage(response, 'Could not mark as read.'));
      }

      if (!mounted) return;
      setState(() {
        item['is_read'] = 1;
        if (_unreadCount > 0) _unreadCount--;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
      ));
    } finally {
      if (mounted) setState(() => _updatingIds.remove(id));
    }
  }

  Future<void> _markAllRead() async {
    if (_updatingAll || _unreadCount == 0) return;
    setState(() => _updatingAll = true);

    try {
      final response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/notifications/read-all'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(_responseMessage(response, 'Could not mark all as read.'));
      }

      if (!mounted) return;
      setState(() {
        for (final item in _notifications) {
          item['is_read'] = 1;
        }
        _unreadCount = 0;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
      ));
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  String _titleFor(String type) {
    switch (type.toUpperCase()) {
      case 'REPORT_APPROVED':
        return 'Report Approved';
      case 'REPORT_REJECTED':
        return 'Report Rejected';
      case 'CLAIM_APPROVED':
        return 'Claim Approved';
      case 'CLAIM_REJECTED':
        return 'Claim Rejected';
      case 'MATCH_SUGGESTED':
      case 'MATCH_FOUND':
        return 'New Match Suggestion';
      case 'OTP_GENERATED':
        return 'Collection OTP';
      default:
        return type.isEmpty
            ? 'Notification'
            : type.replaceAll('_', ' ');
    }
  }

  IconData _iconFor(String type) {
    switch (type.toUpperCase()) {
      case 'REPORT_APPROVED':
      case 'CLAIM_APPROVED':
        return Icons.check_circle_outline;
      case 'REPORT_REJECTED':
      case 'CLAIM_REJECTED':
        return Icons.cancel_outlined;
      case 'MATCH_SUGGESTED':
      case 'MATCH_FOUND':
        return Icons.auto_awesome_outlined;
      case 'OTP_GENERATED':
        return Icons.password_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _timeLabel(dynamic raw) {
    if (raw == null) return '';
    final value = raw.toString();
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final local = date.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _unreadOnly
        ? _notifications.where(_isUnread).toList()
        : _notifications;

    return StudentShell(
      selectedPage: StudentPage.notifications,
      title: 'Notifications',
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Unread: $_unreadCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _loadNotifications,
                        icon: const Icon(Icons.refresh),
                      ),
                      TextButton(
                        onPressed: _loading || _updatingAll || _unreadCount == 0
                            ? null
                            : _markAllRead,
                        child: Text(_updatingAll ? 'Updating...' : 'Mark all read'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Unread only'),
                        selected: _unreadOnly,
                        onSelected: (value) {
                          setState(() => _unreadOnly = value);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _errorView()
                          : RefreshIndicator(
                              onRefresh: _loadNotifications,
                              child: visible.isEmpty
                                  ? ListView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        const SizedBox(height: 110),
                                        Icon(
                                          Icons.notifications_none_outlined,
                                          size: 60,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(height: 14),
                                        Center(
                                          child: Text(
                                            _unreadOnly
                                                ? 'No unread notifications.'
                                                : 'No notifications yet.',
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                                      itemCount: visible.length,
                                      itemBuilder: (context, index) {
                                        final item = visible[index];
                                        final type = '${item['notification_type'] ?? ''}';
                                        final unread = _isUnread(item);
                                        final id = _idOf(item);
                                        return Card(
                                          elevation: 0,
                                          color: unread
                                              ? _primary.withValues(alpha: 0.07)
                                              : Colors.white,
                                          margin: const EdgeInsets.only(bottom: 10),
                                          child: ListTile(
                                            onTap: unread ? () => _markRead(item) : null,
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            leading: Icon(_iconFor(type), color: _primary),
                                            title: Text(
                                              _titleFor(type),
                                              style: TextStyle(
                                                fontWeight: unread
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('${item['message'] ?? ''}'),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    _timeLabel(item['created_at']),
                                                    style: const TextStyle(fontSize: 11),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            trailing: id != null && _updatingIds.contains(id)
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : unread
                                                    ? Icon(Icons.circle, color: _primary, size: 10)
                                                    : const Icon(Icons.done, size: 17),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(_error ?? 'Failed to load notifications.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadNotifications,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

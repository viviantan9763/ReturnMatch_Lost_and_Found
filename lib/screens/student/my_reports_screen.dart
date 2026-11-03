import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';

/// Shows only the currently authenticated user's reports.
/// The backend GET /items returns private items only to their owner or an admin.
class MyReportsScreen extends StatefulWidget {
  final String itemType;

  const MyReportsScreen({super.key, required this.itemType})
      : assert(itemType == 'LOST' || itemType == 'FOUND');

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  String _text(Object? value, [String fallback = 'Not specified']) {
    final string = (value ?? '').toString().trim();
    return string.isEmpty ? fallback : string;
  }

  String _message(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) {
        return '${data['message']}';
      }
    } catch (_) {}
    return 'Unable to load reports (HTTP ${response.statusCode})';
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myId = int.tryParse('${AuthService.currentUser?['user_id'] ?? ''}');
      if (myId == null) {
        throw Exception('User session not found. Please sign in again.');
      }
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/items'),
        headers: AuthService.authenticatedHeaders(),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception(_message(response));
      final data = jsonDecode(response.body);
      if (data is! Map || data['items'] is! List) {
        throw const FormatException('Invalid item response');
      }
      final reports = (data['items'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((item) => int.tryParse('${item['reporter_id'] ?? ''}') == myId)
          .where((item) => '${item['item_type']}'.toUpperCase() == widget.itemType)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = reports;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showItem(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text(item['item_name'], 'Item Details')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detail('Type', item['item_type']),
                _detail('Status', item['status']),
                _detail('Publication', item['publication_status']),
                _detail('Category', item['category_name']),
                _detail('Location', item['location']),
                _detail('Model', item['model_info']),
                _detail('Colour', item['colour']),
                _detail('Event Date', item['event_date']),
                _detail('Description', item['description']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            )),
            const SizedBox(height: 3),
            Text(_text(value), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lost = widget.itemType == 'LOST';
    final title = lost ? 'My Lost Reports' : 'My Found Reports';
    return StudentShell(
      selectedPage: StudentPage.profile,
      title: title,
      child: Container(
        color: AppColors.background,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back to Profile',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(title, style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ))),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _loadReports,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, textAlign: TextAlign.center),
                                  TextButton.icon(
                                    onPressed: _loadReports,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ))
                          : _items.isEmpty
                              ? Center(child: Text(
                                  lost ? 'No lost-item reports yet.' : 'No found-item reports yet.',
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ))
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    return Card(
                                      color: Colors.white,
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.all(14),
                                        leading: CircleAvatar(
                                          backgroundColor: AppColors.studentSoft,
                                          child: Icon(
                                            lost ? Icons.search_off : Icons.inventory_2_outlined,
                                            color: AppColors.studentPrimary,
                                          ),
                                        ),
                                        title: Text(_text(item['item_name'])),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 5),
                                          child: Text(
                                            '${_text(item['category_name'])} • ${_text(item['location'])}\n'
                                            'Status: ${_text(item['status'])}  |  Publication: ${_text(item['publication_status'])}',
                                          ),
                                        ),
                                        isThreeLine: true,
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () => _showItem(item),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/student/student_shell.dart';
import 'claim_item_screen.dart';

class MatchDetailsScreen extends StatefulWidget {
  final int matchId;
  const MatchDetailsScreen({super.key, required this.matchId});

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  Map<String, dynamic>? _match;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMatch();
  }

  Future<void> _loadMatch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/matches/${widget.matchId}'),
        headers: AuthService.authenticatedHeaders(),
      );
      if (response.statusCode != 200) {
        String message = 'Unable to load match (HTTP ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['message'] != null) {
            message = decoded['message'].toString();
          }
        } catch (_) {}
        throw Exception(message);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _match = Map<String, dynamic>.from(data['match'] as Map);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _value(dynamic raw, {String fallback = 'Not provided'}) {
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _percent(dynamic raw) {
    final n = double.tryParse(raw?.toString() ?? '');
    if (n == null || !n.isFinite) return 'N/A';
    final pct = n <= 1 ? n * 100 : n;
    return '${pct.clamp(0, 100).toStringAsFixed(1)}%';
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  Widget _panel(String title, List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const Divider(height: 22),
        ...children,
      ],
    ),
  );

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadMatch, child: const Text('Retry')),
          ],
        ),
      );
    }
    final m = _match!;
    final highValue = _value(m['found_value_tier']).toUpperCase() == 'HIGH';
    final foundId = int.tryParse('${m['found_item_id'] ?? ''}');
    final foundStatus = _value(m['found_status']).toUpperCase();
    final canClaim =
        foundId != null &&
        ['ACTIVE', 'MATCHED', 'CLAIM_PENDING'].contains(foundStatus) &&
        _value(m['match_status']).toUpperCase() == 'SUGGESTED';
    final foundName = _value(m['found_item_name'], fallback: 'Found item');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _panel('AI Match Result', [
              Text(
                _percent(m['overall_similarity']),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.studentPrimary,
                ),
              ),
              const Text(
                'Overall similarity score · AI suggestion, not proof of ownership',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _detail('Match status', _value(m['match_status'])),
              _detail('Image similarity', _percent(m['image_similarity'])),
              _detail('Text similarity', _percent(m['text_similarity'])),
              _detail('Model similarity', _percent(m['model_similarity'])),
              _detail('Colour similarity', _percent(m['colour_similarity'])),
              _detail(
                'Category similarity',
                _percent(m['category_similarity']),
              ),
              _detail(
                'Location similarity',
                _percent(m['location_similarity']),
              ),
              _detail('Date similarity', _percent(m['date_similarity'])),
            ]),
            _panel('Your Lost Item', [
              _detail('Item name', _value(m['lost_item_name'])),
              _detail('Description', _value(m['lost_description'])),
              _detail('Location', _value(m['lost_location'])),
            ]),
            _panel('Potential Found Item', [
              _detail('Item name', foundName),
              if (!highValue)
                _detail('Description', _value(m['found_description'])),
              _detail('Location', _value(m['found_location'])),
              _detail('Value tier', _value(m['found_value_tier'])),
              if (highValue)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'High-value item: identifying details are hidden until ownership is verified.',
                    style: TextStyle(color: Colors.deepOrange, fontSize: 12),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canClaim
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClaimItemScreen(
                              itemId: foundId,
                              itemName: foundName,
                              valueTier: _value(
                                m['found_value_tier'],
                                fallback: 'NORMAL',
                              ),
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Proceed to Claim'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Claims require ownership verification and administrator approval.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StudentShell(
    selectedPage: StudentPage.home,
    title: 'Match Details',
    child: Container(color: AppColors.background, child: _content()),
  );
}

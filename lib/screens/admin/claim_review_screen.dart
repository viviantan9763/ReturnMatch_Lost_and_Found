import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/admin/admin_shell.dart';

class ClaimReviewScreen extends StatefulWidget {
  const ClaimReviewScreen({super.key});

  @override
  State<ClaimReviewScreen> createState() => _ClaimReviewScreenState();
}

class _ClaimReviewScreenState extends State<ClaimReviewScreen> {
  static const Color adminBlue = AppColors.adminPrimary;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  bool _isLoading = true;
  String? _errorMessage;
  String _selectedStatus = 'ALL';
  String _searchQuery = '';
  List<Map<String, dynamic>> _claims = [];

  final List<String> _statuses = const [
    'ALL',
    'PENDING',
    'VERIFICATION_REQUIRED',
    'APPROVED',
    'REJECTED',
    'COLLECTED',
  ];

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/claims'),
        headers: AuthService.authenticatedHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception(
          _extractMessage(response, fallback: 'Failed to load claims.'),
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawClaims = body['claims'];

      if (rawClaims is! List) {
        throw Exception('Invalid claim data returned by server.');
      }

      final claims = rawClaims
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _claims = claims;
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

  List<Map<String, dynamic>> get _filteredClaims {
    final query = _searchQuery.trim().toLowerCase();

    return _claims.where((claim) {
      final status = _text(claim['claim_status']).toUpperCase();
      final matchesStatus =
          _selectedStatus == 'ALL' || status == _selectedStatus;

      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final haystack = [
        claim['claim_id'],
        claim['item_id'],
        claim['item_name'],
        claim['claimant_name'],
        claim['claimant_email'],
        claim['claim_reason'],
      ].map(_text).join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  int _countStatus(String status) => _claims
      .where((claim) =>
          _text(claim['claim_status']).toUpperCase() == status)
      .length;

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedPage: AdminPage.claims,
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
            Icons.verified_user_outlined,
            color: adminBlue,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Claim Review',
                style: TextStyle(
                  color: textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Review ownership claims, security answers and collection verification.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadClaims,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _summarySection() {
    final cards = [
      _summaryCard('Total Claims', _claims.length.toString(),
          Icons.receipt_long_outlined),
      _summaryCard('Pending', _countStatus('PENDING').toString(),
          Icons.hourglass_top_rounded),
      _summaryCard(
          'Needs Review',
          _countStatus('VERIFICATION_REQUIRED').toString(),
          Icons.fact_check_outlined),
      _summaryCard('Approved', _countStatus('APPROVED').toString(),
          Icons.check_circle_outline_rounded),
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
              hintText: 'Search claim, item or claimant',
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
            items: _statuses
                .map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(status == 'ALL'
                        ? 'All Statuses'
                        : _formatStatus(status)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
              }
            },
          );

          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                search,
                const SizedBox(height: 10),
                filter,
              ],
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
        title: 'Unable to Load Claims',
        message: _errorMessage!,
        action: TextButton.icon(
          onPressed: _loadClaims,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    }

    if (_filteredClaims.isEmpty) {
      return _messageState(
        icon: Icons.inbox_outlined,
        title: 'No Claims Found',
        message: _claims.isEmpty
            ? 'No claim records are currently available.'
            : 'No claims match the selected filter or search.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadClaims,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _filteredClaims.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _claimCard(_filteredClaims[index]),
      ),
    );
  }

  Widget _claimCard(Map<String, dynamic> claim) {
    final status = _text(claim['claim_status']).toUpperCase();
    final tier = _text(claim['value_tier']).toUpperCase();
    final itemName = _fallback(claim['item_name'], 'Unknown Item');
    final claimant = _fallback(claim['claimant_name'], 'Unknown Claimant');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Column(
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
                          'Claim #${_fallback(claim['claim_id'], '—')} • Item #${_fallback(claim['item_id'], '—')}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusChip(status),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _meta(Icons.person_outline_rounded, claimant),
                  _meta(Icons.email_outlined,
                      _fallback(claim['claimant_email'], 'No email')),
                  _meta(Icons.workspace_premium_outlined,
                      tier == 'HIGH' ? 'High Value' : 'Medium Value'),
                  _meta(Icons.schedule_outlined,
                      _formatDateTime(claim['submitted_at'])),
                ],
              ),
              if (_text(claim['claim_reason']).trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Reason: ${_text(claim['claim_reason'])}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          );

          final action = FilledButton.icon(
            onPressed: () => _openClaimReview(claim),
            style: FilledButton.styleFrom(
              backgroundColor: adminBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
            ),
            icon: Icon(
              status == 'APPROVED'
                  ? Icons.password_outlined
                  : Icons.fact_check_outlined,
              size: 18,
            ),
            label: Text(status == 'APPROVED' ? 'Collection' : 'Review'),
          );

          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 14),
                action,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 18),
              action,
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _loadSecurityAnswers(int claimId) async {
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/claims/$claimId/security-answers'),
      headers: AuthService.authenticatedHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(
          response,
          fallback: 'Security answers are not available yet.',
        ),
      );
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Invalid security answer data returned by server.');
    }
    return body;
  }

  Future<void> _openClaimReview(Map<String, dynamic> claim) async {
    final claimId = int.tryParse(_text(claim['claim_id']));
    if (claimId == null) {
      _showMessage('Invalid claim ID.', isError: true);
      return;
    }

    final status = _text(claim['claim_status']).toUpperCase();

    if (status == 'APPROVED') {
      await _showOtpVerificationDialog(claim);
      return;
    }

    Map<String, dynamic>? answerData;
    String? loadError;

    try {
      answerData = await _loadSecurityAnswers(claimId);
    } catch (error) {
      loadError = error.toString().replaceFirst('Exception: ', '');
    }

    if (!mounted) return;

    final rawAnswers = answerData?['answers'];
    final answers = rawAnswers is List
        ? rawAnswers
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList()
        : <Map<String, dynamic>>[];

    final correctness = <int, bool?>{};
    for (final answer in answers) {
      final id = int.tryParse(_text(answer['answer_id']));
      if (id == null) continue;
      final raw = answer['is_correct'];
      if (raw == true || raw == 1 || raw == '1') {
        correctness[id] = true;
      } else if (raw == false || raw == 0 || raw == '0') {
        correctness[id] = false;
      } else {
        correctness[id] = null;
      }
    }

    final noteController = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canVerify = status == 'VERIFICATION_REQUIRED' &&
                answers.isNotEmpty &&
                correctness.values.every((value) => value != null);

            return AlertDialog(
              title: Text('Claim #$claimId Review'),
              content: SizedBox(
                width: 680,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 620),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dialogInfoRow('Item',
                            _fallback(claim['item_name'], 'Unknown Item')),
                        _dialogInfoRow('Claimant',
                            _fallback(claim['claimant_name'], 'Unknown')),
                        _dialogInfoRow('Email',
                            _fallback(claim['claimant_email'], '—')),
                        _dialogInfoRow('Value Tier',
                            _formatStatus(_text(claim['value_tier']))),
                        _dialogInfoRow('Status', _formatStatus(status)),
                        _dialogInfoRow('Submitted',
                            _formatDateTime(claim['submitted_at'])),
                        _dialogInfoRow('Claim Reason',
                            _fallback(claim['claim_reason'], '—')),
                        const SizedBox(height: 18),
                        const Text(
                          'Security Answers',
                          style: TextStyle(
                            color: textDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (loadError != null)
                          _inlineMessage(loadError!, isError: true)
                        else if (answers.isEmpty)
                          _inlineMessage(
                            'No security answers have been submitted for this claim.',
                          )
                        else
                          ...answers.map((answer) {
                            final id =
                                int.tryParse(_text(answer['answer_id']));
                            final question = _fallback(
                              answer['question_text'],
                              'Security question',
                            );
                            final response =
                                _fallback(answer['answer_text'], '—');

                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    question,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    response,
                                    style: const TextStyle(
                                      color: textDark,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (status == 'VERIFICATION_REQUIRED' &&
                                      id != null) ...[
                                    const SizedBox(height: 10),
                                    SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment(
                                          value: true,
                                          icon: Icon(Icons.check_rounded),
                                          label: Text('Correct'),
                                        ),
                                        ButtonSegment(
                                          value: false,
                                          icon: Icon(Icons.close_rounded),
                                          label: Text('Incorrect'),
                                        ),
                                      ],
                                      emptySelectionAllowed: true,
                                      selected: correctness[id] == null
                                          ? <bool>{}
                                          : <bool>{correctness[id]!},
                                      onSelectionChanged: (selection) {
                                        setDialogState(() {
                                          correctness[id] = selection.isEmpty
                                              ? null
                                              : selection.first;
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        if (status == 'VERIFICATION_REQUIRED') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: noteController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Verification Note (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (!canVerify && answers.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Mark every security answer as Correct or Incorrect before making a decision.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                        if (isSubmitting) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(color: adminBlue),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
                if (status == 'VERIFICATION_REQUIRED') ...[
                  OutlinedButton(
                    onPressed: !canVerify || isSubmitting
                        ? null
                        : () async {
                            setDialogState(() => isSubmitting = true);
                            final success = await _verifyClaim(
                              claimId: claimId,
                              decision: 'REJECTED',
                              note: noteController.text.trim(),
                              answers: answers,
                              correctness: correctness,
                            );
                            if (!mounted) return;
                            if (success) {
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              await _loadClaims();
                            } else if (dialogContext.mounted) {
                              setDialogState(() => isSubmitting = false);
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed: !canVerify || isSubmitting
                        ? null
                        : () async {
                            setDialogState(() => isSubmitting = true);
                            final success = await _verifyClaim(
                              claimId: claimId,
                              decision: 'APPROVED',
                              note: noteController.text.trim(),
                              answers: answers,
                              correctness: correctness,
                            );
                            if (!mounted) return;
                            if (success) {
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              await _loadClaims();
                            } else if (dialogContext.mounted) {
                              setDialogState(() => isSubmitting = false);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: adminBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Approve'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );

    noteController.dispose();
  }

  Future<bool> _verifyClaim({
    required int claimId,
    required String decision,
    required String note,
    required List<Map<String, dynamic>> answers,
    required Map<int, bool?> correctness,
  }) async {
    try {
      final reviewedAnswers = answers.map((answer) {
        final answerId = int.parse(_text(answer['answer_id']));
        return {
          'answer_id': answerId,
          'is_correct': correctness[answerId] == true,
        };
      }).toList();

      final response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/claims/$claimId/verify'),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'decision': decision,
          'verification_note': note.isEmpty ? null : note,
          'answers': reviewedAnswers,
        }),
      );

      if (response.statusCode != 200) {
        _showMessage(
          _extractMessage(response, fallback: 'Failed to verify claim.'),
          isError: true,
        );
        return false;
      }

      _showMessage(
        decision == 'APPROVED'
            ? 'Claim approved successfully.'
            : 'Claim rejected successfully.',
      );
      return true;
    } catch (error) {
      _showMessage('Unable to connect to server: $error', isError: true);
      return false;
    }
  }

  Future<void> _showOtpVerificationDialog(
    Map<String, dynamic> claim,
  ) async {
    final claimId = int.tryParse(_text(claim['claim_id']));
    if (claimId == null) return;

    final controller = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify Collection OTP'),
              content: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_fallback(claim['item_name'], 'Item')} • Claim #$claimId',
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter the one-time collection code presented by the claimant.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6-digit OTP',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    if (isSubmitting) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(color: adminBlue),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final code = controller.text.trim();
                          if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                            _showMessage(
                              'Please enter a valid 6-digit OTP.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          final success =
                              await _verifyOtp(claimId, code);

                          if (!mounted) return;
                          if (success) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            await _loadClaims();
                          } else if (dialogContext.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: adminBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Verify & Collect'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<bool> _verifyOtp(int claimId, String otpCode) async {
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/claims/$claimId/otp/verify'),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'otp_code': otpCode}),
      );

      if (response.statusCode != 200) {
        _showMessage(
          _extractMessage(response, fallback: 'OTP verification failed.'),
          isError: true,
        );
        return false;
      }

      _showMessage('OTP verified. Item collection completed.');
      return true;
    } catch (error) {
      _showMessage('Unable to connect to server: $error', isError: true);
      return false;
    }
  }

  Widget _dialogInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

  Widget _inlineMessage(String message, {bool isError = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.withValues(alpha: 0.05)
            : AppColors.adminSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.red.shade700 : AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
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

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 5),
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
            mainAxisAlignment: MainAxisAlignment.center,
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
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      case 'VERIFICATION_REQUIRED':
      case 'UNDER_REVIEW':
        return AppColors.warning;
      case 'COLLECTED':
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
    if (name.contains('phone') ||
        name.contains('iphone') ||
        name.contains('mobile')) {
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

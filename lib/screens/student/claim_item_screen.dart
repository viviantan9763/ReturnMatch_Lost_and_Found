import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';

class ClaimItemScreen extends StatefulWidget {
  final int itemId;
  final String itemName;
  final String valueTier;

  const ClaimItemScreen({
    super.key,
    required this.itemId,
    required this.itemName,
    required this.valueTier,
  });

  @override
  State<ClaimItemScreen> createState() =>
      _ClaimItemScreenState();
}

class _ClaimItemScreenState extends State<ClaimItemScreen> {
  static const Color studentOrange = AppColors.studentPrimary;
  static const Color background = AppColors.background;
  static const Color textDark = AppColors.textPrimary;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _claimReasonController =
      TextEditingController();

  final TextEditingController _answer1Controller =
      TextEditingController();

  final TextEditingController _answer2Controller =
      TextEditingController();

  final TextEditingController _answer3Controller =
      TextEditingController();

  bool _isSubmitting = false;
  bool _submitted = false;

  int? _createdClaimId;

  @override
  void dispose() {
    _claimReasonController.dispose();
    _answer1Controller.dispose();
    _answer2Controller.dispose();
    _answer3Controller.dispose();

    super.dispose();
  }

  // -------------------------------------------------------
  // SUBMIT CLAIM + SECURITY ANSWERS
  // -------------------------------------------------------

  Future<void> _submitClaim() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // ---------------------------------------------------
      // 1. CREATE CLAIM
      // POST /api/claims
      // ---------------------------------------------------

      final claimResponse = await http.post(
        Uri.parse(
          '${AuthService.baseUrl}/claims',
        ),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'item_id': widget.itemId,
          'claim_reason':
              _claimReasonController.text.trim(),
        }),
      );

      final claimBody =
          jsonDecode(claimResponse.body);

      if (claimResponse.statusCode != 201) {
        throw Exception(
          claimBody['message'] ??
              'Failed to submit claim',
        );
      }

      final claimData =
          Map<String, dynamic>.from(
        claimBody['claim'],
      );

      final int claimId =
          int.parse(
        claimData['claim_id'].toString(),
      );

      _createdClaimId = claimId;

      // ---------------------------------------------------
      // 2. SUBMIT SECURITY ANSWERS
      // POST /api/claims/:claimId/security-answers
      // ---------------------------------------------------

      final securityResponse = await http.post(
        Uri.parse(
          '${AuthService.baseUrl}/claims/$claimId/security-answers',
        ),
        headers: {
          ...AuthService.authenticatedHeaders(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'answers': [
            {
              'question_text':
                  'What colour is the item?',
              'answer_text':
                  _answer1Controller.text.trim(),
            },
            {
              'question_text':
                  'Describe any unique feature, mark, sticker or damage.',
              'answer_text':
                  _answer2Controller.text.trim(),
            },
            {
              'question_text':
                  'Provide another detail that can help verify ownership.',
              'answer_text':
                  _answer3Controller.text.trim(),
            },
          ],
        }),
      );

      final securityBody =
          jsonDecode(securityResponse.body);

      if (securityResponse.statusCode != 201) {
        throw Exception(
          securityBody['message'] ??
              'Claim was created, but security answers could not be submitted',
        );
      }

      if (!mounted) return;

      setState(() {
        _submitted = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Claim and security answers submitted successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst(
                  'Exception: ',
                  '',
                ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor:
            AppColors.studentPrimary,
        foregroundColor: Colors.white,
        elevation: 0,

        title: const Text(
          'Claim Item',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      body: _submitted
          ? _buildSuccessState()
          : _buildClaimForm(),
    );
  }

  // -------------------------------------------------------
  // CLAIM FORM
  // -------------------------------------------------------

  Widget _buildClaimForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),

      child: Form(
        key: _formKey,

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            _itemSummaryCard(),

            const SizedBox(height: 22),

            const Text(
              'Claim Reason',
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Explain why you believe this item belongs to you.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller:
                  _claimReasonController,
              maxLines: 4,

              decoration:
                  _inputDecoration(
                'Example: I lost this phone yesterday near the library.',
              ),

              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Claim reason is required';
                }

                return null;
              },
            ),

            const SizedBox(height: 24),

            const Text(
              'Security Verification',
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              widget.valueTier
                          .toUpperCase() ==
                      'HIGH'
                  ? 'This is a High Value item. Please provide detailed ownership information for administrator verification.'
                  : 'Provide ownership information to support your claim.',

              style: const TextStyle(
                color:
                    AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 18),

            _questionField(
              number: 1,
              question:
                  'What colour is the item?',
              controller:
                  _answer1Controller,
              hint:
                  'Example: Black',
            ),

            const SizedBox(height: 16),

            _questionField(
              number: 2,
              question:
                  'Describe any unique feature, mark, sticker or damage.',
              controller:
                  _answer2Controller,
              hint:
                  'Example: Small scratch near the camera',
            ),

            const SizedBox(height: 16),

            _questionField(
              number: 3,
              question:
                  'Provide another detail that can help verify ownership.',
              controller:
                  _answer3Controller,
              hint:
                  'Example: Black protective case with red sticker',
            ),

            const SizedBox(height: 22),

            _verificationInfoCard(),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(
                onPressed:
                    _isSubmitting
                        ? null
                        : _submitClaim,

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      studentOrange,

                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 16,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                ),

                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,

                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons
                            .verified_user_outlined,
                        color:
                            Colors.white,
                      ),

                label: Text(
                  _isSubmitting
                      ? 'Submitting...'
                      : 'Submit Claim',

                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // ITEM SUMMARY
  // -------------------------------------------------------

  Widget _itemSummaryCard() {
    final bool high =
        widget.valueTier
                .toUpperCase() ==
            'HIGH';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.studentPrimary,
            AppColors.studentDark,
          ],
        ),

        borderRadius:
            BorderRadius.circular(16),
      ),

      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,

            decoration: BoxDecoration(
              color: Colors.white
                  .withValues(
                alpha: 0.16,
              ),

              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),

            child: Icon(
              _itemIcon(
                widget.itemName,
              ),
              size: 32,
              color: Colors.white,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  widget.itemName,

                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Item ID: ${widget.itemId}',

                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 7),

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),

                  decoration: BoxDecoration(
                    color: Colors.white
                        .withValues(
                      alpha: 0.16,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),

                  child: Text(
                    high
                        ? 'HIGH VALUE'
                        : 'MEDIUM VALUE',

                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // QUESTION FIELD
  // -------------------------------------------------------

  Widget _questionField({
    required int number,
    required String question,
    required TextEditingController controller,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(12),

        border: Border.all(
          color: AppColors.border,
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          Text(
            'Question $number',

            style: const TextStyle(
              color:
                  AppColors.studentPrimary,
              fontSize: 11,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            question,

            style: const TextStyle(
              color: textDark,
              fontWeight:
                  FontWeight.w800,
            ),
          ),

          const SizedBox(height: 12),

          TextFormField(
            controller: controller,

            decoration:
                _inputDecoration(hint),

            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'Answer is required';
              }

              return null;
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // INFORMATION CARD
  // -------------------------------------------------------

  Widget _verificationInfoCard() {
    return Container(
      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color:
            const Color(0xFFFFF7ED),

        borderRadius:
            BorderRadius.circular(12),

        border: Border.all(
          color:
              const Color(0xFFFED7AA),
        ),
      ),

      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          Icon(
            Icons.security_outlined,
            color: Colors.orange,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Text(
              'Your answers will be reviewed by an administrator before the item can be collected. '
              'Do not include passwords, PINs or other highly sensitive information.',

              style: TextStyle(
                color: textDark,
                fontSize: 12,
                height: 1.4,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // SUCCESS STATE
  // -------------------------------------------------------

  Widget _buildSuccessState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),

        child: Container(
          constraints:
              const BoxConstraints(
            maxWidth: 500,
          ),

          padding: const EdgeInsets.all(28),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius:
                BorderRadius.circular(
              16,
            ),

            border: Border.all(
              color: AppColors.border,
            ),
          ),

          child: Column(
            mainAxisSize:
                MainAxisSize.min,

            children: [
              Container(
                width: 72,
                height: 72,

                decoration:
                    BoxDecoration(
                  color: AppColors.success
                      .withValues(
                    alpha: 0.10,
                  ),

                  shape:
                      BoxShape.circle,
                ),

                child: const Icon(
                  Icons
                      .check_circle_outline_rounded,
                  color:
                      AppColors.success,
                  size: 40,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Claim Submitted',

                style: TextStyle(
                  color: textDark,
                  fontSize: 22,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _createdClaimId == null
                    ? 'Your claim was submitted successfully.'
                    : 'Claim ID: $_createdClaimId',

                style: const TextStyle(
                  color:
                      AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Your security answers have been submitted and the claim is now waiting for administrator verification.',

                textAlign:
                    TextAlign.center,

                style: TextStyle(
                  color:
                      AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,

                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                    );
                  },

                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        studentOrange,

                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 14,
                    ),
                  ),

                  child: const Text(
                    'Done',

                    style: TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
  ) {
    return InputDecoration(
      hintText: hint,

      filled: true,

      fillColor:
          AppColors.background,

      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),

      focusedBorder:
          OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(10),

        borderSide:
            const BorderSide(
          color:
              AppColors.studentPrimary,
        ),
      ),
    );
  }

  IconData _itemIcon(
    String itemName,
  ) {
    final value =
        itemName.toLowerCase();

    if (value.contains('phone') ||
        value.contains('iphone')) {
      return Icons.smartphone_rounded;
    }

    if (value.contains('laptop')) {
      return Icons.laptop_mac_rounded;
    }

    if (value.contains('wallet')) {
      return Icons
          .account_balance_wallet_rounded;
    }

    if (value.contains('bag')) {
      return Icons.backpack_rounded;
    }

    return Icons.inventory_2_rounded;
  }
}
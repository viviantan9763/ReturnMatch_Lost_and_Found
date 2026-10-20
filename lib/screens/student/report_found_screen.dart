import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'package:image_picker/image_picker.dart';

import 'package:mime/mime.dart';

import 'package:http_parser/http_parser.dart';

import '../../constants/app_colors.dart';

import '../../services/auth_service.dart';

class ReportFoundScreen extends StatefulWidget {

  const ReportFoundScreen({super.key});

  @override

  State<ReportFoundScreen> createState() =>

      _ReportFoundScreenState();

}

class _ReportFoundScreenState

    extends State<ReportFoundScreen> {

  static const Color primaryOrange =

      AppColors.studentPrimary;

  static const Color lightOrange =

      AppColors.studentSoft;

  static const Color background =

      AppColors.background;

  static const Color textDark =

      AppColors.textPrimary;

  static const Color successGreen =

      AppColors.success;

  // =========================================================

  // FORM CONTROLLERS

  // =========================================================

  final TextEditingController _itemNameController =

      TextEditingController();

  final TextEditingController _modelController =

      TextEditingController();

  final TextEditingController _colourController =

      TextEditingController();

  final TextEditingController _locationController =

      TextEditingController();

  final TextEditingController _dateController =

      TextEditingController();

  final TextEditingController _descriptionController =

      TextEditingController();

  final List<TextEditingController> _privateQuestionControllers = [
    TextEditingController(), TextEditingController(),
  ];
  final List<TextEditingController> _privateAnswerControllers = [
    TextEditingController(), TextEditingController(),
  ];

  final ImagePicker _imagePicker = ImagePicker();

  // =========================================================

  // STATE

  // =========================================================

  List<Map<String, dynamic>> _categories = [];

  int? _selectedCategoryId;

  bool _isLoadingCategories = true;

  bool _isSubmitting = false;
  bool _isAnalyzing = false;

  // Actual result from Node.js -> FastAPI (never hard-coded).
  Map<String, dynamic>? _aiResult;
  String? _autoFilledDescription;
  int? _aiAppliedCategoryId;

  XFile? _selectedImage;

  Uint8List? _selectedImageBytes;

  // =========================================================

  // INIT

  // =========================================================

  @override

  void initState() {

    super.initState();

    _loadCategories();

  }

  // =========================================================

  // DISPOSE

  // =========================================================

  @override

  void dispose() {

    _itemNameController.dispose();

    _modelController.dispose();

    _colourController.dispose();

    _locationController.dispose();

    _dateController.dispose();

    _descriptionController.dispose();
    for (final controller in _privateQuestionControllers) {
      controller.dispose();
    }
    for (final controller in _privateAnswerControllers) {
      controller.dispose();
    }

    super.dispose();

  }

  // =========================================================

  // LOAD CATEGORIES FROM BACKEND

  // =========================================================

  Future<void> _loadCategories() async {

    try {

      final response = await http.get(

        Uri.parse(

          '${AuthService.baseUrl}/items/categories',

        ),

        headers:

            AuthService.authenticatedHeaders(),

      );

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data =

            jsonDecode(response.body)

                as Map<String, dynamic>;

        final rawCategories =

            data['categories'] as List? ?? [];

        final loadedCategories =

            rawCategories

                .map(

                  (item) =>

                      Map<String, dynamic>.from(

                    item as Map,

                  ),

                )

                .toList();

        setState(() {

          _categories = loadedCategories;

          if (_categories.isNotEmpty) {

            _selectedCategoryId =

                int.tryParse(

              _categories.first['category_id']

                  .toString(),

            );

          }

          _isLoadingCategories = false;

        });

      } else {

        setState(() {

          _isLoadingCategories = false;

        });

        ScaffoldMessenger.of(context)

            .showSnackBar(

          SnackBar(

            content: Text(

              _getMessage(

                response.body,

                'Failed to load item categories.',

              ),

            ),

          ),

        );

      }

    } catch (error) {

      if (!mounted) return;

      setState(() {

        _isLoadingCategories = false;

      });

      ScaffoldMessenger.of(context)

          .showSnackBar(

        SnackBar(

          content: Text(

            'Failed to load categories: $error',

          ),

        ),

      );

    }

  }

  // =========================================================

  // SELECT IMAGE

  // =========================================================

  // ---------------------------------------------------------
  // AI IMAGE ANALYSIS (CLIP category + BLIP description)
  // ---------------------------------------------------------

  // Called when the user selects a different image or removes it.
  // Clear AI-filled fields only if the student has not edited them.
  void _resetAiForImageChange() {
    if (_autoFilledDescription != null &&
        _descriptionController.text.trim() == _autoFilledDescription) {
      _descriptionController.clear();
    }

    if (_aiAppliedCategoryId != null &&
        _selectedCategoryId == _aiAppliedCategoryId) {
      _selectedCategoryId = null;
    }

    _aiResult = null;
    _autoFilledDescription = null;
    _aiAppliedCategoryId = null;
  }

  void _removeImage() {
    if (_isSubmitting || _isAnalyzing) return;

    setState(() {
      _resetAiForImageChange();
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  void _applyAiDescription() {
    if (_isSubmitting || _isAnalyzing) return;

    final description =
        _aiResult?['generated_description']?.toString().trim() ?? '';
    if (description.isEmpty) return;

    setState(() {
      _descriptionController.text = description;
      _autoFilledDescription = description;
    });

    _showMessage('AI description applied. Please review it before submitting.');
  }

  Future<void> _analyzeImage() async {
    if (_isSubmitting || _isAnalyzing) return;

    final image = _selectedImage;
    final bytes = _selectedImageBytes;

    if (image == null || bytes == null) {
      _showMessage('Please choose an image before using AI.');
      return;
    }

    if (_isLoadingCategories || _categories.isEmpty) {
      _showMessage('Please wait for item categories to load.');
      return;
    }

    final token = AuthService.authToken;
    if (token == null || token.isEmpty) {
      _showMessage('Please log in again to use AI analysis.');
      return;
    }

    if (bytes.length > 10 * 1024 * 1024) {
      _showMessage('Image is too large. Please choose an image under 10 MB.');
      return;
    }

    final mimeType = lookupMimeType(image.name, headerBytes: bytes);
    if (mimeType == null ||
        (mimeType != 'image/jpeg' &&
            mimeType != 'image/png' &&
            mimeType != 'image/webp')) {
      _showMessage('AI analysis supports JPEG, PNG and WEBP images only.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      // Node.js accepts multipart field "image" and forwards it to
      // FastAPI using the field name "file".
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.baseUrl}/ai/analyze-image'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: image.name,
          contentType: MediaType.parse(mimeType),
        ),
      );

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 130));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode != 200) {
        _showMessage(
          _getMessage(response.body, 'AI analysis failed. Please try again.'),
        );
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        _showMessage('The AI service returned an unexpected response.');
        return;
      }

      final suggestedCategory =
          decoded['suggested_category']?.toString().trim() ?? '';
      final generatedDescription =
          decoded['generated_description']?.toString().trim() ?? '';

      // Never hard-code category IDs: they come from MySQL.
      int? matchingCategoryId;
      for (final category in _categories) {
        final categoryName =
            category['category_name']?.toString().trim() ?? '';
        if (categoryName.toLowerCase() ==
            suggestedCategory.toLowerCase()) {
          matchingCategoryId =
              int.tryParse(category['category_id'].toString());
          break;
        }
      }

      setState(() {
        _aiResult = decoded;

        if (matchingCategoryId != null) {
          _selectedCategoryId = matchingCategoryId;
          _aiAppliedCategoryId = matchingCategoryId;
        } else {
          // Do not silently map an unknown AI category to an arbitrary ID.
          _selectedCategoryId = null;
          _aiAppliedCategoryId = null;
        }

        // Keep a description that the student has written or edited.
        final currentDescription = _descriptionController.text.trim();
        if (generatedDescription.isNotEmpty &&
            (currentDescription.isEmpty ||
                currentDescription == _autoFilledDescription)) {
          _descriptionController.text = generatedDescription;
          _autoFilledDescription = generatedDescription;
        }
      });

      if (matchingCategoryId == null) {
        _showMessage(
          'AI analysis complete. Please select a category manually: '
          '"$suggestedCategory" was not found in the category list.',
        );
      } else {
        _showMessage('AI analysis complete. Review the suggestions before submitting.');
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('AI analysis error: $error');
      _showMessage('Could not analyze the image. Check that both servers are running.');
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    if (_isSubmitting || _isAnalyzing) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;

      setState(() {
        _resetAiForImageChange();
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Failed to select image: $error');
    }
  }

  // =========================================================

  // UPLOAD IMAGE

  // =========================================================

  Future<bool> _uploadImage(

    int itemId,

  ) async {

    if (_selectedImage == null ||

        _selectedImageBytes == null) {

      return true;

    }

    try {

      final mimeType = lookupMimeType(

        _selectedImage!.name,

        headerBytes:

            _selectedImageBytes,

      );

      if (mimeType == null) {

        debugPrint(

          'Unable to detect image MIME type',

        );

        return false;

      }

      final request =

          http.MultipartRequest(

        'POST',

        Uri.parse(

          '${AuthService.baseUrl}/items/$itemId/images',

        ),

      );

      request.headers['Authorization'] =

          'Bearer ${AuthService.authToken}';

      request.files.add(

        http.MultipartFile.fromBytes(

          'image',

          _selectedImageBytes!,

          filename:

              _selectedImage!.name,

          contentType:

              MediaType.parse(

            mimeType,

          ),

        ),

      );

      final streamedResponse =

          await request.send();

      final response =

          await http.Response.fromStream(

        streamedResponse,

      );

      debugPrint(

        'Image upload status: ${response.statusCode}',

      );

      debugPrint(

        'Image upload response: ${response.body}',

      );

      return response.statusCode == 201;

    } catch (error) {

      debugPrint(

        'Image upload error: $error',

      );

      return false;

    }

  }

  // =========================================================

  // SUBMIT FOUND ITEM

  // =========================================================

  Future<void> _submitFoundItem() async {

    final itemName =

        _itemNameController.text.trim();

    final modelInfo =

        _modelController.text.trim();

    final colour =

        _colourController.text.trim();

    final location =

        _locationController.text.trim();

    final dateText =

        _dateController.text.trim();

    final description =

        _descriptionController.text.trim();

    // ---------------------------------------------------------

    // VALIDATION

    // ---------------------------------------------------------

    if (itemName.isEmpty) {

      _showMessage(

        'Please enter the item name.',

      );

      return;

    }

    if (_selectedCategoryId == null) {

      _showMessage(

        'Please select an item category.',

      );

      return;

    }

    if (modelInfo.isEmpty) {

      _showMessage(

        'Please enter the exact or approximate model. '

        'If you are unsure, enter "Not Sure".',

      );

      return;

    }

    if (location.isEmpty) {

      _showMessage(

        'Please enter where the item was found.',

      );

      return;

    }

    for (int i = 0; i < 2; i++) {
      final question = _privateQuestionControllers[i].text.trim();
      final answer = _privateAnswerControllers[i].text.trim();
      if (question.length < 8 || question.length > 250 ||
          answer.length < 2 || answer.length > 250) {
        _showMessage('Complete both private questions (8–250 characters) '
            'and answers (2–250 characters).');
        return;
      }
    }
    if (_privateQuestionControllers[0].text.trim().toLowerCase() ==
        _privateQuestionControllers[1].text.trim().toLowerCase()) {
      _showMessage('Please enter two different ownership questions.');
      return;
    }

    if (AuthService.authToken == null) {

      _showMessage(

        'Your login session is missing. '

        'Please login again.',

      );

      return;

    }

    String? formattedDate;

    if (dateText.isNotEmpty) {

      formattedDate =

          _convertDate(

        dateText,

      );

      if (formattedDate == null) {

        _showMessage(

          'Please use date format DD/MM/YYYY, '

          'for example 23/09/2026.',

        );

        return;

      }

    }

    setState(() {

      _isSubmitting = true;

    });

    try {

      // =====================================================

      // STEP 1: CREATE FOUND ITEM

      //

      // Student does NOT send value_tier.

      // Backend determines HIGH / MEDIUM from category.

      // =====================================================

      final response =

          await http.post(

        Uri.parse(

          '${AuthService.baseUrl}/items',

        ),

        headers:

            AuthService.authenticatedHeaders(),

        body: jsonEncode({

          'category_id':

              _selectedCategoryId,

          'item_name':

              itemName,

          'model_info':

              modelInfo,

          'colour':

              colour.isEmpty

                  ? null

                  : colour,

          'description':

              description.isEmpty

                  ? null

                  : description,

          'security_questions': List.generate(2, (i) => {
            'question': _privateQuestionControllers[i].text.trim(),
            'answer': _privateAnswerControllers[i].text.trim(),
          }),
          'item_type':

              'FOUND',

          'location':

              location,

          'event_date':

              formattedDate,

        }),

      );

      Map<String, dynamic> responseData = {};

      if (response.body.isNotEmpty) {

        try {

          responseData =

              jsonDecode(

            response.body,

          ) as Map<String, dynamic>;

        } catch (_) {

          responseData = {};

        }

      }

      if (!mounted) return;

      if (response.statusCode == 201) {

        final itemData =

            responseData['item']

                as Map<String, dynamic>?;

        final dynamic rawItemId =

            itemData?['item_id'];

        final int? itemId =

            rawItemId is int

                ? rawItemId

                : int.tryParse(

                    rawItemId

                            ?.toString() ??

                        '',

                  );

        if (itemId == null) {

          _showMessage(

            'Item was created, but item ID '

            'was not returned.',

          );

          return;

        }

        // ===================================================

        // STEP 2: UPLOAD IMAGE

        // ===================================================

        final imageUploaded =

            await _uploadImage(

          itemId,

        );

        if (!mounted) return;

        if (imageUploaded) {

          _showMessage(

            _selectedImage == null

                ? 'Found item reported successfully.'

                : 'Found item and image submitted successfully.',

          );

          _clearForm();

        } else {

          _showMessage(

            'Item was reported, but image upload failed.',

          );

        }

      } else {

        _showMessage(

          responseData['message']

                  ?.toString() ??

              'Failed to submit found item.',

        );

      }

    } catch (error) {

      if (!mounted) return;

      _showMessage(

        'Connection error: $error',

      );

    } finally {

      if (mounted) {

        setState(() {

          _isSubmitting = false;

        });

      }

    }

  }

  // =========================================================

  // DATE CONVERSION

  // DD/MM/YYYY -> YYYY-MM-DD

  // =========================================================

  String? _convertDate(

    String input,

  ) {

    try {

      final parts =

          input.split('/');

      if (parts.length != 3) {

        return null;

      }

      final day =

          int.parse(parts[0]);

      final month =

          int.parse(parts[1]);

      final year =

          int.parse(parts[2]);

      final date =

          DateTime(

        year,

        month,

        day,

      );

      if (date.day != day ||

          date.month != month ||

          date.year != year) {

        return null;

      }

      final dayText =

          day

              .toString()

              .padLeft(

                2,

                '0',

              );

      final monthText =

          month

              .toString()

              .padLeft(

                2,

                '0',

              );

      return '$year-$monthText-$dayText';

    } catch (_) {

      return null;

    }

  }

  // =========================================================

  // RESPONSE MESSAGE HELPER

  // =========================================================

  String _getMessage(

    String responseBody,

    String fallback,

  ) {

    try {

      final data =

          jsonDecode(

        responseBody,

      ) as Map<String, dynamic>;

      return data['message']

              ?.toString() ??

          fallback;

    } catch (_) {

      return fallback;

    }

  }

  // =========================================================

  // MESSAGE

  // =========================================================

  void _showMessage(

    String message,

  ) {

    if (!mounted) return;

    ScaffoldMessenger.of(context)

        .showSnackBar(

      SnackBar(

        content: Text(message),

      ),

    );

  }

  // =========================================================

  // CLEAR FORM

  // =========================================================

  void _clearForm() {

    _itemNameController.clear();

    _modelController.clear();

    _colourController.clear();

    _locationController.clear();

    _dateController.clear();

    _descriptionController.clear();
    for (final controller in _privateQuestionControllers) {
      controller.clear();
    }
    for (final controller in _privateAnswerControllers) {
      controller.clear();
    }

    setState(() {

      _selectedCategoryId =

          _categories.isNotEmpty

              ? int.tryParse(

                  _categories.first[

                          'category_id']

                      .toString(),

                )

              : null;

      _selectedImage = null;
      _selectedImageBytes = null;
      _aiResult = null;
      _autoFilledDescription = null;
      _aiAppliedCategoryId = null;

    });

  }

  // =========================================================

  // BUILD

  // =========================================================

  @override

  Widget build(

    BuildContext context,

  ) {

    return Scaffold(

      backgroundColor: background,

      appBar: AppBar(

        backgroundColor:

            AppColors.studentPrimary,

        foregroundColor:

            Colors.white,

        elevation: 0,

        title: const Text(

          'Report Found Item',

          style: TextStyle(

            color: Colors.white,

            fontWeight:

                FontWeight.w900,

          ),

        ),

      ),

      body: SingleChildScrollView(

        padding:

            const EdgeInsets.all(18),

        child: Column(

          crossAxisAlignment:

              CrossAxisAlignment.start,

          children: [

            _headerCard(),

            const SizedBox(

              height: 20,

            ),

            _imageUploadCard(),

            const SizedBox(

              height: 18,

            ),

            _aiDetectionCard(),

            const SizedBox(

              height: 20,

            ),

            _inputField(

              label:

                  'Item Name *',

              hint:

                  'Example: Black iPhone',

              controller:

                  _itemNameController,

            ),

            const SizedBox(

              height: 14,

            ),

            _dropdownField(),

            const SizedBox(

              height: 14,

            ),

            _inputField(

              label:

                  'Model / Approximate Model *',

              hint:

                  'Example: iPhone 15 Series, ASUS Vivobook, or Not Sure',

              controller:

                  _modelController,

            ),

            const SizedBox(

              height: 14,

            ),

            _inputField(

              label:

                  'Colour',

              hint:

                  'Example: Black, Silver, Dark Blue',

              controller:

                  _colourController,

            ),

            const SizedBox(

              height: 14,

            ),

            _inputField(

              label:

                  'Location Found *',

              hint:

                  'Example: Library Level 2',

              controller:

                  _locationController,

            ),

            const SizedBox(

              height: 14,

            ),

            _inputField(

              label:

                  'Date Found',

              hint:

                  'Example: 23/09/2026',

              controller:

                  _dateController,

            ),

            const SizedBox(

              height: 14,

            ),

            _descriptionField(),
            const SizedBox(height: 20),
            _privateOwnershipQuestionsCard(),

            const SizedBox(

              height: 24,

            ),

            SizedBox(

              width:

                  double.infinity,

              height: 55,

              child:

                  ElevatedButton.icon(

                onPressed: (_isSubmitting || _isAnalyzing ||
                            _isLoadingCategories)
                        ? null

                        : _submitFoundItem,

                icon:

                    _isSubmitting

                        ? const SizedBox(

                            width: 20,

                            height: 20,

                            child:

                                CircularProgressIndicator(

                              strokeWidth:

                                  2,

                              color:

                                  Colors.white,

                            ),

                          )

                        : const Icon(

                            Icons

                                .send_rounded,

                            color:

                                Colors.white,

                          ),

                label: Text(

                  _isSubmitting

                      ? 'Submitting...'

                      : 'Submit Found Report',

                  style:

                      const TextStyle(

                    color:

                        Colors.white,

                    fontWeight:

                        FontWeight.w800,

                  ),

                ),

                style:

                    ElevatedButton

                        .styleFrom(

                  backgroundColor:

                      primaryOrange,

                  disabledBackgroundColor:

                      primaryOrange

                          .withValues(

                    alpha: 0.6,

                  ),

                  shape:

                      RoundedRectangleBorder(

                    borderRadius:

                        BorderRadius

                            .circular(

                      16,

                    ),

                  ),

                ),

              ),

            ),

          ],

        ),

      ),

    );

  }

  // =========================================================

  // HEADER

  // =========================================================

  Widget _privateOwnershipQuestionsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lock_outline_rounded, color: primaryOrange),
            SizedBox(width: 10),
            Expanded(child: Text('Private Ownership Verification',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Set two questions about details that are NOT visible in the '
            'public item photo or description. The claimant will answer '
            'these questions. Keep the reference answers private.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 2; i++) ...[
            Text('Question ${i + 1} *',
              style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _privateQuestionControllers[i],
              enabled: !_isSubmitting,
              maxLength: 250,
              decoration: InputDecoration(
                hintText: 'E.g. What is the hidden marking inside?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            Text('Reference Answer ${i + 1} *',
              style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _privateAnswerControllers[i],
              enabled: !_isSubmitting,
              maxLength: 250,
              decoration: InputDecoration(
                hintText: 'Only the system should use this answer',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (i == 0) const Divider(height: 30),
          ],
          const Text(
            'Avoid easily guessed answers (colour, visible brand, etc.). '
            'Only record details you actually checked.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {

    return Container(

      width:

          double.infinity,

      padding:

          const EdgeInsets.all(

        20,

      ),

      decoration:

          BoxDecoration(

        gradient:

            const LinearGradient(

          colors: [

            successGreen,

            AppColors.studentDark,

          ],

        ),

        borderRadius:

            BorderRadius.circular(

          22,

        ),

      ),

      child:

          const Column(

        crossAxisAlignment:

            CrossAxisAlignment.start,

        children: [

          Icon(

            Icons

                .inventory_2_outlined,

            color:

                Colors.white,

            size: 34,

          ),

          SizedBox(

            height: 12,

          ),

          Text(

            'Found an item?',

            style: TextStyle(

              color:

                  Colors.white,

              fontSize: 22,

              fontWeight:

                  FontWeight.w900,

            ),

          ),

          SizedBox(

            height: 8,

          ),

          Text(

            'Upload a clear image and provide the item details to help identify its owner.',

            style: TextStyle(

              color:

                  Colors.white,

              fontSize: 13,

              height: 1.4,

            ),

          ),

        ],

      ),

    );

  }

  // =========================================================

  // IMAGE UPLOAD

  // =========================================================

  Widget _imageUploadCard() {

    return Container(

      width:

          double.infinity,

      padding:

          const EdgeInsets.all(

        22,

      ),

      decoration:

          BoxDecoration(

        color:

            Colors.white,

        borderRadius:

            BorderRadius.circular(

          20,

        ),

        border:

            Border.all(

          color:

              AppColors.border,

        ),

      ),

      child:

          Column(

        children: [

          if (_selectedImageBytes ==

              null)

            Container(

              width: 100,

              height: 100,

              decoration:

                  BoxDecoration(

                color:

                    lightOrange,

                borderRadius:

                    BorderRadius

                        .circular(

                  20,

                ),

              ),

              child:

                  const Icon(

                Icons

                    .camera_alt_outlined,

                color:

                    primaryOrange,

                size: 48,

              ),

            )

          else

            ClipRRect(

              borderRadius:

                  BorderRadius

                      .circular(

                16,

              ),

              child:

                  Image.memory(

                _selectedImageBytes!,

                width:

                    double.infinity,

                height: 230,

                fit:

                    BoxFit.cover,

              ),

            ),

          const SizedBox(

            height: 14,

          ),

          const Text(

            'Upload Item Image',

            style:

                TextStyle(

              fontSize: 18,

              fontWeight:

                  FontWeight.w900,

              color:

                  textDark,

            ),

          ),

          const SizedBox(

            height: 8,

          ),

          Text(

            _selectedImage ==

                    null

                ? 'Add a clear photo of the found item to improve image recognition and matching accuracy.'

                : _selectedImage!

                    .name,

            textAlign:

                TextAlign.center,

            style:

                const TextStyle(

              color:

                  AppColors

                      .textSecondary,

            ),

          ),

          const SizedBox(

            height: 14,

          ),

          SizedBox(

            width:

                double.infinity,

            child:

                ElevatedButton.icon(

              onPressed: (_isSubmitting || _isAnalyzing)
                    ? null
                    : _pickImage,

              icon:

                  Icon(

                _selectedImage ==

                        null

                    ? Icons.upload

                    : Icons

                        .change_circle_outlined,

              ),

              label:

                  Text(

                _selectedImage ==

                        null

                    ? 'Choose Image'

                    : 'Change Image',

              ),

              style:

                  ElevatedButton

                      .styleFrom(

                backgroundColor:

                    primaryOrange,

                foregroundColor:

                    Colors.white,

                padding:

                    const EdgeInsets

                        .symmetric(

                  vertical: 14,

                ),

              ),

            ),

          ),

          if (_selectedImage !=

              null) ...[

            const SizedBox(

              height: 6,

            ),

            TextButton.icon(
                  onPressed: (_isSubmitting || _isAnalyzing)
                      ? null
                      : _removeImage,
                

              icon:

                  const Icon(

                Icons

                    .delete_outline,

              ),

              label:

                  const Text(

                'Remove Image',

              ),

            ),

          ],

        ],

      ),

    );

  }

  // =========================================================

  // AI INFORMATION CARD

  // =========================================================

  Widget _aiDetectionCard() {
    final result = _aiResult;
    final category = result?['suggested_category']?.toString() ?? '';
    final description = result?['generated_description']?.toString() ?? '';
    final rawScore = result?['relative_score_percent'];
    final score = rawScore is num
        ? rawScore.toDouble()
        : double.tryParse(rawScore?.toString() ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: successGreen),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI Image Recognition',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'CLIP suggests an item category and BLIP generates an image '
            'description. These are suggestions, not verified item details. '
            'Please review and edit them before submitting.',
            style: TextStyle(
              color: textDark,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_selectedImageBytes == null ||
                      _isAnalyzing ||
                      _isSubmitting ||
                      _isLoadingCategories ||
                      _categories.isEmpty)
                  ? null
                  : _analyzeImage,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _isAnalyzing
                    ? 'Analyzing image...'
                    : result == null
                        ? 'Analyze with AI'
                        : 'Analyze Again',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: successGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_selectedImageBytes == null) ...[
            const SizedBox(height: 8),
            const Text(
              'Choose an image above to enable AI analysis.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text(
              'Suggested Category',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              category.isEmpty ? 'Not available' : category,
              style: const TextStyle(
                color: textDark,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (score != null) ...[
              const SizedBox(height: 4),
              Text(
                'CLIP relative category score: ${score.toStringAsFixed(2)}% '
                '(not model accuracy)',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'AI Generated Description',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description.isEmpty ? 'No description generated.' : description,
              style: const TextStyle(
                color: textDark,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: (_isAnalyzing || _isSubmitting)
                    ? null
                    : _applyAiDescription,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Use AI Description'),
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'You can change the category and edit the description '
              'in the form before submission.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }


  // =========================================================

  // CATEGORY

  // =========================================================

  Widget _dropdownField() {

    return Column(

      crossAxisAlignment:

          CrossAxisAlignment.start,

      children: [

        const Text(

          'Category *',

          style:

              TextStyle(

            color:

                textDark,

            fontWeight:

                FontWeight.w800,

          ),

        ),

        const SizedBox(

          height: 8,

        ),

        Container(

          width:

              double.infinity,

          padding:

              const EdgeInsets

                  .symmetric(

            horizontal: 14,

          ),

          decoration:

              BoxDecoration(

            color:

                Colors.white,

            borderRadius:

                BorderRadius

                    .circular(

              14,

            ),

            border:

                Border.all(

              color:

                  AppColors.border,

            ),

          ),

          child:

              _isLoadingCategories

                  ? const Padding(

                      padding:

                          EdgeInsets

                              .symmetric(

                        vertical: 14,

                      ),

                      child:

                          Row(

                        children: [

                          SizedBox(

                            width: 18,

                            height: 18,

                            child:

                                CircularProgressIndicator(

                              strokeWidth:

                                  2,

                            ),

                          ),

                          SizedBox(

                            width: 12,

                          ),

                          Text(

                            'Loading categories...',

                          ),

                        ],

                      ),

                    )

                  : _categories.isEmpty

                      ? const Padding(

                          padding:

                              EdgeInsets

                                  .symmetric(

                            vertical:

                                14,

                          ),

                          child:

                              Text(

                            'No categories available',

                          ),

                        )

                      : DropdownButtonHideUnderline(

                          child:

                              DropdownButton<

                                  int>(

                            value:

                                _selectedCategoryId,

                            isExpanded:

                                true,

                            hint:

                                const Text(

                              'Select category',

                            ),

                            items:

                                _categories

                                    .map(

                              (

                                category,

                              ) {

                                final categoryId =

                                    int.parse(

                                  category[

                                          'category_id']

                                      .toString(),

                                );

                                final categoryName =

                                    category[

                                            'category_name']

                                        .toString();

                                return DropdownMenuItem<

                                    int>(

                                  value:

                                      categoryId,

                                  child:

                                      Text(

                                    categoryName,

                                  ),

                                );

                              },

                            ).toList(),

                            onChanged: (_isSubmitting || _isAnalyzing)
                                    ? null

                                    : (

                                        value,

                                      ) {

                                        setState(

                                          () {

                                            _selectedCategoryId =

                                                value;
                                              _aiAppliedCategoryId = null;

                                          },

                                        );

                                      },

                          ),

                        ),

        ),

      ],

    );

  }

  // =========================================================

  // INPUT FIELD

  // =========================================================

  Widget _inputField({

    required String label,

    required String hint,

    required TextEditingController

        controller,

  }) {

    return Column(

      crossAxisAlignment:

          CrossAxisAlignment.start,

      children: [

        Text(

          label,

          style:

              const TextStyle(

            color:

                textDark,

            fontWeight:

                FontWeight.w800,

          ),

        ),

        const SizedBox(

          height: 8,

        ),

        TextField(

          controller:

              controller,

          decoration:

              InputDecoration(

            hintText:

                hint,

            filled:

                true,

            fillColor:

                Colors.white,

            contentPadding:

                const EdgeInsets

                    .symmetric(

              horizontal:

                  14,

              vertical:

                  14,

            ),

            border:

                OutlineInputBorder(

              borderRadius:

                  BorderRadius

                      .circular(

                14,

              ),

              borderSide:

                  const BorderSide(

                color:

                    AppColors.border,

              ),

            ),

            enabledBorder:

                OutlineInputBorder(

              borderRadius:

                  BorderRadius

                      .circular(

                14,

              ),

              borderSide:

                  const BorderSide(

                color:

                    AppColors.border,

              ),

            ),

            focusedBorder:

                OutlineInputBorder(

              borderRadius:

                  BorderRadius

                      .circular(

                14,

              ),

              borderSide:

                  const BorderSide(

                color:

                    primaryOrange,

                width:

                    1.5,

              ),

            ),

          ),

        ),

      ],

    );

  }

  // =========================================================

  // DESCRIPTION

  // =========================================================

  Widget _descriptionField() {

    return Column(

      crossAxisAlignment:

          CrossAxisAlignment.start,

      children: [

        Row(

          children: [

            const Expanded(

              child:

                  Text(

                'Description',

                style:

                    TextStyle(

                  color:

                      textDark,

                  fontWeight:

                      FontWeight.w800,

                ),

              ),

            ),

            Container(

              padding:

                  const EdgeInsets

                      .symmetric(

                horizontal:

                    9,

                vertical:

                    4,

              ),

              decoration:

                  BoxDecoration(

                color:

                    lightOrange,

                borderRadius:

                    BorderRadius

                        .circular(

                  20,

                ),

              ),

              child:

                  const Text(

                'AI-ready',

                style:

                    TextStyle(

                  color:

                      primaryOrange,

                  fontSize:

                      11,

                  fontWeight:

                      FontWeight.w800,

                ),

              ),

            ),

          ],

        ),

        const SizedBox(

          height:

              8,

        ),

        TextField(

          controller:

              _descriptionController,

          maxLines:

              4,

          decoration:

              InputDecoration(

            hintText:

                'Description can be reviewed and edited before submission.',

            filled:

                true,

            fillColor:

                Colors.white,

            border:

                OutlineInputBorder(

              borderRadius:

                  BorderRadius

                      .circular(

                14,

              ),

              borderSide:

                  const BorderSide(

                color:

                    AppColors.border,

              ),

            ),

            enabledBorder:

                OutlineInputBorder(

              borderRadius:

                  BorderRadius

                      .circular(

                14,

              ),

              borderSide:

                  const BorderSide(

                color:

                    AppColors.border,

              ),

            ),

            focusedBorder:

                OutlineInputBorder(

              borderRadius:

                  BorderRadius

                      .circular(

                14,

              ),

              borderSide:

                  const BorderSide(

                color:

                    primaryOrange,

                width:

                    1.5,

              ),

            ),

          ),

        ),

      ],

    );

  }

}
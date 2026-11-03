import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Use image_picker's already-installed platform interface solely as a test fake.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/services/report_submission_service.dart';
import 'package:my_app/screens/student/report_lost_screen.dart';
import 'package:my_app/screens/student/report_found_screen.dart';
import 'package:my_app/screens/student/student_home_screen.dart';
import 'package:my_app/screens/student/match_details_screen.dart';
import 'package:my_app/screens/student/claim_item_screen.dart';
import 'package:my_app/widgets/authenticated_item_image.dart';
import 'package:my_app/widgets/student/student_shell.dart';

// Synthetic HTTP and picker data. Never connects to a server or database.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _Picker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(_png, name: 'synthetic.png', mimeType: 'image/png');
}

class _Server {
  final requests = <http.Request>[];
  String publication = 'PUBLISHED';
  FutureOr<http.Response?> Function(http.Request)? intercept;
  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );
  int count(String suffix, [String method = 'POST']) => requests
      .where((r) => r.method == method && r.url.path.endsWith(suffix))
      .length;
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final overridden = await intercept?.call(r);
    if (overridden != null) return overridden;
    if (r.url.path.endsWith('/items/categories')) {
      return json({
        'categories': [
          {'category_id': 1, 'category_name': 'Bottle'},
        ],
      });
    }
    if (r.url.path.endsWith('/ai/analyze-image')) {
      return json({
        'success': true,
        'suggested_category': 'Bottle',
        'relative_score_percent': 88.0,
        'generated_description': 'A synthetic blue bottle',
        'top_predictions': [
          {'category': 'Bottle', 'score_percent': 88.0},
        ],
      });
    }
    if (r.url.path.endsWith('/items') && r.method == 'POST') {
      return json({
        'item': {'item_id': 55, 'publication_status': publication},
      }, 201);
    }
    if (r.url.path.endsWith('/items/55/images')) {
      return json({
        'image': {'image_id': 5, 'item_id': 55},
        'publication_status': publication,
      }, 201);
    }
    if (r.url.path.endsWith('/items/55/images/5')) {
      return http.Response.bytes(
        _png,
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    if (r.url.path.endsWith('/items/55/run')) {
      return json({
        'result': {'errors': 0, 'saved': 1},
      });
    }
    if (r.url.path.endsWith('/matches/my')) {
      return json({
        'matches': [
          {
            'match_id': 9,
            'found_item_id': 2,
            'found_item_name': 'Synthetic recommendation',
            'lost_item_name': 'Synthetic report',
            'found_value_tier': 'MEDIUM',
            'overall_similarity': '0.8750',
          },
        ],
      });
    }
    if (r.url.path.endsWith('/matches/9')) {
      return json({
        'match': {
          'match_id': 9,
          'found_item_id': 2,
          'found_item_name': 'Synthetic recommendation',
          'found_value_tier': 'MEDIUM',
          'found_status': 'ACTIVE',
          'match_status': 'SUGGESTED',
          'overall_similarity': '0.8750',
          'image_similarity': '0.9000',
          'text_similarity': '0.8000',
          'model_similarity': null,
          'colour_similarity': '1.0000',
        },
      });
    }
    throw StateError('Unexpected mock request: ${r.method} ${r.url.path}');
  }
}

Map<String, dynamic> _payload([String type = 'LOST']) => {
  'item_type': type,
  'item_name': 'Synthetic report',
  'category_id': 1,
  if (type == 'FOUND')
    'security_questions': [
      {'question': 'What is inside?', 'answer': 'Synthetic'},
      {'question': 'What is marked?', 'answer': 'Synthetic'},
    ],
};
Future<void> _withServer(_Server server, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(server.handle));
Future<void> _tap(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }
  final finder = find.text(label).first;
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _page(
  WidgetTester tester,
  _Server server,
  Widget page,
  Future<void> Function() scenario,
) async {
  tester.view.physicalSize = const Size(1200, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await _withServer(server, () async {
    try {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
      await scenario();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AuthService.authToken = 'synthetic-session';
    AuthService.currentUser = {'user_id': 7, 'role': 'USER'};
  });
  tearDown(() {
    AuthService.logout();
    debugDefaultTargetPlatformOverride = null;
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    test('all API operations share the ${platform.name} base URL', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        AuthService.baseUrl,
        platform == TargetPlatform.android
            ? 'http://10.0.2.2:3000/api'
            : 'http://localhost:3000/api',
      );
      final server = _Server();
      await _withServer(server, () async {
        await ReportSubmission().submit(
          _payload(),
          imageBytes: _png,
          imageName: 'synthetic.png',
        );
      });
      expect(server.requests.map((r) => r.url.host).toSet(), {
        Uri.parse(AuthService.baseUrl).host,
      });
    });
  }
  for (final type in ['LOST', 'FOUND']) {
    test(
      '$type request order is create -> upload -> matching with deferred triggers',
      () async {
        final server = _Server();
        await _withServer(server, () async {
          await ReportSubmission().submit(
            _payload(type),
            imageBytes: _png,
            imageName: 'synthetic.png',
          );
        });
        expect(server.requests.map((r) => r.url.path), [
          '/api/items',
          '/api/items/55/images',
          '/api/matches/items/55/run',
        ]);
        expect(jsonDecode(server.requests.first.body)['defer_matching'], true);
        expect(jsonDecode(server.requests.first.body)['image_pending'], true);
        expect(
          utf8.decode(server.requests[1].bodyBytes, allowMalformed: true),
          contains('defer_matching'),
        );
      },
    );
  }
  test(
    'failed upload retries the saved report ID without another creation',
    () async {
      final server = _Server();
      var failures = 1;
      server.intercept = (r) => r.url.path.endsWith('/images') && failures-- > 0
          ? server.json({'message': 'Synthetic upload outage'}, 503)
          : null;
      final submission = ReportSubmission();
      await _withServer(server, () async {
        await expectLater(
          submission.submit(
            _payload(),
            imageBytes: _png,
            imageName: 'test.png',
          ),
          throwsException,
        );
        expect(submission.itemId, 55);
        await submission.submit(
          _payload(),
          imageBytes: _png,
          imageName: 'test.png',
        );
      });
      expect(server.count('/items'), 1);
      expect(server.count('/images'), 2);
      expect(server.count('/run'), 1);
    },
  );
  test(
    'matching failure retries only matching and preserves successful upload',
    () async {
      final server = _Server();
      var failures = 1;
      server.intercept = (r) => r.url.path.endsWith('/run') && failures-- > 0
          ? server.json({'message': 'AI unavailable'}, 503)
          : null;
      final submission = ReportSubmission();
      await _withServer(server, () async {
        await expectLater(
          submission.submit(
            _payload(),
            imageBytes: _png,
            imageName: 'test.png',
          ),
          throwsException,
        );
        await submission.submit(
          _payload(),
          imageBytes: _png,
          imageName: 'test.png',
        );
      });
      expect(server.count('/items'), 1);
      expect(server.count('/images'), 1);
      expect(server.count('/run'), 2);
    },
  );
  test(
    'lost upload response retries the same report and identical bytes',
    () async {
      final server = _Server();
      var failures = 1;
      server.intercept = (r) {
        if (r.url.path.endsWith('/images') && failures-- > 0) {
          throw http.ClientException('Synthetic lost response');
        }
        return null;
      };
      final submission = ReportSubmission();
      await _withServer(server, () async {
        await expectLater(
          submission.submit(
            _payload(),
            imageBytes: _png,
            imageName: 'test.png',
          ),
          throwsException,
        );
        await submission.submit(
          _payload(),
          imageBytes: _png,
          imageName: 'test.png',
        );
      });
      expect(server.count('/items'), 1);
      expect(server.count('/images'), 2);
    },
  );
  for (final failure in [
    'lost response',
    'malformed success',
    'server error',
  ]) {
    test(
      'uncertain creation: $failure prevents blind creation retry',
      () async {
        final server = _Server();
        server.intercept = (r) {
          if (r.url.path.endsWith('/items')) {
            if (failure == 'lost response') {
              throw http.ClientException('Synthetic lost response');
            }
            return failure == 'malformed success'
                ? server.json({'item': {}}, 201)
                : server.json({'message': 'Synthetic error'}, 500);
          }
          return null;
        };
        final submission = ReportSubmission();
        await _withServer(server, () async {
          await expectLater(submission.submit(_payload()), throwsException);
          await expectLater(submission.submit(_payload()), throwsException);
        });
        expect(server.count('/items'), 1);
      },
    );
  }
  test(
    'oversized and unsupported images fail before report creation',
    () async {
      final server = _Server();
      await _withServer(server, () async {
        for (final bytes in [
          Uint8List(6 * 1024 * 1024),
          Uint8List.fromList([1, 2, 3]),
        ]) {
          await expectLater(
            ReportSubmission().submit(
              _payload(),
              imageBytes: bytes,
              imageName: 'test.bin',
            ),
            throwsException,
          );
        }
      });
      expect(server.requests, isEmpty);
    },
  );
  test(
    'HIGH report remains pending review without matching before publication',
    () async {
      final server = _Server()..publication = 'PENDING_REVIEW';
      await _withServer(server, () async {
        final submission = ReportSubmission();
        await submission.submit(
          _payload('FOUND'),
          imageBytes: _png,
          imageName: 'test.png',
        );
        expect(submission.publicationStatus, 'PENDING_REVIEW');
      });
      expect(server.count('/images'), 1);
      expect(server.count('/run'), 0);
    },
  );
  test('session change stops later upload/matching operations', () async {
    final server = _Server();
    server.intercept = (r) {
      if (r.url.path.endsWith('/items')) {
        AuthService.authToken = 'another-session';
      }
      return null;
    };
    await _withServer(server, () async {
      await expectLater(
        ReportSubmission().submit(
          _payload(),
          imageBytes: _png,
          imageName: 'test.png',
        ),
        throwsException,
      );
    });
    expect(server.count('/images'), 0);
    expect(server.count('/run'), 0);
  });
  testWidgets(
    'authorized image delivery attaches bearer header and renders image bytes',
    (tester) async {
      final server = _Server();
      await _page(
        tester,
        server,
        AuthenticatedItemImage(
          url: '${AuthService.baseUrl}/items/55/images/5',
          placeholder: const Text('placeholder'),
        ),
        () async {
          expect(find.byType(Image), findsOneWidget);
          expect(
            server.requests.single.headers['Authorization'],
            'Bearer synthetic-session',
          );
        },
      );
    },
  );
  testWidgets('image widget never sends a bearer token to a foreign origin', (
    tester,
  ) async {
    final server = _Server();
    await _page(
      tester,
      server,
      const AuthenticatedItemImage(
        url: 'https://foreign.invalid/api/items/55/images/5',
        placeholder: Text('placeholder'),
      ),
      () async {
        expect(find.text('placeholder'), findsOneWidget);
        expect(server.requests, isEmpty);
      },
    );
  });
  testWidgets('image API errors retain existing placeholder', (tester) async {
    final server = _Server();
    server.intercept = (r) => server.json({'message': 'Not found'}, 404);
    await _page(
      tester,
      server,
      AuthenticatedItemImage(
        url: '${AuthService.baseUrl}/items/55/images/5',
        placeholder: const Text('placeholder'),
      ),
      () async {
        expect(find.text('placeholder'), findsOneWidget);
      },
    );
  });
  for (final found in [false, true]) {
    testWidgets(
      '${found ? 'Found' : 'Lost'} form -> selected image -> AI suggestions -> saved report',
      (tester) async {
        final previousPicker = ImagePickerPlatform.instance;
        ImagePickerPlatform.instance = _Picker();
        addTearDown(() => ImagePickerPlatform.instance = previousPicker);
        final server = _Server();
        await _page(
          tester,
          server,
          found ? const ReportFoundScreen() : const ReportLostScreen(),
          () async {
            expect(find.byType(StudentShell), findsOneWidget);
            final fields = find.byType(TextField);
            await tester.enterText(fields.at(0), 'Synthetic report');
            await tester.enterText(fields.at(3), 'Synthetic campus');
            if (found) {
              final questions = find.widgetWithText(
                TextField,
                'E.g. What is the hidden marking inside?',
              );
              final answers = find.widgetWithText(
                TextField,
                'Only the system should use this answer',
              );
              for (var i = 0; i < 2; i++) {
                await tester.ensureVisible(questions.at(i));
                await tester.enterText(
                  questions.at(i),
                  i == 0
                      ? 'What is hidden inside?'
                      : 'What is the hidden mark?',
                );
                await tester.ensureVisible(answers.at(i));
                await tester.enterText(answers.at(i), 'Synthetic answer $i');
              }
            }
            await _tap(tester, 'Choose Image');
            await _tap(tester, 'Analyze with AI');
            expect(server.count('/ai/analyze-image'), 1);
            expect(server.count('/items'), 0);
            await _tap(
              tester,
              found ? 'Submit Found Report' : 'Submit Lost Report',
            );
            expect(server.count('/items'), 1);
            expect(server.count('/images'), 1);
            expect(server.count('/run'), 1);
            expect(find.byType(StudentShell), findsOneWidget);
          },
        );
      },
    );
  }
  testWidgets(
    'recommendation renders decimal score -> correct match details -> claim',
    (tester) async {
      final server = _Server();
      await _page(tester, server, const StudentHomeScreen(), () async {
        await _tap(tester, 'Synthetic recommendation');
        expect(find.byType(MatchDetailsScreen), findsOneWidget);
        expect(find.text('87.5%'), findsOneWidget);
        expect(find.text('90.0%'), findsOneWidget);
        expect(find.text('N/A'), findsWidgets);
        await _tap(tester, 'Proceed to Claim');
        expect(find.byType(ClaimItemScreen), findsOneWidget);
        expect(
          (tester.widget<ClaimItemScreen>(find.byType(ClaimItemScreen))).itemId,
          2,
        );
        expect(server.count('/matches/9', 'GET'), 1);
      });
    },
  );
  test(
    'malformed image acknowledgement retries upload for the saved report',
    () async {
      final server = _Server();
      var malformed = true;
      server.intercept = (r) {
        if (r.url.path.endsWith('/images') && malformed) {
          malformed = false;
          return server.json({
            'image': {'item_id': 55},
          }, 201);
        }
        return null;
      };
      final submission = ReportSubmission();
      await _withServer(server, () async {
        await expectLater(
          submission.submit(
            _payload(),
            imageBytes: _png,
            imageName: 'test.png',
          ),
          throwsException,
        );
        await submission.submit(
          _payload(),
          imageBytes: _png,
          imageName: 'test.png',
        );
      });
      expect(server.count('/items'), 1);
      expect(server.count('/images'), 2);
    },
  );
  testWidgets(
    'image widget hides previous image while a new session is loading',
    (tester) async {
      final server = _Server();
      final pending = Completer<http.Response>();
      await _page(
        tester,
        server,
        AuthenticatedItemImage(
          url: '${AuthService.baseUrl}/items/55/images/5',
          placeholder: const Text('placeholder'),
        ),
        () async {
          expect(find.byType(Image), findsOneWidget);
          server.intercept = (r) => pending.future;
          AuthService.authToken = 'new-synthetic-session';
          await tester.pumpWidget(
            MaterialApp(
              home: AuthenticatedItemImage(
                url: '${AuthService.baseUrl}/items/55/images/5',
                placeholder: const Text('placeholder'),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(Image), findsNothing);
          expect(find.text('placeholder'), findsOneWidget);
          pending.complete(
            http.Response.bytes(
              _png,
              200,
              headers: {'content-type': 'image/png'},
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(Image), findsOneWidget);
        },
      );
    },
  );
}

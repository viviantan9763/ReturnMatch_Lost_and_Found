import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/constants/app_colors.dart';
import 'package:my_app/screens/student/claim_item_screen.dart';
import 'package:my_app/screens/student/match_details_screen.dart';
import 'package:my_app/screens/student/my_claims_screen.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/widgets/student/student_shell.dart';

// HTTP responses and persistence are synthetic. These tests never contact an API.
class _Server {
  _Server({this.tier = 'HIGH'});

  final String tier;
  final requests = <http.Request>[];
  final claims = <Map<String, dynamic>>[];
  FutureOr<http.Response?> Function(http.Request)? intercept;

  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value), status, headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> saveClaim({String status = 'PENDING', int itemId = 55}) {
    final claim = <String, dynamic>{
      'claim_id': 101 + claims.length,
      'item_id': itemId,
      'item_name': 'Synthetic found item',
      'claim_reason': 'Synthetic ownership reason',
      'claim_status': status,
      'value_tier': tier,
      'location': 'Synthetic campus location',
      'item_status': 'ACTIVE',
    };
    claims.add(claim);
    return claim;
  }

  int count(String method, String suffix) => requests.where(
    (request) => request.method == method && request.url.path.endsWith(suffix),
  ).length;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final overridden = await intercept?.call(request);
    if (overridden != null) return overridden;
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/matches/9')) {
      return json({'match': {
        'match_id': 9, 'found_item_id': 55, 'found_item_name': 'Synthetic found item',
        'found_value_tier': tier, 'found_status': 'ACTIVE',
        'match_status': 'SUGGESTED', 'overall_similarity': 0.8,
        'lost_item_name': 'Synthetic lost item',
      }});
    }
    if (request.method == 'GET' && path.endsWith('/claims/my')) {
      return json({'claims': claims});
    }
    if (request.method == 'POST' && path.endsWith('/claims')) {
      return json({'claim': saveClaim()}, 201);
    }
    if (request.method == 'GET' && path.endsWith('/security-questions')) {
      final id = int.parse(path.split('/')[3]);
      final claim = claims.singleWhere((claim) => claim['claim_id'] == id);
      return json({
        'claim_id': id, 'claim_status': claim['claim_status'], 'value_tier': tier,
        // Reversed deliberately: the UI must associate numbers and actual text.
        'questions': [
          {'question_no': 2, 'question_text': 'What is the concealed engraving?'},
          {'question_no': 1, 'question_text': 'What is inside the hidden pocket?'},
        ],
      });
    }
    if (request.method == 'POST' && path.endsWith('/security-answers')) {
      final id = int.parse(path.split('/')[3]);
      final claim = claims.singleWhere((claim) => claim['claim_id'] == id);
      claim['claim_status'] = tier == 'HIGH' ? 'VERIFICATION_REQUIRED' : 'APPROVED';
      return json({
        'claim': claim,
        'message': tier == 'HIGH' ? 'Answers submitted for manual review' : 'Claim automatically approved',
      }, 201);
    }
    throw StateError('Unexpected mock request: ${request.method} $path');
  }
}

Future<void> _withServer(
  WidgetTester tester, _Server server, Widget page,
  Future<void> Function() scenario,
) async {
  tester.view.physicalSize = const Size(1200, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await http.runWithClient(() async {
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppColors.studentPrimary)),
        home: page,
      ));
      await tester.pumpAndSettle();
      await scenario();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  }, () => MockClient(server.handle));
}

const _claimPage = ClaimItemScreen(itemId: 55, itemName: 'Synthetic found item', valueTier: 'HIGH');

Future<void> _startClaim(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), 'I recognise this synthetic item.');
  await tester.ensureVisible(find.text('Submit Claim'));
  await tester.tap(find.text('Submit Claim'));
  await tester.pumpAndSettle();
}

Future<void> _fillAnswers(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('ownership-answer-1')), '  synthetic contents  ');
  await tester.enterText(find.byKey(const ValueKey('ownership-answer-2')), 'synthetic engraving');
}

void main() {
  setUp(() {
    AuthService.authToken = 'synthetic-session';
    AuthService.currentUser = {'user_id': 7, 'role': 'USER'};
  });
  tearDown(AuthService.logout);

  for (final tier in ['HIGH', 'MEDIUM']) {
    testWidgets('$tier match -> claim -> actual questions -> My Claims', (tester) async {
      final server = _Server(tier: tier);
      await _withServer(tester, server, const MatchDetailsScreen(matchId: 9), () async {
        await tester.ensureVisible(find.text('Proceed to Claim'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proceed to Claim'));
        await tester.pumpAndSettle();
        expect(find.byType(ClaimItemScreen), findsOneWidget);
        expect(find.text('What colour is the item?'), findsNothing);
        await _startClaim(tester);
        expect(find.byType(MyClaimsScreen), findsOneWidget);
        expect(find.byType(StudentShell), findsWidgets);
        expect(find.text('Verify Ownership'), findsOneWidget);
        expect(find.text('1. What is inside the hidden pocket?'), findsOneWidget);
        expect(find.text('2. What is the concealed engraving?'), findsOneWidget);
        await _fillAnswers(tester);
        await tester.tap(find.text('Submit Answers'));
        await tester.pumpAndSettle();
        expect(find.text('Verify Ownership'), findsNothing);
        expect(server.count('POST', '/claims'), 1);
        final post = server.requests.singleWhere((request) => request.url.path.endsWith('/security-answers'));
        expect(jsonDecode(post.body), {'answers': [
          {'question_no': 1, 'answer_text': 'synthetic contents'},
          {'question_no': 2, 'answer_text': 'synthetic engraving'},
        ]});
        expect(server.claims.single['claim_status'], tier == 'HIGH' ? 'VERIFICATION_REQUIRED' : 'APPROVED');
      });
    });
  }

  testWidgets('answer errors preserve text and retry the same claim', (tester) async {
    final server = _Server();
    var attempts = 0;
    server.intercept = (request) {
      if (request.url.path.endsWith('/security-answers') && ++attempts == 1) {
        return server.json({'message': 'Temporary answer failure'}, 503);
      }
      return null;
    };
    await _withServer(tester, server, _claimPage, () async {
      await _startClaim(tester);
      await _fillAnswers(tester);
      await tester.tap(find.text('Submit Answers'));
      await tester.pumpAndSettle();
      expect(find.text('Temporary answer failure'), findsOneWidget);
      final field = tester.widget<TextFormField>(find.byKey(const ValueKey('ownership-answer-1')));
      expect(field.controller!.text, '  synthetic contents  ');
      await tester.tap(find.text('Submit Answers'));
      await tester.pumpAndSettle();
      expect(server.count('POST', '/claims'), 1);
      expect(server.count('POST', '/claims/101/security-answers'), 2);
      expect(find.text('Answers submitted for manual review'), findsOneWidget);
    });
  });

  testWidgets('empty, short and overlength answers do not send a request', (tester) async {
    final server = _Server()..saveClaim();
    await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 101), () async {
      await tester.tap(find.text('Submit Answers'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter at least 2 characters'), findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('ownership-answer-1')), 'x');
      await tester.enterText(find.byKey(const ValueKey('ownership-answer-2')), 'valid');
      await tester.tap(find.text('Submit Answers'));
      await tester.pumpAndSettle();
      expect(server.count('POST', '/claims/101/security-answers'), 0);
      final field = tester.widget<TextFormField>(find.byKey(const ValueKey('ownership-answer-1')));
      field.controller!.text = List.filled(251, 'x').join();
      await tester.tap(find.text('Submit Answers'));
      await tester.pumpAndSettle();
      expect(find.text('Use at most 250 characters'), findsOneWidget);
      expect(server.count('POST', '/claims/101/security-answers'), 0);
    });
  });

  testWidgets('dismissal and refresh do not auto-reopen; manual resume works', (tester) async {
    final server = _Server()..saveClaim();
    await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 101), () async {
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Verify Ownership'), findsNothing);
      expect(server.count('GET', '/claims/101/security-questions'), 1);
      await tester.tap(find.text('Answer Security Questions'));
      await tester.pumpAndSettle();
      expect(find.text('Verify Ownership'), findsOneWidget);
      expect(server.count('GET', '/claims/101/security-questions'), 2);
      expect(server.count('POST', '/claims'), 0);
    });
  });

  testWidgets('re-entering Claim resumes a saved claim without a new reason or POST', (tester) async {
    final server = _Server()..saveClaim();
    await _withServer(tester, server, _claimPage, () async {
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.tap(find.text('Submit Claim'));
      await tester.pumpAndSettle();
      expect(find.text('Verify Ownership'), findsOneWidget);
      expect(server.count('POST', '/claims'), 0);
    });
  });

  for (final status in ['APPROVED', 'VERIFICATION_REQUIRED', 'REJECTED', 'COLLECTED']) {
    testWidgets('$status claim is not automatically opened for answers', (tester) async {
      final server = _Server()..saveClaim(status: status);
      await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 101), () async {
        expect(find.text('Verify Ownership'), findsNothing);
        expect(server.count('GET', '/claims/101/security-questions'), 0);
      });
    });
  }

  testWidgets('a missing intended claim never opens another pending claim', (tester) async {
    final server = _Server()..saveClaim();
    await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 999), () async {
      expect(find.text('Verify Ownership'), findsNothing);
      expect(server.requests.where((request) => request.url.path.endsWith('/security-questions')), isEmpty);
    });
  });

  testWidgets('normal My Claims navigation does not auto-open a pending claim', (tester) async {
    final server = _Server()..saveClaim();
    await _withServer(tester, server, const MyClaimsScreen(), () async {
      expect(find.text('Verify Ownership'), findsNothing);
      expect(find.text('Answer Security Questions'), findsOneWidget);
      expect(server.count('GET', '/claims/101/security-questions'), 0);
    });
  });

  testWidgets('a new claim requires a reason and sends no creation request when empty', (tester) async {
    final server = _Server();
    await _withServer(tester, server, _claimPage, () async {
      await tester.ensureVisible(find.text('Submit Claim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Claim'));
      await tester.pumpAndSettle();
      expect(find.text('Claim reason is required'), findsOneWidget);
      expect(server.count('POST', '/claims'), 0);
    });
  });

  testWidgets('question response for a different claim cannot be submitted', (tester) async {
    final server = _Server()..saveClaim();
    server.intercept = (request) => request.url.path.endsWith('/security-questions')
        ? server.json({'claim_id': 999, 'claim_status': 'PENDING', 'questions': [
            {'question_no': 1, 'question_text': 'Synthetic question one'},
            {'question_no': 2, 'question_text': 'Synthetic question two'},
          ]}) : null;
    await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 101), () async {
      expect(find.text('Submit Answers'), findsNothing);
      expect(find.text('Retry Questions'), findsOneWidget);
      expect(server.count('POST', '/claims/101/security-answers'), 0);
    });
  });

  for (final kind in ['missing', 'duplicate numbers', 'blank text', 'not a list', 'non-json', 'unavailable']) {
    testWidgets('$kind questions have retry, no answers or extra claim creation', (tester) async {
      final server = _Server()..saveClaim();
      var fail = true;
      server.intercept = (request) {
        if (!fail || !request.url.path.endsWith('/security-questions')) return null;
        if (kind == 'non-json') return http.Response('unavailable', 502);
        if (kind == 'unavailable') return server.json({'message': 'Questions unavailable'}, 503);
        final Object questions = switch (kind) {
          'duplicate numbers' => [
            {'question_no': 1, 'question_text': 'Question one'},
            {'question_no': 1, 'question_text': 'Question duplicate'},
          ],
          'blank text' => [
            {'question_no': 1, 'question_text': ' '},
            {'question_no': 2, 'question_text': 'Question two'},
          ],
          'not a list' => {'invalid': true},
          _ => <Object>[],
        };
        return server.json({'claim_id': 101, 'claim_status': 'PENDING', 'questions': questions});
      };
      await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 101), () async {
        expect(find.text('Retry Questions'), findsOneWidget);
        expect(find.text('Submit Answers'), findsNothing);
        fail = false;
        await tester.tap(find.text('Retry Questions'));
        await tester.pumpAndSettle();
        expect(find.text('1. What is inside the hidden pocket?'), findsOneWidget);
        expect(server.count('POST', '/claims'), 0);
      });
    });
  }

  for (final kind in ['lost response', 'malformed success', 'creation conflict']) {
    testWidgets('$kind resumes the saved claim', (tester) async {
      final server = _Server();
      server.intercept = (request) {
        if (request.method == 'POST' && request.url.path.endsWith('/claims')) {
          server.saveClaim();
          if (kind == 'lost response') throw http.ClientException('Synthetic connection loss');
          if (kind == 'malformed success') return http.Response('invalid-json', 201);
          return server.json({'message': 'Active claim already exists'}, 409);
        }
        return null;
      };
      await _withServer(tester, server, _claimPage, () async {
        await _startClaim(tester);
        expect(find.text('Verify Ownership'), findsOneWidget);
        expect(server.count('POST', '/claims'), 1);
        expect(server.claims.length, 1);
      });
    });
  }

  testWidgets('uncertain creation never blindly repeats POST', (tester) async {
    final server = _Server();
    server.intercept = (request) {
      if (request.method == 'POST' && request.url.path.endsWith('/claims')) {
        throw http.ClientException('Synthetic connection loss');
      }
      return null;
    };
    await _withServer(tester, server, _claimPage, () async {
      await _startClaim(tester);
      await tester.ensureVisible(find.text('Check Existing Claim'));
      await tester.tap(find.text('Check Existing Claim'));
      await tester.pumpAndSettle();
      expect(server.count('POST', '/claims'), 1);
      await tester.ensureVisible(find.text('Open My Claims'));
      await tester.tap(find.text('Open My Claims'));
      await tester.pumpAndSettle();
      expect(find.byType(MyClaimsScreen), findsOneWidget);
    });
  });

  testWidgets('claim-history failure prevents creation and can be retried', (tester) async {
    final server = _Server();
    var fail = true;
    server.intercept = (request) => fail && request.url.path.endsWith('/claims/my')
        ? server.json({'message': 'History unavailable'}, 503) : null;
    await _withServer(tester, server, _claimPage, () async {
      await _startClaim(tester);
      expect(find.text('History unavailable'), findsOneWidget);
      expect(server.count('POST', '/claims'), 0);
      fail = false;
      await tester.tap(find.text('Submit Claim'));
      await tester.pumpAndSettle();
      expect(find.text('Verify Ownership'), findsOneWidget);
    });
  });

  testWidgets('malformed claim history prevents blind creation', (tester) async {
    final server = _Server();
    server.intercept = (request) => request.url.path.endsWith('/claims/my')
        ? server.json({'claims': [<String, dynamic>{}]}) : null;
    await _withServer(tester, server, _claimPage, () async {
      await _startClaim(tester);
      expect(find.text('Invalid claim history. Please refresh My Claims.'), findsOneWidget);
      expect(server.count('POST', '/claims'), 0);
    });
  });

  testWidgets('session change while loading history prevents automatic verification', (tester) async {
    final server = _Server()..saveClaim();
    server.intercept = (request) {
      if (request.url.path.endsWith('/claims/my')) {
        AuthService.currentUser = {'user_id': 8, 'role': 'USER'};
      }
      return null;
    };
    await _withServer(tester, server, const MyClaimsScreen(initialClaimId: 101), () async {
      expect(find.text('Verify Ownership'), findsNothing);
      expect(server.count('GET', '/claims/101/security-questions'), 0);
      expect(find.textContaining('Your session changed'), findsOneWidget);
    });
  });
}

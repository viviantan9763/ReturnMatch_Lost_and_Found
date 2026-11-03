import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/screens/admin/retention_screen.dart';
import 'package:my_app/screens/admin/disposal_record_screen.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/widgets/admin/admin_shell.dart';

// Synthetic HTTP only; no running API or database is used.
class _Server {
  final requests = <http.Request>[];
  final retention = <String, dynamic>{
    'retention_id': 1,
    'item_id': 55,
    'item_name': 'Synthetic lifecycle item',
    'retention_status': 'DUE',
    'retention_start_date': '2026-10-05',
    'retention_due_date': '2026-11-04',
    'item_status': 'ACTIVE',
    'custody_status': 'RECEIVED',
    'storage_location': 'Synthetic shelf',
    'value_tier': 'HIGH',
    'can_create_disposal': true,
  };
  final disposal = <String, dynamic>{
    'disposal_id': 1,
    'item_id': 55,
    'item_name': 'Synthetic lifecycle item',
    'disposal_status': 'PENDING',
    'disposal_method': 'RECYCLING',
    'admin_name': 'Synthetic staff',
    'value_tier': 'HIGH',
    'item_type': 'FOUND',
    'can_update': true,
    'can_reverse': false,
  };
  FutureOr<http.Response?> Function(http.Request)? intercept;
  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final overridden = await intercept?.call(request);
    if (overridden != null) return overridden;
    if (request.method == 'GET' && request.url.path.endsWith('/retention')) {
      return json({
        'records': [retention],
        'newly_due_count': 0,
      });
    }
    if (request.method == 'GET' && request.url.path.endsWith('/disposals')) {
      return json({
        'records': [disposal],
      });
    }
    if (request.method == 'POST' &&
        request.url.path.endsWith('/disposals/55')) {
      retention['can_create_disposal'] = false;
      return json({'message': 'Created'}, 201);
    }
    if (request.method == 'PATCH' && request.url.path.endsWith('/status')) {
      disposal['disposal_status'] = (jsonDecode(request.body) as Map)['status'];
      disposal['can_update'] = false;
      return json({'message': 'Updated'});
    }
    if (request.method == 'POST' && request.url.path.endsWith('/reverse')) {
      disposal['disposal_status'] = 'REVERSED';
      disposal['can_reverse'] = false;
      return json({'message': 'Reversed'});
    }
    throw StateError(
      'Unexpected synthetic request: ${request.method} ${request.url.path}',
    );
  }

  int get writes => requests.where((r) => r.method != 'GET').length;
}

Future<void> _run(
  WidgetTester tester,
  _Server server,
  Widget page,
  Future<void> Function() scenario,
) async {
  tester.view.physicalSize = const Size(700, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await http.runWithClient(() async {
    try {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
      expect(find.byType(AdminShell), findsOneWidget);
      await scenario();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  }, () => MockClient(server.handle));
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AuthService.authToken = 'synthetic-admin-session';
    AuthService.currentUser = {'user_id': 1, 'role': 'ADMIN'};
  });
  tearDown(AuthService.logout);
  testWidgets(
    'retention respects backend eligibility and displays reason/date-only values',
    (tester) async {
      final server = _Server();
      server.retention['can_create_disposal'] = false;
      server.retention['disposal_block_reason'] =
          'Pending ownership claim prevents disposal.';
      await _run(tester, server, const RetentionMonitorScreen(), () async {
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Disposal Pending'),
        );
        expect(button.onPressed, isNull);
        expect(
          find.text('Pending ownership claim prevents disposal.'),
          findsOneWidget,
        );
        expect(find.text('04/11/2026'), findsOneWidget);
        expect(server.writes, 0);
      });
    },
  );
  testWidgets('eligible retention creates once and retains existing shell', (
    tester,
  ) async {
    final server = _Server();
    server.disposal['disposal_status'] = 'CANCELLED';
    await _run(tester, server, const RetentionMonitorScreen(), () async {
      await _tap(tester, 'Create Disposal Record');
      await _tap(tester, 'Create Record');
      expect(server.writes, 1);
      expect(server.requests.last.method, 'GET');
      expect(
        find.text('Disposal record created successfully.'),
        findsOneWidget,
      );
    });
  });
  testWidgets('retention API rejection is shown and action becomes retryable', (
    tester,
  ) async {
    final server = _Server();
    server.disposal['disposal_status'] = 'CANCELLED';
    server.intercept = (r) => r.method == 'POST'
        ? server.json({'message': 'New ownership claim prevents disposal'}, 409)
        : null;
    await _run(tester, server, const RetentionMonitorScreen(), () async {
      await _tap(tester, 'Create Disposal Record');
      await _tap(tester, 'Create Record');
      expect(
        find.text('New ownership claim prevents disposal'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create Disposal Record'),
            )
            .onPressed,
        isNotNull,
      );
      expect(server.writes, 1);
    });
  });
  testWidgets(
    'historical inconsistent disposal actions are disabled with reason',
    (tester) async {
      final server = _Server();
      server.disposal.addAll({
        'disposal_status': 'COMPLETED',
        'can_reverse': false,
        'lifecycle_block_reason': 'Historical state requires manual review.',
      });
      await _run(tester, server, const DisposalRecordScreen(), () async {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Restore to Retention'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text('Historical state requires manual review.'),
          findsOneWidget,
        );
        expect(server.writes, 0);
      });
    },
  );
  testWidgets(
    'completion sends selected method and disables duplicate pending actions during request',
    (tester) async {
      final server = _Server();
      final pending = Completer<http.Response>();
      server.intercept = (r) => r.method == 'PATCH' ? pending.future : null;
      await _run(tester, server, const DisposalRecordScreen(), () async {
        await _tap(tester, 'Complete Disposal');
        await _tap(tester, 'Confirm Completion');
        expect(server.writes, 1);
        expect(
          jsonDecode(server.requests.last.body)['disposal_method'],
          'RECYCLING',
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete Disposal'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Cancel'),
              )
              .onPressed,
          isNull,
        );
        server.disposal['disposal_status'] = 'COMPLETED';
        server.disposal['can_update'] = false;
        pending.complete(server.json({'message': 'Completed'}));
        await tester.pumpAndSettle();
        expect(server.writes, 1);
      });
    },
  );
  testWidgets('cancellation sends CANCELLED and leaves record visible', (
    tester,
  ) async {
    final server = _Server();
    await _run(tester, server, const DisposalRecordScreen(), () async {
      await _tap(tester, 'Cancel');
      await _tap(tester, 'Cancel Disposal');
      expect(server.writes, 1);
      expect(
        jsonDecode(
          server.requests.firstWhere((r) => r.method == 'PATCH').body,
        )['status'],
        'CANCELLED',
      );
      expect(find.text('Synthetic lifecycle item'), findsOneWidget);
    });
  });
  testWidgets(
    'reversal requires custody confirmation, reason and storage; sends all three',
    (tester) async {
      final server = _Server();
      server.disposal.addAll({
        'disposal_status': 'COMPLETED',
        'can_reverse': true,
      });
      await _run(tester, server, const DisposalRecordScreen(), () async {
        await _tap(tester, 'Restore to Retention');
        await _tap(tester, 'Restore Item');
        expect(server.writes, 0);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Storage location *'),
          'Synthetic restored shelf',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason for reversal *'),
          'Synthetic mistaken completion',
        );
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await _tap(tester, 'Restore Item');
        final body = jsonDecode(
          server.requests.firstWhere((r) => r.method == 'POST').body,
        );
        expect(body, {
          'reason': 'Synthetic mistaken completion',
          'storage_location': 'Synthetic restored shelf',
          'confirm_item_still_held': true,
        });
        expect(server.writes, 1);
        expect(find.text('Restore to Retention'), findsNothing);
      });
    },
  );
  testWidgets(
    'disposal recoverable API errors show backend message and reenable action',
    (tester) async {
      final server = _Server();
      server.intercept = (r) => r.method == 'PATCH'
          ? server.json({'message': 'Concurrent item action; refresh'}, 409)
          : null;
      await _run(tester, server, const DisposalRecordScreen(), () async {
        await _tap(tester, 'Complete Disposal');
        await _tap(tester, 'Confirm Completion');
        expect(find.text('Concurrent item action; refresh'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete Disposal'),
              )
              .onPressed,
          isNotNull,
        );
        expect(server.writes, 1);
      });
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/app_theme.dart';
import 'package:an_xin_ban/family_cloud.dart';
import 'package:an_xin_ban/family_demo.dart';
import 'package:an_xin_ban/pairing_confirmation.dart';

/// Both phones' side of pairing, without the network.
class FakePairingCloud extends FamilyCloud {
  /// Answers to the elder's status checks, in order; the last one repeats.
  List<PairingStatus> statuses = [PairingStatus.pending];
  final pending = <PairingRequest>[];
  final approved = <String>[];
  final rejected = <String>[];
  final entered = <String>[];
  String? requestError;
  bool remembered = false;
  int statusChecks = 0;

  @override
  String? get user => 'elder';
  @override
  bool get hasFamilyAccount => true;

  @override
  Future<PairingRequest> requestPairing(String code) async {
    entered.add(code);
    final error = requestError;
    if (error != null) throw FamilyPublishException(pairingErrorMessage(error));
    return const PairingRequest(id: 'r1', confirmCode: '47');
  }

  @override
  Future<PairingStatus> pairingStatus(String requestId) async {
    statusChecks++;
    return statuses.length > 1 ? statuses.removeAt(0) : statuses.single;
  }

  @override
  Future<void> rememberPairing() async => remembered = true;
  @override
  Future<List<PairingRequest>> pendingPairings() async => List.of(pending);
  @override
  Future<void> approvePairing(String requestId) async =>
      approved.add(requestId);
  @override
  Future<void> rejectPairing(String requestId) async => rejected.add(requestId);
}

void main() {
  late FakePairingCloud cloud;
  setUp(() => cloud = FakePairingCloud());

  Widget app(Future<void> Function(BuildContext context) onPressed) =>
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => onPressed(context),
                child: const Text('開始'),
              ),
            ),
          ),
        ),
      );

  group('elder', () {
    bool? linked;
    Object? failure;

    Future<void> enterCode(WidgetTester tester) async {
      linked = null;
      failure = null;
      await tester.pumpWidget(
        app((context) async {
          try {
            linked = await pairWithFamily(context, cloud, '123456');
          } catch (error) {
            failure = error;
          }
        }),
      );
      await tester.tap(find.text('開始'));
      await tester.pump();
    }

    testWidgets('sees the number and is linked once the family allows', (
      tester,
    ) async {
      cloud.statuses = [PairingStatus.pending, PairingStatus.approved];
      await enterCode(tester);
      expect(cloud.entered, ['123456']);
      expect(find.text('請家人確認'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);
      expect(find.text('等待家人允許…'), findsOneWidget);

      // Still waiting: nothing is linked yet.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('47'), findsOneWidget);
      expect(cloud.remembered, isFalse);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('請家人確認'), findsNothing);
      expect(linked, isTrue);
      expect(cloud.remembered, isTrue);
    });

    testWidgets('is told when the family refuses, and is not linked', (
      tester,
    ) async {
      cloud.statuses = [PairingStatus.rejected];
      await enterCode(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(linked, isFalse);
      expect(cloud.remembered, isFalse);
      expect(find.textContaining('家人沒有允許'), findsOneWidget);
    });

    testWidgets('is told when the request lapses', (tester) async {
      cloud.statuses = [PairingStatus.expired];
      await enterCode(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(linked, isFalse);
      expect(find.textContaining('重新產生配對碼'), findsOneWidget);
    });

    testWidgets('can stop waiting', (tester) async {
      await enterCode(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(linked, isFalse);
      final checks = cloud.statusChecks;
      await tester.pump(const Duration(seconds: 6));
      expect(cloud.statusChecks, checks, reason: 'kept asking after cancel');
    });

    testWidgets('a code that is not taken says why', (tester) async {
      cloud.requestError = 'busy';
      await enterCode(tester);
      await tester.pumpAndSettle();
      expect(find.text('請家人確認'), findsNothing);
      expect((failure! as FamilyPublishException).message, contains('等家人確認'));
    });
  });

  test('every refusal from the server has a plain message', () {
    expect(pairingErrorMessage('rate_limited'), contains('10 分鐘'));
    expect(pairingErrorMessage('already_paired'), contains('已配對'));
    expect(pairingErrorMessage('busy'), contains('等家人確認'));
    expect(pairingErrorMessage('invalid_code'), contains('重新產生'));
    expect(pairingErrorMessage(null), contains('重新產生'));
  });

  group('family', () {
    Future<void> showCode(WidgetTester tester) async {
      await tester.pumpWidget(
        app((context) async {
          final request = await showDialog<PairingRequest>(
            context: context,
            builder: (_) => InvitationCodeDialog(
              code: '123456',
              cloud: cloud,
              interval: const Duration(seconds: 1),
            ),
          );
          if (request != null && context.mounted) {
            await reviewPairingRequest(context, cloud, request);
          }
        }),
      );
      await tester.tap(find.text('開始'));
      await tester.pumpAndSettle();
      expect(find.text('123456'), findsOneWidget);

      // The code stays until an elder enters it.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('123456'), findsOneWidget);

      cloud.pending.add(const PairingRequest(id: 'r9', confirmCode: '31'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('長輩手機要連結'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
    }

    testWidgets('allows the link when the numbers match', (tester) async {
      await showCode(tester);
      await tester.tap(find.text('一樣，允許'));
      await tester.pumpAndSettle();
      expect(cloud.approved, ['r9']);
      expect(cloud.rejected, isEmpty);
      expect(find.text('已連結長輩'), findsOneWidget);
    });

    testWidgets('refuses a request that does not match', (tester) async {
      await showCode(tester);
      await tester.tap(find.text('不一樣，拒絕'));
      await tester.pumpAndSettle();
      expect(cloud.rejected, ['r9']);
      expect(cloud.approved, isEmpty);
      expect(find.textContaining('配對碼已失效'), findsOneWidget);
    });
  });
}

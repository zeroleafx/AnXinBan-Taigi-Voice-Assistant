import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:an_xin_ban/assistant_controller.dart';
import 'package:an_xin_ban/contact_matcher.dart';
import 'package:an_xin_ban/emergency_store.dart';
import 'package:an_xin_ban/home_page.dart';
import 'package:an_xin_ban/main.dart';
import 'package:an_xin_ban/place.dart';
import 'package:an_xin_ban/recording_controller.dart';
import 'package:an_xin_ban/speech_model.dart';
import 'package:an_xin_ban/taigi_voice.dart';
import 'package:an_xin_ban/voice_command.dart';

import 'support/fake_phone.dart';
import 'support/fake_voice.dart';

const daughter = ContactEntry(name: '女兒', numbers: ['0911-111-111']);

class QuietBackend implements RecordingBackend {
  @override
  Stream<double> get decibels => const Stream.empty();
  final _states = StreamController<RecordState>.broadcast();
  @override
  Future<String?> retainLatest({String? keepPath}) async => keepPath;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<String?> stop() async => '/latest.m4a';
  @override
  Future<void> cancel() async {}
  @override
  Stream<RecordState> get states => _states.stream;
  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

/// An Android phone whose speech model is not downloaded yet.
class ModelStore implements SpeechModelBackend {
  ModelStore(this.network);
  ModelNetwork network;
  int downloadedBytes = 0;
  bool ready = false;
  String? failWith;

  /// Reports this much, then waits for [finish].
  int reaches = 37;
  Completer<void> finish = Completer<void>();

  @override
  Future<ModelStatus?> status() async => ModelStatus(
    ready: ready,
    totalBytes: 1080732108,
    downloadedBytes: downloadedBytes,
    network: network,
  );

  @override
  Future<void> download(void Function(int percent) onPercent) async {
    onPercent(reaches);
    await finish.future;
    finish = Completer<void>();
    final message = failWith;
    if (message != null) {
      throw PlatformException(code: 'download', message: message);
    }
    ready = true;
  }
}

void main() {
  late FakePhone phone;
  late MemoryEmergencyStore store;
  late AssistantController assistant;
  late RecordingController recording;
  SpeechModelController? model;
  var heard = '';

  setUp(() {
    phone = FakePhone();
    store = MemoryEmergencyStore();
    assistant = AssistantController(phone, store: store);
    recording = RecordingController(
      QuietBackend(),
      transcribe: (_) async => heard,
    );
    model = null;
  });
  tearDown(() {
    assistant.dispose();
    recording.dispose();
    model?.dispose();
  });

  Future<void> open(
    WidgetTester tester,
    Size size, {
    double text = 1,
    TaigiVoice? voice,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      AnXinBanApp(
        home: HomePage(
          recording: recording,
          assistant: assistant,
          model: model,
          voice: voice,
        ),
      ),
    );
    await tester.pump();
  }

  /// Taps and lets the card that follows finish appearing.
  Future<void> press(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> say(WidgetTester tester, String words) async {
    heard = words;
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('停止錄音'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  // Overflow is reported as a test failure, so these also prove that every
  // state fits on one screen without scrolling.
  for (final (name, size) in [
    ('small phone', const Size(320, 568)),
    ('iPhone SE', const Size(375, 667)),
    ('iPhone 16', const Size(393, 852)),
  ]) {
    testWidgets('every state fits on a $name, even with large text', (
      tester,
    ) async {
      await open(tester, size, text: 1.6);
      expect(find.text('有啥物需要幫忙？'), findsOneWidget);
      expect(find.text('可以這樣講'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);

      await tester.tap(find.bySemanticsLabel('開始錄音'));
      await tester.pump();
      expect(find.text('正在聽…'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('停止錄音'));
      await tester.pump(const Duration(seconds: 1));

      await say(tester, '打給阿明');
      expect(find.text('要打給哪一位？'), findsOneWidget);
      await say(tester, '今天心情不錯');
      expect(find.text('這句我還不會'), findsOneWidget);
      await say(tester, '開手電筒');
      expect(find.text('關掉手電筒'), findsOneWidget);

      await say(tester, '我在哪裡');
      expect(find.text('你在這裡'), findsOneWidget);
      expect(find.text('彰化縣彰化市中山路三段185巷16號'), findsOneWidget);

      await press(tester, find.text('求救'));
      expect(find.text('需要幫忙嗎？'), findsOneWidget);
      expect(find.text('設定緊急聯絡人'), findsOneWidget);

      store.contact = daughter;
      await assistant.initialize();
      await say(tester, '救命');
      expect(find.text('正在打給 女兒'), findsOneWidget);
      expect(find.text('把位置傳給 女兒'), findsOneWidget);
    });
  }

  testWidgets('the SOS button offers help without any speech', (tester) async {
    store.contact = daughter;
    await assistant.initialize();
    await open(tester, const Size(393, 852));
    await press(tester, find.text('求救'));
    expect(phone.dialed, isEmpty, reason: 'a tap alone calls no one');

    await press(tester, find.text('打給 女兒'));
    expect(phone.dialed, ['0911-111-111']);

    await press(tester, find.text('把位置傳給 女兒'));
    await press(tester, find.text('確認'));
    expect(phone.texts.single.$2, startsWith('我需要幫忙。我在這裡：'));
    expect(find.text('把位置傳給 女兒'), findsOneWidget);
  });

  testWidgets('pressing SOS drops what was being said', (tester) async {
    final slow = Completer<String>();
    recording.dispose();
    recording = RecordingController(
      QuietBackend(),
      transcribe: (_) => slow.future,
    );
    await open(tester, const Size(393, 852));

    // While still recording: the recording is thrown away.
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await press(tester, find.text('求救'));
    expect(recording.isRecording, false);
    expect(find.text('需要幫忙嗎？'), findsOneWidget);
    await press(tester, find.byTooltip('關閉'));

    // While the words are being recognized: their result is ignored.
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('停止錄音'));
    await tester.pump();
    await press(tester, find.text('求救'));
    slow.complete('幫我開LINE');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('需要幫忙嗎？'), findsOneWidget);
    expect(phone.opened, isEmpty);
  });

  testWidgets('help is there before the speech model is, and can be closed', (
    tester,
  ) async {
    model = SpeechModelController(ModelStore(ModelNetwork.unmetered));
    await open(tester, const Size(393, 852));
    expect(find.text('先下載語音模型'), findsOneWidget);

    await press(tester, find.text('求救'));
    expect(find.text('打 119'), findsOneWidget);
    await press(tester, find.text('打 119'));
    expect(phone.dialed, ['119']);

    await press(tester, find.byTooltip('關閉'));
    expect(find.text('先下載語音模型'), findsOneWidget);
  });

  testWidgets('sending my location to one of several matches', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '把位置傳給阿明');
    expect(find.text('要傳給哪一位？'), findsOneWidget);
    await press(tester, find.text('陳志明'));
    await press(tester, find.text('確認'));
    expect(phone.texts.single.$1, '0933-222-111');
    expect(phone.dialed, isEmpty);
    expect(find.text('把位置傳給 陳志明'), findsOneWidget);
  });

  testWidgets('a location problem offers the way to fix it', (tester) async {
    phone.location = const LocationOff();
    await open(tester, const Size(393, 852));
    await say(tester, '我在哪裡');
    await press(tester, find.text('打開定位'));
    expect(phone.locationSettingsOpened, 1);
  });

  for (final (name, size) in [
    ('small phone', const Size(320, 568)),
    ('iPhone 16', const Size(393, 852)),
  ]) {
    testWidgets('the model download fits on a $name with large text', (
      tester,
    ) async {
      final store = ModelStore(ModelNetwork.metered);
      model = SpeechModelController(store);
      await open(tester, size, text: 1.6);
      expect(find.text('先下載語音模型'), findsOneWidget);
      expect(find.textContaining('不是 Wi-Fi'), findsOneWidget);

      await tester.tap(find.text('用行動數據下載'));
      await tester.pump();
      expect(find.text('下載中 37%'), findsOneWidget);

      store.failWith = '下載中斷，再試一次會接著下載。';
      store.downloadedBytes = 400000000;
      store.finish.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('下載沒有成功'), findsOneWidget);
      expect(find.textContaining('中斷'), findsOneWidget);
    });
  }

  testWidgets('speech stays off until the model is downloaded', (tester) async {
    final store = ModelStore(ModelNetwork.unmetered);
    model = SpeechModelController(store);
    await open(tester, const Size(393, 852));
    expect(find.text('1.1 GB，只要下載一次'), findsOneWidget);

    expect(find.bySemanticsLabel('開始錄音'), findsNothing);
    await tester.pump();
    expect(find.text('正在聽…'), findsNothing);

    store.reaches = 100;
    await tester.tap(find.text('開始下載'));
    await tester.pump();
    expect(find.text('檢查檔案中'), findsOneWidget);

    store.finish.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('可以這樣講'), findsOneWidget);
    await say(tester, '幫我開LINE');
    await press(tester, find.text('確認'));
    expect(find.text('已打開 LINE'), findsOneWidget);
  });

  testWidgets('download can be deferred to record and reopened later', (
    tester,
  ) async {
    final store = ModelStore(ModelNetwork.unmetered);
    model = SpeechModelController(store);
    await open(tester, const Size(393, 852));
    await tester.tap(find.text('稍後下載，先使用錄音'));
    await tester.pump();
    expect(find.bySemanticsLabel('開始錄音'), findsOneWidget);
    await tester.tap(find.text('下載語音模型以啟用辨識'));
    await tester.pump();
    expect(find.text('開始下載'), findsOneWidget);
    expect(model!.phase, ModelPhase.missing);
  });

  testWidgets('an interrupted download offers to continue', (tester) async {
    final store = ModelStore(ModelNetwork.unmetered)
      ..downloadedBytes = 540366054;
    model = SpeechModelController(store);
    await open(tester, const Size(393, 852));
    expect(find.text('繼續下載語音模型'), findsOneWidget);
    expect(find.text('已經下載 50%'), findsOneWidget);
    expect(find.text('繼續下載'), findsOneWidget);
  });

  testWidgets('returning to the app notices a model installed meanwhile', (
    tester,
  ) async {
    final store = ModelStore(ModelNetwork.none);
    model = SpeechModelController(store);
    await open(tester, const Size(393, 852));
    expect(find.text('現在沒有網路'), findsOneWidget);

    store.ready = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('可以這樣講'), findsOneWidget);
  });

  testWidgets('saying "開 LINE" opens LINE and says so', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '幫我開LINE');
    await press(tester, find.text('確認'));
    expect(phone.opened, [PhoneApp.line]);
    expect(find.text('已打開 LINE'), findsOneWidget);
    expect(find.text('「幫我開LINE」'), findsOneWidget);
  });

  testWidgets('tapping a contact choice calls that person', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '打給阿明');
    await tester.tap(find.text('陳志明'));
    await tester.pump();
    expect(phone.dialed, isEmpty);
    await press(tester, find.text('確認'));
    expect(phone.dialed, ['0933-222-111']);
    expect(find.text('打給 陳志明'), findsOneWidget);
  });

  testWidgets('a new recording clears the previous result', (tester) async {
    await open(tester, const Size(393, 852));
    await say(tester, '幫我開LINE');
    await press(tester, find.text('確認'));
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已打開 LINE'), findsNothing);
    expect(find.text('可以這樣講'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('停止錄音'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the flashlight keeps its off button after its card is gone', (
    tester,
  ) async {
    await open(tester, const Size(393, 852));
    await say(tester, '開手電筒');
    expect(phone.torch, true);
    expect(find.text('手電筒開了'), findsOneWidget);

    // A new recording clears the result, but the light is still on.
    await tester.tap(find.bySemanticsLabel('開始錄音'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('手電筒開了'), findsNothing);
    expect(find.text('手電筒開著'), findsOneWidget);

    await tester.tap(find.text('關掉手電筒'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(phone.torch, false);
    expect(find.text('手電筒關了'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('停止錄音'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('coming back after the control centre switched the light off', (
    tester,
  ) async {
    await open(tester, const Size(393, 852));
    await say(tester, '開手電筒');
    expect(find.text('手電筒開了'), findsOneWidget);

    phone.torch = false; // pulled down the control centre and switched it off
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('手電筒開了'), findsNothing);
    expect(find.text('手電筒關了'), findsOneWidget);
    expect(find.text('關掉手電筒'), findsNothing);
  });

  group('the Taiwanese voice download', () {
    late FakeSynthesizer synthesizer;
    late FakePlayer player;
    late TaigiVoice voice;

    setUp(() {
      synthesizer = FakeSynthesizer()..installed = false;
      player = FakePlayer();
      voice = TaigiVoice(assistant, synthesizer, player);
    });
    // Runs before the outer tearDown disposes the assistant.
    tearDown(() => voice.dispose());

    /// Lets async work finish and cards change: the card switch starts on
    /// the frame after the voice reports, then fades for 250 ms.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> openOn(
      WidgetTester tester,
      ModelNetwork network, {
      bool speechModel = true,
    }) async {
      model = SpeechModelController(ModelStore(network)..ready = speechModel);
      await open(tester, const Size(393, 852), voice: voice);
      await settle(tester);
    }

    for (final network in [ModelNetwork.metered, ModelNetwork.unmetered]) {
      testWidgets('asks before downloading the voice on ${network.name}', (
        tester,
      ) async {
        synthesizer.downloadGate = Completer<void>();
        await openOn(tester, network);
        expect(find.byTooltip('開啟語音模式'), findsOneWidget);
        expect(synthesizer.prepared, isEmpty);
        expect(voice.enabled, isFalse);

        await press(tester, find.byTooltip('開啟語音模式'));
        expect(find.text('要下載台語朗讀模型嗎？'), findsOneWidget);
        expect(find.textContaining('114 MB'), findsOneWidget);
        expect(synthesizer.downloadAttempts, 0);

        await press(tester, find.text('確定'));
        expect(find.text('台語語音下載中 42%'), findsOneWidget);
        expect(synthesizer.downloadAttempts, 1);

        synthesizer.downloadGate!.complete();
        await settle(tester);
        expect(find.text('台語語音下載中 42%'), findsNothing);
        expect(find.byTooltip('關閉語音模式'), findsOneWidget);
        expect(voice.enabled, isTrue);
      });
    }

    testWidgets('voice setup appears on home after deferring the recognizer', (
      tester,
    ) async {
      await openOn(tester, ModelNetwork.metered, speechModel: false);
      expect(find.text('先下載語音模型'), findsOneWidget);
      expect(find.byTooltip('開啟語音模式'), findsNothing);
      await press(tester, find.text('稍後下載，先使用錄音'));
      await press(tester, find.byTooltip('開啟語音模式'));
      expect(find.text('要下載台語朗讀模型嗎？'), findsOneWidget);
      await press(tester, find.text('稍後'));
      expect(find.text('先下載語音模型'), findsOneWidget);
      expect(synthesizer.downloadAttempts, 0);

      await model!.refresh();
      await settle(tester);
      expect(find.text('要下載台語朗讀模型嗎？'), findsNothing);
      await press(tester, find.byTooltip('開啟語音模式'));
      expect(find.text('要下載台語朗讀模型嗎？'), findsOneWidget);
    });

    testWidgets('a recording that was not understood is read aloud', (
      tester,
    ) async {
      synthesizer.installed = true;
      await openOn(tester, ModelNetwork.unmetered);
      await press(tester, find.byTooltip('開啟語音模式'));
      expect(find.byTooltip('關閉語音模式'), findsOneWidget);
      await say(tester, '');
      await settle(tester);
      expect(find.text('沒有聽清楚'), findsOneWidget);
      expect(player.played, ['Bô lio̍k tio̍h lí ê ōe koh kóng chi̍t pái']);

      // Starting the next recording silences the voice.
      await tester.tap(find.bySemanticsLabel('開始錄音'));
      await tester.pump();
      expect(player.events.last, 'stop');
      await tester.tap(find.bySemanticsLabel('停止錄音'));
      await settle(tester);
    });

    testWidgets('turning voice off stops playback and keeps the local model', (
      tester,
    ) async {
      synthesizer.installed = true;
      await openOn(tester, ModelNetwork.none);
      await press(tester, find.byTooltip('開啟語音模式'));
      expect(find.byTooltip('關閉語音模式'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await say(tester, '開手電筒');
      expect(player.played, hasLength(1));

      await press(tester, find.byTooltip('關閉語音模式'));
      expect(player.events.last, 'stop');
      await say(tester, '手電筒關掉');
      expect(find.text('手電筒關了'), findsOneWidget);
      expect(player.played, hasLength(1));

      await press(tester, find.byTooltip('開啟語音模式'));
      expect(find.byTooltip('關閉語音模式'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(synthesizer.downloadAttempts, 0);
    });

    for (final enabled in [false, true]) {
      testWidgets('SOS keeps voice enabled=$enabled without a toggle', (
        tester,
      ) async {
        synthesizer.installed = true;
        await openOn(tester, ModelNetwork.unmetered);
        if (enabled) await press(tester, find.byTooltip('開啟語音模式'));
        await press(tester, find.text('求救'));
        expect(find.text('需要幫忙嗎？'), findsOneWidget);
        expect(find.byTooltip('開啟語音模式'), findsNothing);
        expect(find.byTooltip('關閉語音模式'), findsNothing);
        expect(player.played.isNotEmpty, enabled);
        await press(tester, find.byTooltip('關閉'));
        expect(find.byTooltip(enabled ? '關閉語音模式' : '開啟語音模式'), findsOneWidget);
      });
    }

    testWidgets('an offline download cannot be confirmed', (tester) async {
      await openOn(tester, ModelNetwork.none);
      await press(tester, find.byTooltip('開啟語音模式'));
      expect(find.textContaining('目前沒有網路連線'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '確定'),
      );
      expect(confirm.onPressed, isNull);
      expect(synthesizer.downloadAttempts, 0);
    });
  });
}

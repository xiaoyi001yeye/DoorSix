import 'package:door_six/main.dart';
import 'package:door_six/models/app_update.dart';
import 'package:door_six/services/app_update_service.dart';
import 'package:door_six/widgets/app_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUpdateService extends AppUpdateService {
  @override
  Future<AppUpdateInfo?> checkLatest({
    bool manual = false,
    String source = 'startup',
  }) async {
    return AppUpdateInfo(
      type: AppUpdateType.optional,
      versionName: '0.1.1',
      versionCode: 2,
      title: '发现新版本',
      releaseNotes: const ['测试更新弹窗'],
      downloadUrl: 'http://example.com/door_six.apk',
      fileSizeBytes: 12 * 1024 * 1024,
      sha256: 'test',
      publishedAt: DateTime(2026, 5, 9),
    );
  }
}

void main() {
  testWidgets('DoorSix home renders primary actions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DoorSixApp());

    expect(find.text('砸六家'), findsOneWidget);
    expect(find.text('快速开始'), findsOneWidget);
    expect(find.text('练习桌'), findsOneWidget);
    expect(find.text('创建房间'), findsOneWidget);
    expect(find.text('加入房间'), findsOneWidget);
  });

  testWidgets('AppUpdateGate shows update dialog from app builder context',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Text('home'),
        builder: (context, child) {
          return AppUpdateGate(
            navigatorKey: navigatorKey,
            service: _FakeUpdateService(),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('测试更新弹窗'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

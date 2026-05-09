import 'package:door_six/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

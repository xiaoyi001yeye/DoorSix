import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'models/rule_set.dart';
import 'pages/game_table_page.dart';
import 'pages/home_page.dart';
import 'pages/online_room_page.dart';
import 'pages/rule_select_page.dart';
import 'pages/scoreboard_page.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  AppTheme.setSystemUi();
  runApp(const DoorSixApp());
}

class DoorSixApp extends StatelessWidget {
  const DoorSixApp({super.key});

  static final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/rules',
        builder: (context, state) => const RuleSelectPage(),
      ),
      GoRoute(
        path: '/table',
        builder: (context, state) {
          final ruleSet = state.extra is RuleSet
              ? state.extra! as RuleSet
              : RuleSet.tianjin;
          return GameTablePage(ruleSet: ruleSet);
        },
      ),
      GoRoute(
        path: '/online/create',
        builder: (context, state) {
          return const OnlineRoomPage(initialMode: OnlineEntryMode.create);
        },
      ),
      GoRoute(
        path: '/online/join',
        builder: (context, state) {
          return const OnlineRoomPage(initialMode: OnlineEntryMode.join);
        },
      ),
      GoRoute(
        path: '/scoreboard',
        builder: (context, state) => const ScoreboardPage(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DoorSix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: _router,
    );
  }
}

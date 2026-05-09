import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_update.dart';
import '../services/app_update_service.dart';
import 'app_update_dialog.dart';

class AppUpdateScope extends InheritedWidget {
  const AppUpdateScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final AppUpdateController controller;

  static AppUpdateController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppUpdateScope>();
    assert(scope != null, 'AppUpdateScope is missing');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(AppUpdateScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

class AppUpdateController {
  AppUpdateController._(this._state);

  final _AppUpdateGateState _state;

  Future<void> checkNow({
    bool manual = false,
    bool ignoreDismissal = false,
    String source = 'manual',
  }) {
    return _state._checkNow(
      manual: manual,
      ignoreDismissal: ignoreDismissal,
      source: source,
    );
  }
}

class AppUpdateGate extends StatefulWidget {
  AppUpdateGate({
    super.key,
    required this.child,
    this.navigatorKey,
    AppUpdateService? service,
  }) : service = service ?? AppUpdateService();

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final AppUpdateService service;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final AppUpdateController _controller = AppUpdateController._(this);
  bool _checking = false;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkNow(source: 'startup'));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_checkOnResume());
  }

  @override
  Widget build(BuildContext context) {
    return AppUpdateScope(
      controller: _controller,
      child: widget.child,
    );
  }

  Future<void> _checkOnResume() async {
    if (!await widget.service.shouldCheckOnResume()) {
      return;
    }
    await _checkNow(source: 'resume');
  }

  Future<void> _checkNow({
    bool manual = false,
    bool ignoreDismissal = false,
    String source = 'manual',
  }) async {
    if (_checking || _dialogShowing || !mounted) {
      return;
    }
    _checking = true;
    try {
      final info = await widget.service.checkLatest(
        manual: manual,
        source: source,
      );
      if (!mounted) {
        return;
      }
      if (info == null) {
        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前已经是最新版本')),
          );
        }
        return;
      }
      if (!ignoreDismissal && !info.isForce) {
        final shouldShow = await widget.service.stateStore
            .shouldShowOptionalUpdate(
          versionCode: info.versionCode,
          now: DateTime.now(),
        );
        if (!shouldShow && !manual) {
          return;
        }
      }
      await _showUpdateDialog(info);
    } finally {
      _checking = false;
    }
  }

  Future<void> _showUpdateDialog(AppUpdateInfo info) async {
    if (_dialogShowing || !mounted) {
      return;
    }
    final dialogContext = _dialogContext();
    if (dialogContext == null) {
      return;
    }
    _dialogShowing = true;
    try {
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: !info.isForce,
        builder: (context) {
          return AppUpdateDialog(
            info: info,
            stateStore: widget.service.stateStore,
          );
        },
      );
    } finally {
      _dialogShowing = false;
    }
  }

  BuildContext? _dialogContext() {
    final navigator = widget.navigatorKey?.currentState;
    final keyedContext = navigator?.overlay?.context ?? navigator?.context;
    if (keyedContext != null) {
      return keyedContext;
    }
    return Navigator.maybeOf(context) == null ? null : context;
  }
}

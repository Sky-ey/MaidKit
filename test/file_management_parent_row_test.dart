import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/file_management_tab.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
// ignore_for_file: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:super_native_extensions/src/native/context.dart'
    show setContextOverride;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // super_context_menu asks irondash_engine_context for a native engine
    // handle when its first ContextMenuWidget mounts; the plugin channel is
    // unavailable in tests. Its drag init also calls into the native
    // DragManager message channel, and its mobile menu builder probes
    // device_info_plus for background-blur support.
    final mockContext = MockMessageChannelContext()
      ..registerMockChannelHandler('DragManager', (message) async {
        return ['ok', null];
      });
    setContextOverride(mockContext);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.irondash.engine_context'),
          (call) async => call.method == 'getEngineHandle' ? 1 : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/device_info'),
          (call) async => <String, dynamic>{
            'computerName': 'Test Mac',
            'hostName': 'test.local',
            'arch': 'arm64',
            'model': 'Mac',
            'modelName': 'MacBook Pro',
            'kernelVersion': '27.0.0',
            'osRelease': '27.0.0',
            'majorVersion': 27,
            'minorVersion': 0,
            'patchVersion': 0,
            'activeCPUs': 8,
            'memorySize': 17179869184,
            'cpuFrequency': 0,
            'systemGUID': null,
          },
        );
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Server localServer() => Server(
    id: 7,
    name: 'Local machine',
    host: '127.0.0.1',
    port: 22,
    username: 'user',
    collectStats: true,
    collectSystemInfo: true,
    connectionType: ServerConnectionType.local.name,
  );

  /// Lets a real directory listing (and any pane animations) finish. Only
  /// valid inside [tester.runAsync].
  Future<void> settleListing(WidgetTester tester) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// Pumps a local-machine file-management tab. Must run inside
  /// [tester.runAsync]: the tab's [initState] lists a real directory, and the
  /// server list is pre-delivered so the tab mounts as a local-machine
  /// session (no SFTP side). Real time passes here, which also lets the pane
  /// split animation finish.
  Future<void> pumpTab(WidgetTester tester, {String? initialPath}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        serversProvider.overrideWithValue(AsyncValue.data([localServer()])),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: [
              ...material_ui.GlobalMaterialLocalizations.delegates,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'US')],
            home: Scaffold(
              body: Material(
                child: FileManagementTabView(
                  tab: FileManagementTab(
                    id: 'files',
                    serverId: 7,
                    serverName: 'Local machine',
                    initialPath: initialPath,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleListing(tester);
  }

  testWidgets('local list shows a .. row above the first directory', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpTab(tester);

      expect(find.text('..'), findsOneWidget);

      // The .. row leads the list: its folder icon renders above the first
      // real directory entry.
      final folderIcons = find.byIcon(Symbols.folder);
      expect(folderIcons, findsAtLeastNWidgets(2));
      final goUpTop = tester.getTopLeft(find.text('..')).dy;
      final firstEntryTop = tester.getTopLeft(folderIcons.at(1)).dy;
      expect(goUpTop, lessThan(firstEntryTop));
    });
  });

  testWidgets('tapping .. navigates to the parent directory', (tester) async {
    await tester.runAsync(() async {
      await pumpTab(tester);

      final parent = Directory(Directory.current.path).parent.path;
      await tester.tap(find.text('..'));
      await settleListing(tester);

      expect(find.text(parent), findsOneWidget);
    });
  });

  testWidgets('.. row is hidden at the filesystem root', (tester) async {
    await tester.runAsync(() async {
      await pumpTab(tester, initialPath: '/');

      expect(find.text('..'), findsNothing);
    });
  });

  testWidgets('mouse back/forward buttons navigate folder history', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('maidkit-nav-');
      final sub = Directory('${root.path}/sub')..createSync();
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      await pumpTab(tester, initialPath: sub.path);

      // The local pane header shows the current folder.
      expect(find.widgetWithText(TextButton, sub.path), findsOneWidget);

      // Go up to the parent; that records sub as the previous folder.
      await tester.tap(find.text('..'));
      await settleListing(tester);
      expect(find.widgetWithText(TextButton, root.path), findsOneWidget);

      // Back mouse button returns to sub.
      await _pressSideButton(tester, kBackMouseButton);
      await settleListing(tester);
      expect(find.widgetWithText(TextButton, sub.path), findsOneWidget);

      // Forward mouse button returns to the parent again.
      await _pressSideButton(tester, kForwardMouseButton);
      await settleListing(tester);
      expect(find.widgetWithText(TextButton, root.path), findsOneWidget);
    });
  });

  testWidgets('forward mouse button is a no-op without history', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpTab(tester);

      final current = Directory.current.path;
      await _pressSideButton(tester, kForwardMouseButton);
      await settleListing(tester);

      expect(find.widgetWithText(TextButton, current), findsOneWidget);
    });
  });
}

/// Dispatches a single mouse side-button press over the local pane.
Future<void> _pressSideButton(WidgetTester tester, int button) async {
  final location = tester.getCenter(find.text('..'));
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.down(location, buttons: button));
  await tester.sendEventToBinding(pointer.up());
}

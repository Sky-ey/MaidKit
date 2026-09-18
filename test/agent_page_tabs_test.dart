import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/agent/agent_page.dart';
import 'package:maid_kit/agent/agent_selection.dart';
import 'package:maid_kit/agent/conversation_store.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpAgent(WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            cloudUserProvider.overrideWith((ref) async => null),
            serversProvider.overrideWith(
              (ref) => Stream.value(const <Server>[]),
            ),
            mcpServersProvider.overrideWith(
              (ref) => Stream.value(const <McpServer>[]),
            ),
            agentProvidersProvider.overrideWith(
              (ref) => Stream.value(const <AgentProvider>[]),
            ),
            agentProviderModelsProvider.overrideWith(
              (ref, providerId) => Stream.value(const <AgentProviderModel>[]),
            ),
            agentConversationsProvider.overrideWith(
              (ref) => Stream.value(const <AgentConversation>[]),
            ),
            agentSelectionProvider.overrideWith(() => _StubSelectionNotifier()),
          ],
          child: const MaterialApp(home: AgentPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // All tabs stay mounted in the shell's IndexedStack; non-selected ones are
  // offstage, so prompt finders must not skip them.
  Finder prompts() => find.byType(TextField, skipOffstage: false);

  testWidgets('opens with a seeded chat tab', (tester) async {
    await pumpAgent(tester);

    // The seeded tab chip and its prompt are present.
    expect(find.text('agentNewConversation'.tr()), findsOneWidget);
    expect(prompts(), findsOneWidget);
    expect(find.byTooltip('agentNewConversation'.tr()), findsOneWidget);
  });

  testWidgets('adds a second tab and keeps both chats alive', (tester) async {
    await pumpAgent(tester);

    await tester.tap(find.byTooltip('agentNewConversation'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('agentNewConversation'.tr()), findsNWidgets(2));
    expect(prompts(), findsNWidgets(2));
  });

  testWidgets('prompt state is isolated and retained across tab switches', (
    tester,
  ) async {
    await pumpAgent(tester);

    await tester.tap(find.byTooltip('agentNewConversation'.tr()));
    await tester.pumpAndSettle();

    // Draft text in the second tab.
    tester.widget<TextField>(prompts().at(1)).controller!.text = 'kept draft';
    await tester.pump();

    // Switch to the first tab and back; the draft must survive.
    await tester.tap(find.text('agentNewConversation'.tr()).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('agentNewConversation'.tr()).at(1));
    await tester.pumpAndSettle();

    final prompt = tester.widget<TextField>(prompts().at(1));
    expect(prompt.controller!.text, 'kept draft');
  });

  testWidgets('closing a tab removes its chat', (tester) async {
    await pumpAgent(tester);

    await tester.tap(find.byTooltip('agentNewConversation'.tr()));
    await tester.pumpAndSettle();
    expect(prompts(), findsNWidgets(2));

    await tester.tap(find.byIcon(Symbols.close).first);
    await tester.pumpAndSettle();

    expect(prompts(), findsOneWidget);
    expect(find.text('agentNewConversation'.tr()), findsOneWidget);
  });
}

class _StubSelectionNotifier extends AgentSelectionNotifier {
  @override
  Future<AgentSelectionSettings> build() async =>
      InMemoryAgentSelectionSettings();
}

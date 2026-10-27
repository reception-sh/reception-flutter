import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/testing.dart';

/// Pass the App ID with `--dart-define=RECEPTION_APP_ID=app_...`; never commit it.
const appId = String.fromEnvironment(
  'RECEPTION_APP_ID',
  defaultValue: 'app_YOUR_APP_ID',
);

/// Local backend used by Debug builds.
final serviceUrl = Uri.parse(
  const String.fromEnvironment(
    'RECEPTION_SERVICE_URL',
    defaultValue: 'http://localhost:3123',
  ),
);

/// Configure in `main()` when a real App ID is set, so launch arguments such
/// as `-ReceptionSetupCheck` and push cold starts work without tapping.
/// `--dart-define=RECEPTION_AUTOSTART=false` leaves it to the Configure button.
const autostart =
    bool.fromEnvironment('RECEPTION_AUTOSTART', defaultValue: true) &&
    appId != 'app_YOUR_APP_ID';

final status = ValueNotifier('Ready');
final events = ValueNotifier<List<String>>(const []);
final configured = ValueNotifier(false);
final hangingAvailability = ValueNotifier(false);

void record(String event) {
  final previous = events.value;
  events.value = [...previous.skip(max(0, previous.length - 7)), event];
}

const _notifications = MethodChannel('reception_example/notifications');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Callbacks are cleared by a hot restart, so main() assigns them every time.
  Reception.onEvent = (event) => record(switch (event) {
    ChatOpenedEvent() => 'chatOpened',
    MessageSentEvent() => 'messageSent',
    ImageSentEvent() => 'imageSent',
    ReviewOpenedEvent() => 'reviewOpened',
    PaywallOpenedEvent() => 'paywallOpened',
    DataDeletedEvent() => 'dataDeleted',
    IdentityRejectedEvent(:final error) => 'identityRejected:${error.code}',
  });
  Reception.onPaywall = (id) =>
      record('onPaywall:$id, chat:${Reception.isChatOpen.value}');
  Reception.paywallAvailability = plansOnly;
  if (autostart) await run(configure, 'Configured at startup');
  runApp(const ExampleApp());
}

/// Allows only `plans`, after a short delay like a real eligibility check.
Future<bool> plansOnly(String id) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return id == 'plans';
}

Future<void> configure() async {
  if (kDebugMode) {
    await configureReceptionForTesting(appId: appId, serviceUrl: serviceUrl);
  } else {
    await Reception.configure(appId: appId);
  }
  configured.value = Reception.isConfigured;
  Reception.logLevel = LogLevel.debug;
  Reception.appearance = const Appearance(
    accentColor: AppearanceColor.adaptive(light: '#8A2BE2', dark: '#C89FFF'),
    chatBackground: AppearanceColor.adaptive(light: '#F5F1FA', dark: '#191024'),
    incomingBackground: AppearanceColor.adaptive(
      light: '#FFFFFF',
      dark: '#332641',
    ),
    incomingForeground: AppearanceColor.adaptive(
      light: '#23172E',
      dark: '#F8F1FF',
    ),
    onAccentColor: AppearanceColor.adaptive(light: '#FFFFFF', dark: '#22112F'),
    showsCloseButton: true,
  );
  Reception.usesRemoteAppearance = false;
  Reception.paywalls = const [
    ReceptionPaywall(id: 'plans', title: 'Plans'),
    ReceptionPaywall(id: 'hidden', title: 'Unavailable plan'),
  ];
  await Reception.refreshPaywalls(invalidate: true);
}

/// Runs [action] and reports the outcome in the status line.
Future<void> run(Future<void> Function() action, String success) async {
  try {
    await action();
    status.value = success;
  } on ReceptionError catch (error) {
    status.value = 'Failed: ${error.code} (${error.status})';
  } catch (error) {
    status.value = 'Failed: $error';
  }
}

Future<void> enableNotifications() async {
  final granted = await _notifications.invokeMethod<bool>('requestPermission');
  await Reception.registerForPushIfAuthorized();
  status.value = 'Notifications: ${granted == true ? 'granted' : 'denied'}';
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Reception Flutter',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF8A2BE2)),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF8A2BE2),
      brightness: Brightness.dark,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget button(String label, VoidCallback onPressed) =>
        OutlinedButton(onPressed: onPressed, child: Text(label));
    return Scaffold(
      appBar: AppBar(title: const Text('Reception verification')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _StateLine(),
          ValueListenableBuilder(
            valueListenable: status,
            builder: (context, value, _) =>
                Text('$value · SDK ${Reception.version}'),
          ),
          ValueListenableBuilder(
            valueListenable: Reception.availablePaywalls,
            builder: (context, paywalls, _) => Text(
              'Available: ${paywalls.map((paywall) => paywall.id).join(', ')}',
            ),
          ),
          const SizedBox(height: 8),
          button('Calls before configure', () {
            run(() async {
              await Reception.openChat();
              await Reception.closeChat();
              await Reception.identify(
                const Identity.user(userId: 'before-configure'),
              );
              await Reception.setMetadata({'stage': 'before'});
              await Reception.setPushToken(
                'aabb',
                environment: PushEnvironment.sandbox,
              );
              await Reception.logout();
              await Reception.deleteData();
            }, 'Preconfigure calls completed');
          }),
          button('Configure', () => run(configure, 'Configured')),
          ValueListenableBuilder(
            valueListenable: Reception.unreadCount,
            builder: (context, unread, _) => FilledButton.icon(
              onPressed: () => run(Reception.openChat, 'Open requested'),
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.support_agent),
              ),
              label: const Text('Open chat'),
            ),
          ),
          button(
            'Embedded chat',
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EmbeddedChatPage()),
            ),
          ),
          button('Open then close after 3s', () {
            run(() async {
              await Reception.openChat();
              Timer(const Duration(seconds: 3), Reception.closeChat);
            }, 'Close scheduled');
          }),
          button('Track paywall declined', () {
            run(
              () => Reception.track('paywall_declined', opensChat: true),
              'Event tracked',
            );
          }),
          button('Identify and metadata', () {
            run(() async {
              await Reception.identify(
                const Identity.user(
                  userId: 'flutter-verification-user',
                  name: 'Flutter Test Customer',
                  email: 'flutter-test@example.test',
                ),
              );
              await Reception.setMetadata({
                'plan': 'Pro',
                'source': 'Flutter example',
              });
            }, 'Identity and metadata staged');
          }),
          button('Identify with invalid token', () {
            run(
              () => Reception.identify(
                const Identity.token('invalid.test.token'),
              ),
              'Token identity staged',
            );
          }),
          button('German / app language', () {
            Reception.languageOverride = Reception.languageOverride == null
                ? 'de'
                : null;
            status.value = 'Language: ${Reception.languageOverride ?? 'app'}';
          }),
          ValueListenableBuilder(
            valueListenable: hangingAvailability,
            builder: (context, hanging, _) => SwitchListTile(
              title: const Text('Hanging availability'),
              value: hanging,
              onChanged: (value) {
                hangingAvailability.value = value;
                // A future that never completes; native fails closed after 5 s.
                Reception.paywallAvailability = value
                    ? (id) => Completer<bool>().future
                    : plansOnly;
                status.value = value
                    ? 'Availability waiting (5 s timeout)'
                    : 'Availability restored';
              },
            ),
          ),
          button('Refresh paywalls', () {
            run(
              () => Reception.refreshPaywalls(invalidate: true),
              'Paywalls refreshed',
            );
          }),
          button('Enable notifications', () {
            run(enableNotifications, 'Notifications requested');
          }),
          button('Logout', () => run(Reception.logout, 'Logged out')),
          button(
            'Delete support data',
            () => run(Reception.deleteData, 'Data deletion resolved'),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: events,
            builder: (context, values, _) => Text(
              values.join('\n'),
              key: const Key('events'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live unread count, chat visibility and configuration state.
class _StateLine extends StatelessWidget {
  const _StateLine();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      Reception.unreadCount,
      Reception.isChatOpen,
      configured,
    ]),
    builder: (context, _) => Text(
      'Unread: ${Reception.unreadCount.value} · '
      'Chat open: ${Reception.isChatOpen.value} · '
      'Configured: ${Reception.isConfigured}',
      key: const Key('state'),
    ),
  );
}

class EmbeddedChatPage extends StatelessWidget {
  const EmbeddedChatPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Embedded chat')),
    body: const Column(children: [Expanded(child: ReceptionChatView())]),
  );
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reception_flutter/reception_flutter.dart';
import 'package:reception_flutter/testing.dart';

/// Pass the App ID with `--dart-define=RECEPTION_APP_ID=app_...`; never commit it.
const appId = String.fromEnvironment(
  'RECEPTION_APP_ID',
  defaultValue: 'app_YOUR_APP_ID',
);

/// Optional local backend, for example
/// `--dart-define=RECEPTION_SERVICE_URL=http://localhost:3123`. Without it the
/// app uses the production service through `Reception.configure`.
const serviceUrl = String.fromEnvironment('RECEPTION_SERVICE_URL');

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
  debugPrint('[example] event $event');
  final previous = events.value;
  events.value = [...previous.skip(max(0, previous.length - 7)), event];
}

const _notifications = MethodChannel('reception_example/notifications');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Callbacks are cleared by a hot restart, so main() assigns them every time.
  Reception.onEvent = (event) => record(switch (event) {
    ReceptionChatOpened() => 'chatOpened',
    ReceptionMessageSent() => 'messageSent',
    ReceptionImageSent() => 'imageSent',
    ReceptionReviewOpened() => 'reviewOpened',
    ReceptionPaywallOpened() => 'paywallOpened',
    ReceptionDataDeleted() => 'dataDeleted',
    ReceptionIdentityRejected(:final error) => 'identityRejected:${error.code}',
  });
  Reception.onPaywall = (id) =>
      record('onPaywall:$id, chat:${Reception.isChatOpen.value}');
  Reception.paywallAvailability = plansOnly;
  // Console trace for `flutter run`, for example to watch a hot restart
  // re-read native state.
  Reception.unreadCount.addListener(
    () => debugPrint('[example] unread ${Reception.unreadCount.value}'),
  );
  Reception.availablePaywalls.addListener(
    () => debugPrint(
      '[example] available '
      '${Reception.availablePaywalls.value.map((paywall) => paywall.id)}',
    ),
  );
  if (autostart) await run(configure, null);
  debugPrint(
    '[example] started: configured ${Reception.isConfigured}, '
    'unread ${Reception.unreadCount.value}',
  );
  runApp(const ExampleApp());
}

/// Allows only `plans`, after a short delay like a real eligibility check.
Future<bool> plansOnly(String id) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return id == 'plans';
}

/// Configures Reception and reports the native result in the status line.
Future<void> configure() async {
  if (serviceUrl.isEmpty) {
    await Reception.configure(appId: appId);
  } else {
    // Debug simulator builds with a localhost URL only; a no-op otherwise.
    await configureReceptionForTesting(
      appId: appId,
      serviceUrl: Uri.parse(serviceUrl),
    );
  }
  configured.value = Reception.isConfigured;
  status.value = Reception.isConfigured ? 'Configured' : 'Configured: false';
  Reception.logLevel = ReceptionLogLevel.debug;
  Reception.appearance = const ReceptionAppearance(
    accentColor: ReceptionColor.adaptive(light: '#8A2BE2', dark: '#C89FFF'),
    chatBackground: ReceptionColor.adaptive(light: '#F5F1FA', dark: '#191024'),
    incomingBackground: ReceptionColor.adaptive(
      light: '#FFFFFF',
      dark: '#332641',
    ),
    incomingForeground: ReceptionColor.adaptive(
      light: '#23172E',
      dark: '#F8F1FF',
    ),
    onAccentColor: ReceptionColor.adaptive(light: '#FFFFFF', dark: '#22112F'),
    showsCloseButton: true,
  );
  Reception.usesRemoteAppearance = false;
  Reception.paywalls = [
    ReceptionPaywall(id: 'plans', title: 'Plans'),
    ReceptionPaywall(id: 'hidden', title: 'Unavailable plan'),
  ];
  await Reception.refreshPaywalls(invalidate: true);
}

/// Runs [action] and reports the outcome in the status line; a null
/// [success] keeps the status that [action] set.
Future<void> run(Future<void> Function() action, String? success) async {
  try {
    await action();
    if (success != null) status.value = success;
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
                const ReceptionIdentity.user(userId: 'before-configure'),
              );
              await Reception.setMetadata({'stage': 'before'});
              await Reception.setPushToken(
                'aabb',
                environment: ReceptionPushEnvironment.sandbox,
              );
              await Reception.logout();
              await Reception.deleteData();
            }, 'Preconfigure calls completed');
          }),
          button('Configure', () => run(configure, null)),
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
                const ReceptionIdentity.user(
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
                const ReceptionIdentity.token('invalid.test.token'),
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
            run(enableNotifications, null);
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

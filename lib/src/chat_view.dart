import 'package:flutter/widgets.dart';

import 'platform.dart';

/// The native chat embedded in your screen. Give it a defined size; your
/// screen owns dismissal. Renders nothing off iOS.
class ReceptionChatView extends StatelessWidget {
  /// Creates the embedded chat.
  const ReceptionChatView({super.key});

  @override
  Widget build(BuildContext context) => checkSupported()
      ? const UiKitView(viewType: 'reception_flutter/chat')
      : const SizedBox.shrink();
}

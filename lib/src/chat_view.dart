import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform.dart';

const _viewType = 'reception_flutter/chat';

/// The native chat embedded in your screen. Give it a defined size; your
/// screen owns dismissal. Renders nothing off iOS and Android.
class ReceptionChatView extends StatefulWidget {
  /// Creates the embedded chat.
  const ReceptionChatView({
    super.key,
    this.gestureRecognizers = defaultGestureRecognizers,
  });

  /// Gestures the native chat claims before Flutter widgets around it (see
  /// `AndroidViewSurface.gestureRecognizers` and `UiKitView.gestureRecognizers`).
  /// The default, [defaultGestureRecognizers], claims vertical drags, so the
  /// chat scrolls inside a scrolling ancestor such as a `ListView` or
  /// `DraggableScrollableSheet`. Pass an empty set to let ancestors take
  /// vertical drags, or add recognizers to claim more.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// Claims vertical drags for the chat's own scrolling.
  static const Set<Factory<OneSequenceGestureRecognizer>>
  defaultGestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(VerticalDragGestureRecognizer.new),
  };

  @override
  State<ReceptionChatView> createState() => _ReceptionChatViewState();
}

class _ReceptionChatViewState extends State<ReceptionChatView> {
  /// `PlatformViewLink` builds its surface once and keeps it, so the surface
  /// reads the recognizers from here and rebuilds with the same controller
  /// when they change.
  late final _recognizers = ValueNotifier(widget.gestureRecognizers);

  @override
  void didUpdateWidget(ReceptionChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recognizers.value = widget.gestureRecognizers;
  }

  @override
  void dispose() {
    _recognizers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!checkSupported()) return const SizedBox.shrink();
    if (!isAndroid) {
      return UiKitView(
        viewType: _viewType,
        gestureRecognizers: widget.gestureRecognizers,
      );
    }
    // Hybrid composition: the chat is a real Android view in the window, so
    // its text field and the keyboard behave as in a native screen.
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) =>
          ValueListenableBuilder<Set<Factory<OneSequenceGestureRecognizer>>>(
            valueListenable: _recognizers,
            builder: (context, recognizers, _) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: recognizers,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
          ),
      onCreatePlatformView: (params) =>
          PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection:
                  Directionality.maybeOf(context) ?? TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create(),
    );
  }
}

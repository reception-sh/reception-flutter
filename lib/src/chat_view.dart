import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform.dart';

const _viewType = 'reception_flutter/chat';

/// The native chat embedded in your screen. Give it a defined size; your
/// screen owns dismissal. Renders nothing off iOS and Android.
class ReceptionChatView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!checkSupported()) return const SizedBox.shrink();
    if (!isAndroid) {
      return UiKitView(
        viewType: _viewType,
        gestureRecognizers: gestureRecognizers,
      );
    }
    // Hybrid composition: the chat is a real Android view in the window, so
    // its text field and the keyboard behave as in a native screen.
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: gestureRecognizers,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
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

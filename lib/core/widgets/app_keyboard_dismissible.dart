import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Shared form surface that dismisses the keyboard from unused space without
/// competing with text selection or interactive child controls.
class AppKeyboardDismissible extends StatelessWidget {
  const AppKeyboardDismissible({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    key: const ValueKey('app-keyboard-dismissible'),
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      final focus = FocusManager.instance.primaryFocus;
      RenderEditable? editable;
      void findEditable(Element element) {
        if (editable != null) return;
        final renderObject = element.renderObject;
        if (renderObject is RenderEditable) {
          editable = renderObject;
          return;
        }
        element.visitChildElements(findEditable);
      }

      final focusContext = focus?.context;
      if (focusContext is Element) findEditable(focusContext);
      final renderEditable = editable;
      if (renderEditable != null && renderEditable.attached) {
        final localPosition = renderEditable.globalToLocal(event.position);
        if (renderEditable.size.contains(localPosition)) return;
      }
      focus?.unfocus();
    },
    child: child,
  );
}

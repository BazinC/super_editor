import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_text_layout/super_text_layout.dart';

import '../test_runners.dart';
import 'super_textfield_inspector.dart';

void main() {
  group('SuperTextField', () {
    testWidgetsOnAllPlatforms('single-line jumps scroll position horizontally as the user types', (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("ABCDEFG"),
      );

      // Pump the widget tree with a SuperTextField with a maxWidth smaller
      // than the text width
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 1,
        maxWidth: 50,
      );

      // Move selection to the end of the text
      // TODO: change to simulate user input when IME simulation is available
      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pumpAndSettle();

      // Position at the end of the viewport
      final viewportRight = tester.getBottomRight(find.byType(SuperTextField)).dx;

      // Position at the end of the text
      final textRight = tester.getBottomRight(find.byType(SuperText)).dx;

      // Ensure the text field scrolled its content horizontally
      expect(textRight, lessThanOrEqualTo(viewportRight));
    });

    testWidgetsOnAllPlatforms('multi-line jumps scroll position vertically as the user types', (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("A\nB\nC\nD"),
      );

      // Pump the widget tree with a SuperTextField with a maxHeight smaller
      // than the text heght
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 20,
      );

      // Move selection to the end of the text
      // TODO: change to simulate user input when IME simulation is available
      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pumpAndSettle();

      // Position at the end of the viewport
      final viewportBottom = tester.getBottomRight(find.byType(SuperTextField)).dy;

      // Position at the end of the text
      final textBottom = tester.getBottomRight(find.byType(SuperText)).dy;

      // Ensure the text field scrolled its content vertically
      expect(textBottom, lessThanOrEqualTo(viewportBottom));
    });

    testWidgetsOnAllPlatforms(
        "multi-line jumps scroll position vertically when selection extent moves above or below the visible viewport area",
        (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("First line\nSecond Line\nThird Line\nFourth Line"),
      );

      // Pump the widget tree with a SuperTextField which is two lines tall.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 40,
      );

      // Move selection to the end of the text.
      // This will scroll the text field to the end.
      controller.selection = const TextSelection.collapsed(offset: 45);
      await tester.pumpAndSettle();

      // Ensure the text field has scrolled.
      expect(
        SuperTextFieldInspector.findScrollOffset(),
        greaterThan(0.0),
      );

      // Place the caret at the beginning of the text.
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pumpAndSettle();

      // Ensure the text field scrolled to the top.
      expect(
        SuperTextFieldInspector.findScrollOffset(),
        0.0,
      );
    });

    testWidgetsOnAllPlatforms("multi-line doesn't jump scroll position vertically when selection extent is visible",
        (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("First line\nSecond Line\nThird Line\nFourth Line"),
      );

      // Pump the widget tree with a SuperTextField which is two lines tall.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 40,
      );

      // Move selection to the end of the text.
      // This will scroll the text field to the end.
      controller.selection = const TextSelection.collapsed(offset: 45);
      await tester.pumpAndSettle();

      final scrollOffsetBefore = SuperTextFieldInspector.findScrollOffset();

      // Place the caret at "Third| Line".
      // As we have room for two lines, this line is already visible,
      // and thus shouldn't cause the text field to scroll.
      controller.selection = const TextSelection.collapsed(offset: 28);
      await tester.pumpAndSettle();

      // Ensure the content didn't scrolled.
      expect(
        SuperTextFieldInspector.findScrollOffset(),
        scrollOffsetBefore,
      );
    });

    testWidgetsOnDesktop("doesn't scroll vertically when maxLines is null", (tester) async {
      // With the Ahem font the estimated line height is equal to the true line height
      // so we need to use a custom font.
      await loadAppFonts();

      // We use some padding because it affects the viewport height calculation.
      const verticalPadding = 6.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300),
              child: SuperDesktopTextField(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: verticalPadding),
                minLines: 1,
                maxLines: null,
                textController: AttributedTextEditingController(
                  text: AttributedText("SuperTextField"),
                ),
                textStyleBuilder: (_) => const TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // In the running app, the estimated line height and actual line height differ.
      // This test ensures that we account for that. Ideally, this test would check that the scrollview doesn't scroll.
      // However, in test suites, the estimated and actual line heights are always identical.
      // Therefore, this test ensures that we add up the appropriate dimensions,
      // rather than verify the scrollview's max scroll extent.

      final viewportHeight = tester.getRect(find.byType(SuperTextFieldScrollview)).height;

      final layoutState =
          (find.byType(SuperDesktopTextField).evaluate().single as StatefulElement).state as SuperDesktopTextFieldState;
      final contentHeight = layoutState.textLayout.getLineHeightAtPosition(const TextPosition(offset: 0));

      // Vertical padding is added to both top and bottom
      final totalHeight = contentHeight + (verticalPadding * 2);

      // Ensure the viewport is big enough so the text doesn't scroll vertically
      expect(viewportHeight, greaterThanOrEqualTo(totalHeight));
    });

    group("textfield scrolling", () {
      testWidgetsOnDesktopAndWeb(
        'PAGE DOWN scrolls down by the viewport height',
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;

          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
            padding: const EdgeInsets.all(20),
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

          // Let the scrolling system auto-scroll, as desired.
          await tester.pumpAndSettle();

          // Ensure we scrolled down by the viewport height.
          expect(
            scrollState.position.pixels,
            equals(scrollState.position.viewportDimension),
          );
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        'PAGE DOWN does not scroll past bottom of the viewport',
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          // Scroll very close to the bottom but not all the way to avoid explicit
          // checks comparing scroll offset directly against `maxScrollExtent`
          // and test scrolling behaviour in more realistic manner.
          scrollState.position.jumpTo(scrollState.position.maxScrollExtent - 10);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

          // Let the scrolling system auto-scroll, as desired.
          await tester.pumpAndSettle();

          // Ensure we didn't scroll past the bottom of the viewport.
          expect(scrollState.position.pixels, equals(scrollState.position.maxScrollExtent));
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        'PAGE UP scrolls up by the viewport height',
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          // Scroll to the bottom of the viewport.
          scrollState.position.jumpTo(scrollState.position.maxScrollExtent);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);

          // Let the scrolling system auto-scroll, as desired.
          await tester.pumpAndSettle();

          // Ensure we scrolled up by the viewport height.
          expect(
            scrollState.position.pixels,
            equals(scrollState.position.maxScrollExtent - scrollState.position.viewportDimension),
          );
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        'PAGE UP does not scroll past top of the viewport',
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          // Scroll very close to the top but not all the way to avoid explicit
          // checks comparing scroll offset directly against `minScrollExtent`
          // and test scrolling behaviour in more realistic manner.
          scrollState.position.jumpTo(scrollState.position.minScrollExtent + 10);

          await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);

          // Let the scrolling system auto-scroll, as desired.
          await tester.pumpAndSettle();

          // Ensure we didn't scroll past the top of the viewport.
          expect(scrollState.position.pixels, equals(scrollState.position.minScrollExtent));
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        'CMD + HOME on mac/ios and CTRL + HOME on other platforms scrolls to top of viewport',
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          // Scroll to the bottom of the viewport.
          scrollState.position.jumpTo(scrollState.position.maxScrollExtent);

          if (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS) {
            await _pressCmdHome(tester);
          } else {
            await _pressCtrlHome(tester);
          }

          // Ensure we scrolled to the top of the viewport.
          expect(
            scrollState.position.pixels,
            equals(scrollState.position.minScrollExtent),
          );
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        "CMD + HOME on mac/ios and CTRL + HOME on other platforms does not scroll past top of the viewport",
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          // Scroll very close to the top but not all the way to avoid explicit
          // checks comparing scroll offset directly against `minScrollExtent`
          // and test scrolling behaviour in more realistic manner.
          scrollState.position.jumpTo(scrollState.position.minScrollExtent + 10);

          if (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS) {
            await _pressCmdHome(tester);
          } else {
            await _pressCtrlHome(tester);
          }

          // Ensure we didn't scroll past the top of the viewport.
          expect(scrollState.position.pixels, equals(scrollState.position.minScrollExtent));
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        "CMD + END on mac/ios and CTRL + END on other platforms scrolls to bottom of viewport",
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          if (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS) {
            await _pressCmdEnd(tester);
          } else {
            await _pressCtrlEnd(tester);
          }

          // Ensure we scrolled to the bottom of the viewport.
          expect(scrollState.position.pixels, equals(scrollState.position.maxScrollExtent));
        },
        variant: _scrollingVariant,
      );

      testWidgetsOnDesktopAndWeb(
        "CMD + END on mac/ios and CTRL + END on other platforms does not scroll past bottom of the viewport",
        (tester) async {
          final currentVariant = _scrollingVariant.currentValue;
          final controller = AttributedTextEditingController(
            text: AttributedText(_scrollableTextFieldText),
          );

          // Pump the widget tree with a SuperTextField which is four lines tall.
          await _pumpTestApp(
            tester,
            textController: controller,
            minLines: 1,
            maxLines: 4,
            textInputSource: currentVariant!.textInputSource,
          );

          // Tap at top left in the textfield to focus it
          await tester.tapAt(tester.getTopLeft(find.byType(SuperTextField)));
          await tester.pump();

          final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

          // Scroll very close to the bottom but not all the way to avoid explicit
          // checks comparing scroll offset directly against `maxScrollExtent`
          // and test scrolling behaviour in more realistic manner.
          scrollState.position.jumpTo(scrollState.position.maxScrollExtent - 10);

          if (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS) {
            await _pressCmdEnd(tester);
          } else {
            await _pressCtrlEnd(tester);
          }

          // Ensure we didn't scroll past the bottom of the viewport.
          expect(scrollState.position.pixels, equals(scrollState.position.maxScrollExtent));
        },
        variant: _scrollingVariant,
      );
    });
  });
}

Future<void> _pumpTestApp(
  WidgetTester tester, {
  required AttributedTextEditingController textController,
  required int minLines,
  required int maxLines,
  double? maxWidth,
  double? maxHeight,
  EdgeInsets? padding,
  TextInputSource? textInputSource,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? double.infinity,
            maxHeight: maxHeight ?? double.infinity,
          ),
          child: SuperTextField(
            textController: textController,
            lineHeight: 20,
            textStyleBuilder: (_) => const TextStyle(fontSize: 20),
            minLines: minLines,
            maxLines: maxLines,
            padding: padding,
            inputSource: textInputSource,
          ),
        ),
      ),
    ),
  );

  // The first frame might have a zero viewport height. Pump a second frame to account for the final viewport size.
  await tester.pump();
}

final String _scrollableTextFieldText = List.generate(10, (index) => "Line $index").join("\n");

Future<void> _pressCmdHome(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta, platform: 'macos');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.home, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.home, platform: 'macos');
  await tester.pumpAndSettle();
}

Future<void> _pressCmdEnd(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta, platform: 'macos');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.end, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.end, platform: 'macos');
  await tester.pumpAndSettle();
}

Future<void> _pressCtrlHome(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control, platform: 'macos');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.home, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.home, platform: 'macos');
  await tester.pumpAndSettle();
}

Future<void> _pressCtrlEnd(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control, platform: 'macos');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.end, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.end, platform: 'macos');
  await tester.pumpAndSettle();
}

/// Variant for an editor experience with an internal scrollable and
/// an ancestor scrollable.
final _scrollingVariant = ValueVariant<_SuperTextFieldScrollSetup>({
  const _SuperTextFieldScrollSetup(
    textInputSource: TextInputSource.ime,
  ),
  const _SuperTextFieldScrollSetup(
    textInputSource: TextInputSource.keyboard,
  ),
});

class _SuperTextFieldScrollSetup {
  const _SuperTextFieldScrollSetup({
    required this.textInputSource,
  });
  final TextInputSource textInputSource;

  @override
  String toString() {
    return "SuperTextFieldScrollSetup: ${textInputSource.toString()}";
  }
}

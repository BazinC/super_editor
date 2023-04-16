import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_editor.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';
import 'package:super_editor/src/infrastructure/raw_key_event_extensions.dart';

import 'layout_single_column/layout_single_column.dart';
import 'text_tools.dart';

class ParagraphNode extends TextNode {
  ParagraphNode({
    required String id,
    required AttributedText text,
    Map<String, dynamic>? metadata,
  }) : super(
          id: id,
          text: text,
          metadata: metadata,
        ) {
    if (getMetadataValue("blockType") == null) {
      putMetadataValue("blockType", const NamedAttribution("paragraph"));
    }
  }
}

class ParagraphComponentBuilder implements ComponentBuilder {
  const ParagraphComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! ParagraphNode) {
      return null;
    }

    final textDirection = getParagraphDirection(node.text.text);

    TextAlign textAlign = (textDirection == TextDirection.ltr) ? TextAlign.left : TextAlign.right;
    final textAlignName = node.getMetadataValue('textAlign');
    switch (textAlignName) {
      case 'left':
        textAlign = TextAlign.left;
        break;
      case 'center':
        textAlign = TextAlign.center;
        break;
      case 'right':
        textAlign = TextAlign.right;
        break;
      case 'justify':
        textAlign = TextAlign.justify;
        break;
    }

    return ParagraphComponentViewModel(
      nodeId: node.id,
      blockType: node.getMetadataValue('blockType'),
      text: node.text,
      textDirection: textDirection,
      textAlignment: textAlign,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  TextComponent? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! ParagraphComponentViewModel) {
      return null;
    }

    editorLayoutLog.fine("Building paragraph component for node: ${componentViewModel.nodeId}");

    if (componentViewModel.selection != null) {
      editorLayoutLog.finer(' - painting a text selection:');
      editorLayoutLog.finer('   base: ${componentViewModel.selection!.base}');
      editorLayoutLog.finer('   extent: ${componentViewModel.selection!.extent}');
    } else {
      editorLayoutLog.finer(' - not painting any text selection');
    }

    return TextComponent(
      key: componentContext.componentKey,
      text: componentViewModel.text,
      textStyleBuilder: componentViewModel.textStyleBuilder,
      metadata: componentViewModel.blockType != null
          ? {
              'blockType': componentViewModel.blockType,
            }
          : {},
      textAlign: componentViewModel.textAlignment,
      textDirection: componentViewModel.textDirection,
      textSelection: componentViewModel.selection,
      selectionColor: componentViewModel.selectionColor,
      highlightWhenEmpty: componentViewModel.highlightWhenEmpty,
    );
  }
}

class ParagraphComponentViewModel extends SingleColumnLayoutComponentViewModel with TextComponentViewModel {
  ParagraphComponentViewModel({
    required String nodeId,
    double? maxWidth,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    this.blockType,
    required this.text,
    TextComponentTextStyles? textStyler,
    this.textDirection = TextDirection.ltr,
    this.textAlignment = TextAlign.left,
    this.selection,
    required this.selectionColor,
    this.highlightWhenEmpty = false,
  }) : super(nodeId: nodeId, maxWidth: maxWidth, padding: padding) {
    if (textStyler != null) {
      super.textStyler = textStyler;
    }
  }

  Attribution? blockType;
  @override
  AttributedText text;
  @override
  TextDirection textDirection;
  @override
  TextAlign textAlignment;
  @override
  TextSelection? selection;
  @override
  Color selectionColor;
  @override
  bool highlightWhenEmpty;

  @override
  ParagraphComponentViewModel copy() {
    return ParagraphComponentViewModel(
      nodeId: nodeId,
      maxWidth: maxWidth,
      padding: padding,
      blockType: blockType,
      text: text,
      textStyler: textStyler,
      textDirection: textDirection,
      textAlignment: textAlignment,
      selection: selection,
      selectionColor: selectionColor,
      highlightWhenEmpty: highlightWhenEmpty,
    );
  }

  // TODO: we shouldn't override == and hashCode for mutable objects.
  //       Find another way to implement the use-cases for comparison.
  @override
  bool operator ==(Object other) {
    // print("Comparing $this and $other");
    // print("super == other? ${super == other}");
    // print("other is ParagraphComponentViewModel? ${other is ParagraphComponentViewModel}");
    // if (other is! ParagraphComponentViewModel) {
    //   return false;
    // }
    // print("nodeId == other.nodeId ${nodeId == other.nodeId}");
    // print("This node $nodeId vs other node ${other.nodeId}");
    // print("blockType == other.blockType? ${blockType == other.blockType}");

    return identical(this, other) ||
        super == other &&
            other is ParagraphComponentViewModel &&
            runtimeType == other.runtimeType &&
            nodeId == other.nodeId &&
            blockType == other.blockType &&
            isTextViewModelEquivalent(other);
  }

  @override
  int get hashCode => super.hashCode ^ nodeId.hashCode ^ blockType.hashCode ^ textHashCode;
}

/// [EditRequest] to combine the [ParagraphNode] with [firstNodeId] with the [ParagraphNode] after it, which
/// should have the [secondNodeId].
class CombineParagraphsRequest implements EditRequest {
  CombineParagraphsRequest({
    required this.firstNodeId,
    required this.secondNodeId,
  }) : assert(firstNodeId != secondNodeId);

  final String firstNodeId;
  final String secondNodeId;
}

/// Combines two consecutive `ParagraphNode`s, indicated by `firstNodeId`
/// and `secondNodeId`, respectively.
///
/// If the specified nodes are not sequential, or are sequential
/// in reverse order, the command fizzles.
///
/// If both nodes are not `ParagraphNode`s, the command fizzles.
class CombineParagraphsCommand implements EditCommand {
  CombineParagraphsCommand({
    required this.firstNodeId,
    required this.secondNodeId,
  }) : assert(firstNodeId != secondNodeId);

  final String firstNodeId;
  final String secondNodeId;

  @override
  void execute(EditorContext context, CommandExecutor executor) {
    editorDocLog.info('Executing CombineParagraphsCommand');
    editorDocLog.info(' - merging "$firstNodeId" <- "$secondNodeId"');
    final document = context.find<MutableDocument>(DocumentEditor.documentKey);
    final secondNode = document.getNodeById(secondNodeId);
    if (secondNode is! TextNode) {
      editorDocLog.info('WARNING: Cannot merge node of type: $secondNode into node above.');
      return;
    }

    final nodeAbove = document.getNodeBefore(secondNode);
    if (nodeAbove == null) {
      editorDocLog.info('At top of document. Cannot merge with node above.');
      return;
    }
    if (nodeAbove.id != firstNodeId) {
      editorDocLog.info('The specified `firstNodeId` is not the node before `secondNodeId`.');
      return;
    }
    if (nodeAbove is! TextNode) {
      editorDocLog.info('Cannot merge ParagraphNode into node of type: $nodeAbove');
      return;
    }

    // Combine the text and delete the currently selected node.
    final isTopNodeEmpty = nodeAbove.text.text.isEmpty;
    nodeAbove.text = nodeAbove.text.copyAndAppend(secondNode.text);
    if (isTopNodeEmpty) {
      // If the top node was empty, we want to retain everything in the
      // bottom node, including the block attribution and styles.
      nodeAbove.metadata = secondNode.metadata;
    }
    bool didRemove = document.deleteNode(secondNode);
    if (!didRemove) {
      editorDocLog.info('ERROR: Failed to delete the currently selected node from the document.');
    }

    executor.logChanges([
      NodeRemovedEvent(secondNode.id),
      NodeChangeEvent(nodeAbove.id),
    ]);
  }
}

class SplitParagraphRequest implements EditRequest {
  SplitParagraphRequest({
    required this.nodeId,
    required this.splitPosition,
    required this.newNodeId,
    required this.replicateExistingMetadata,
  });

  final String nodeId;
  final TextPosition splitPosition;
  final String newNodeId;
  final bool replicateExistingMetadata;
}

/// Splits the `ParagraphNode` affiliated with the given `nodeId` at the
/// given `splitPosition`, placing all text after `splitPosition` in a
/// new `ParagraphNode` with the given `newNodeId`, inserted after the
/// original node.
class SplitParagraphCommand implements EditCommand {
  SplitParagraphCommand({
    required this.nodeId,
    required this.splitPosition,
    required this.newNodeId,
    required this.replicateExistingMetadata,
  });

  final String nodeId;
  final TextPosition splitPosition;
  final String newNodeId;
  final bool replicateExistingMetadata;

  @override
  void execute(EditorContext context, CommandExecutor executor) {
    editorDocLog.info('Executing SplitParagraphCommand');

    final document = context.find<MutableDocument>(DocumentEditor.documentKey);
    final node = document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      editorDocLog.info('WARNING: Cannot split paragraph for node of type: $node.');
      return;
    }

    final text = node.text;
    final startText = text.copyText(0, splitPosition.offset);
    final endText = text.copyText(splitPosition.offset);
    editorDocLog.info('Splitting paragraph:');
    editorDocLog.info(' - start text: "${startText.text}"');
    editorDocLog.info(' - end text: "${endText.text}"');

    // Change the current nodes content to just the text before the caret.
    editorDocLog.info(' - changing the original paragraph text due to split');
    node.text = startText;

    // Create a new node that will follow the current node. Set its text
    // to the text that was removed from the current node. And create a
    // new copy of the metadata if `replicateExistingMetadata` is true.
    final newNode = ParagraphNode(
      id: newNodeId,
      text: endText,
      metadata: replicateExistingMetadata ? node.copyMetadata() : {},
    );

    // Insert the new node after the current node.
    editorDocLog.info(' - inserting new node in document');
    document.insertNodeAfter(
      existingNode: node,
      newNode: newNode,
    );

    editorDocLog.info(' - inserted new node: ${newNode.id} after old one: ${node.id}');

    // Move the caret to the new node.
    final composer = context.find<DocumentComposer>(DocumentEditor.composerKey);
    final oldSelection = composer.selectionComponent.selection;
    final newSelection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: newNodeId,
        nodePosition: const TextNodePosition(offset: 0),
      ),
    );
    composer.selectionComponent.updateSelection(newSelection);
    // composer.selectionComponent.setSelectionWithReason(
    //   newSelection,
    //   SelectionReason.userInteraction,
    // );

    final documentChanges = [
      NodeChangeEvent(node.id),
      NodeInsertedEvent(newNodeId),
      SelectionChangeEvent(
        oldSelection: oldSelection,
        newSelection: newSelection,
        changeType: SelectionChangeType.insertContent,
        reason: SelectionReason.userInteraction,
      ),
    ];

    if (newNode.text.text.isEmpty) {
      executor.logChanges([
        SubmitParagraphIntention.start(),
        ...documentChanges,
        SubmitParagraphIntention.end(),
      ]);
    } else {
      executor.logChanges([
        SplitParagraphIntention.start(),
        ...documentChanges,
        SplitParagraphIntention.end(),
      ]);
    }
  }
}

class Intention implements EditEvent {
  Intention.start() : _isStart = true;

  Intention.end() : _isStart = false;

  final bool _isStart;

  bool get isStart => _isStart;

  bool get isEnd => !_isStart;
}

class SplitParagraphIntention extends Intention {
  SplitParagraphIntention.start() : super.start();

  SplitParagraphIntention.end() : super.end();
}

class SubmitParagraphIntention extends Intention {
  SubmitParagraphIntention.start() : super.start();

  SubmitParagraphIntention.end() : super.end();
}

ExecutionInstruction anyCharacterToInsertInParagraph({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (editContext.composer.selectionComponent.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  // Do nothing if CMD or CTRL are pressed because this signifies an attempted
  // shortcut.
  if (keyEvent.isControlPressed || keyEvent.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  var character = keyEvent.character;
  if (character == null || character == '') {
    return ExecutionInstruction.continueExecution;
  }

  if (LogicalKeyboardKey.isControlCharacter(keyEvent.character!) || keyEvent.isArrowKeyPressed) {
    return ExecutionInstruction.continueExecution;
  }

  // On web, keys like shift and alt are sending their full name
  // as a character, e.g., "Shift" and "Alt". This check prevents
  // those keys from inserting their name into content.
  if (isKeyEventCharacterBlacklisted(character) && character != 'Tab') {
    return ExecutionInstruction.continueExecution;
  }

  // The web reports a tab as "Tab". Intercept it and translate it to a space.
  if (character == 'Tab') {
    character = ' ';
  }

  final didInsertCharacter = editContext.commonOps.insertCharacter(character);

  return didInsertCharacter ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

class DeleteParagraphCommand implements EditCommand {
  DeleteParagraphCommand({
    required this.nodeId,
  });

  final String nodeId;

  @override
  void execute(EditorContext context, CommandExecutor executor) {
    editorDocLog.info('Executing DeleteParagraphCommand');
    editorDocLog.info(' - deleting "$nodeId"');
    final document = context.find<MutableDocument>(DocumentEditor.documentKey);
    final node = document.getNodeById(nodeId);
    if (node is! TextNode) {
      editorDocLog.shout('WARNING: Cannot delete node of type: $node.');
      return;
    }

    bool didRemove = document.deleteNode(node);
    if (!didRemove) {
      editorDocLog.shout('ERROR: Failed to delete node "$node" from the document.');
    }

    executor.logChanges([NodeRemovedEvent(node.id)]);
  }
}

/// When the caret is collapsed at the beginning of a ParagraphNode
/// and backspace is pressed, clear any existing block type, e.g.,
/// header 1, header 2, blockquote.
ExecutionInstruction backspaceToClearParagraphBlockType({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selectionComponent.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (!editContext.composer.selectionComponent.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final node =
      editContext.editor.document.getNodeById(editContext.composer.selectionComponent.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }

  final textPosition = editContext.composer.selectionComponent.selection!.extent.nodePosition;
  if (textPosition is! TextNodePosition || textPosition.offset > 0) {
    return ExecutionInstruction.continueExecution;
  }

  final didClearBlockType = editContext.commonOps.convertToParagraph();
  return didClearBlockType ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction enterToInsertBlockNewline({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.enter && keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }

  final didInsertBlockNewline = editContext.commonOps.insertBlockLevelNewline();

  return didInsertBlockNewline ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction moveParagraphSelectionUpWhenBackspaceIsPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selectionComponent.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!editContext.composer.selectionComponent.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final node =
      editContext.editor.document.getNodeById(editContext.composer.selectionComponent.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }

  if (node.text.text.isEmpty) {
    return ExecutionInstruction.continueExecution;
  }

  final nodeAbove = editContext.editor.document.getNodeBefore(node);
  if (nodeAbove == null) {
    return ExecutionInstruction.continueExecution;
  }
  final newDocumentPosition = DocumentPosition(
    nodeId: nodeAbove.id,
    nodePosition: nodeAbove.endPosition,
  );

  editContext.composer.selectionComponent.updateSelection(
      DocumentSelection.collapsed(
        position: newDocumentPosition,
      ),
      notifyListeners: true);

  return ExecutionInstruction.haltExecution;
}

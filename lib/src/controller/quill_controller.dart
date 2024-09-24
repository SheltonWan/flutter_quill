import 'dart:math' as math;

import 'package:flutter/services.dart' show ClipboardData, Clipboard;
import 'package:flutter/widgets.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart' show experimental;

import '../../quill_delta.dart';
import '../common/structs/image_url.dart';
import '../common/structs/offset_value.dart';
import '../common/utils/embeds.dart';
import '../delta/delta_diff.dart';
import '../delta/delta_x.dart';
import '../document/attribute.dart';
import '../document/document.dart';
import '../document/nodes/embeddable.dart';
import '../document/nodes/leaf.dart';
import '../document/structs/doc_change.dart';
import '../document/style.dart';
import '../editor/config/editor_configurations.dart';
import '../editor_toolbar_controller_shared/clipboard/clipboard_service_provider.dart';
import 'quill_controller_configurations.dart';

typedef ReplaceTextCallback = bool Function(int index, int len, Object? data);
typedef DeleteCallback = void Function(int cursorPosition, bool forward);

class QuillController extends ChangeNotifier {
  QuillController({
    required Document document,
    required TextSelection selection,
    this.configurations = const QuillControllerConfigurations(),
    this.keepStyleOnNewLine = true,
    this.onReplaceText,
    this.onDelete,
    this.onSelectionCompleted,
    this.onSelectionChanged,
    this.readOnly = false,
    this.editorFocusNode,
  })  : _document = document,
        _selection = selection;

  factory QuillController.basic(
          {QuillControllerConfigurations configurations =
              const QuillControllerConfigurations(),
          FocusNode? editorFocusNode}) =>
      QuillController(
        configurations: configurations,
        editorFocusNode: editorFocusNode,
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );

  final QuillControllerConfigurations configurations;

  /// Local copy of editor configurations enables fail-safe setting from editor _initState method
  QuillEditorConfigurations? _editorConfigurations;
  QuillEditorConfigurations? get editorConfigurations =>
      configurations.editorConfigurations ?? _editorConfigurations;
  set editorConfigurations(QuillEditorConfigurations? value) =>
      _editorConfigurations = value;

  /// Document managed by this controller.
  Document _document;

  Document get document => _document;

  set document(Document doc) {
    _document = doc;

    // Prevent the selection from
    _selection = const TextSelection(baseOffset: 0, extentOffset: 0);

    notifyListeners();
  }

  @experimental
  void setContents(
    Delta delta, {
    ChangeSource changeSource = ChangeSource.local,
  }) {
    final newDocument = Document.fromDelta(delta);

    final change = DocChange(_document.toDelta(), delta, changeSource);
    newDocument.documentChangeObserver.add(change);
    newDocument.history.handleDocChange(change);

    _document = newDocument;
    notifyListeners();
  }

  /// Tells whether to keep or reset the [toggledStyle]
  /// when user adds a new line.
  final bool keepStyleOnNewLine;

  /// Currently selected text within the [document].
  TextSelection get selection => _selection;
  TextSelection _selection;

  /// Custom [replaceText] handler
  /// Return false to ignore the event
  ReplaceTextCallback? onReplaceText;

  /// Custom delete handler
  DeleteCallback? onDelete;

  void Function()? onSelectionCompleted;
  void Function(TextSelection textSelection)? onSelectionChanged;

  /// Store any styles attribute that got toggled by the tap of a button
  /// and that has not been applied yet.
  /// It gets reset after each format action within the [document].
  Style toggledStyle = const Style();

  bool ignoreFocusOnTextChange = false;

  /// Skip requestKeyboard being called in
  /// RawEditorState#_didChangeTextEditingValue
  bool skipRequestKeyboard = false;

  /// True when this [QuillController] instance has been disposed.
  ///
  /// A safety mechanism to ensure that listeners don't crash when adding,
  /// removing or listeners to this instance.
  bool _isDisposed = false;

  Stream<DocChange> get changes => document.changes;

  TextEditingValue get plainTextEditingValue => TextEditingValue(
        text: document.toPlainText(),
        selection: selection,
      );

  /// Only attributes applied to all characters within this range are
  /// included in the result.
  Style getSelectionStyle() {
    return document
        .collectStyle(selection.start, selection.end - selection.start)
        .mergeAll(toggledStyle);
  }

  // Increases or decreases the indent of the current selection by 1.
  void indentSelection(bool isIncrease) {
    if (selection.isCollapsed) {
      _indentSelectionFormat(isIncrease);
    } else {
      _indentSelectionEachLine(isIncrease);
    }
  }

  void _indentSelectionFormat(bool isIncrease) {
    final indent = getSelectionStyle().attributes[Attribute.indent.key];
    if (indent == null) {
      if (isIncrease) {
        formatSelection(Attribute.indentL1);
      }
      return;
    }
    if (indent.value == 1 && !isIncrease) {
      formatSelection(Attribute.clone(Attribute.indentL1, null));
      return;
    }
    if (isIncrease) {
      if (indent.value < 5) {
        formatSelection(Attribute.getIndentLevel(indent.value + 1));
      }
      return;
    }
    formatSelection(Attribute.getIndentLevel(indent.value - 1));
  }

  void _indentSelectionEachLine(bool isIncrease) {
    final styles = document.collectAllStylesWithOffset(
      selection.start,
      selection.end - selection.start,
    );
    for (final style in styles) {
      final indent = style.value.attributes[Attribute.indent.key];
      final formatIndex = math.max(style.offset, selection.start);
      final formatLength = math.min(
            style.offset + (style.length ?? 0),
            selection.end,
          ) -
          style.offset;
      Attribute? formatAttribute;
      if (indent == null) {
        if (isIncrease) {
          formatAttribute = Attribute.indentL1;
        }
      } else if (indent.value == 1 && !isIncrease) {
        formatAttribute = Attribute.clone(Attribute.indentL1, null);
      } else if (isIncrease) {
        if (indent.value < 5) {
          formatAttribute = Attribute.getIndentLevel(indent.value + 1);
        }
      } else {
        formatAttribute = Attribute.getIndentLevel(indent.value - 1);
      }
      if (formatAttribute != null) {
        document.format(formatIndex, formatLength, formatAttribute);
      }
    }
    notifyListeners();
  }

  /// Returns all styles and Embed for each node within selection
  List<OffsetValue> getAllIndividualSelectionStylesAndEmbed() {
    final stylesAndEmbed = document.collectAllIndividualStyleAndEmbed(
        selection.start, selection.end - selection.start);
    return stylesAndEmbed;
  }

  /// Returns plain text for each node within selection
  String getPlainText() {
    final text =
        document.getPlainText(selection.start, selection.end - selection.start);
    return text;
  }

  /// Returns all styles for any character within the specified text range.
  List<Style> getAllSelectionStyles() {
    final styles = document.collectAllStyles(
        selection.start, selection.end - selection.start)
      ..add(toggledStyle);
    return styles;
  }

  void undo() {
    final result = document.undo();
    if (result.changed) {
      _handleHistoryChange(result.len);
    }
  }

  void _handleHistoryChange(int len) {
    updateSelection(
      TextSelection.collapsed(
        offset: len,
      ),
      ChangeSource.local,
    );
  }

  void redo() {
    final result = document.redo();
    if (result.changed) {
      _handleHistoryChange(result.len);
    }
  }

  bool get hasUndo => document.hasUndo;

  bool get hasRedo => document.hasRedo;

  /// clear editor
  void clear() {
    replaceText(0, plainTextEditingValue.text.length - 1, '',
        const TextSelection.collapsed(offset: 0));
  }

  void replaceText(
    int index,
    int len,
    Object? data,
    TextSelection? textSelection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    assert(data is String || data is Embeddable || data is Delta);

    if (onReplaceText != null && !onReplaceText!(index, len, data)) {
      return;
    }

    Delta? delta;
    if (len > 0 || data is! String || data.isNotEmpty) {
      delta = document.replace(index, len, data);
      var shouldRetainDelta = toggledStyle.isNotEmpty &&
          delta.isNotEmpty &&
          delta.length <= 2 &&
          delta.last.isInsert;
      if (shouldRetainDelta &&
          toggledStyle.isNotEmpty &&
          delta.length == 2 &&
          delta.last.data == '\n') {
        // if all attributes are inline, shouldRetainDelta should be false
        final anyAttributeNotInline =
            toggledStyle.values.any((attr) => !attr.isInline);
        if (!anyAttributeNotInline) {
          shouldRetainDelta = false;
        }
      }
      if (shouldRetainDelta) {
        final retainDelta = Delta()
          ..retain(index)
          ..retain(data is String ? data.length : 1, toggledStyle.toJson());
        document.compose(retainDelta, ChangeSource.local);
      }
    }

    if (textSelection != null) {
      if (delta == null || delta.isEmpty) {
        _updateSelection(textSelection);
      } else {
        final user = Delta()
          ..retain(index)
          ..insert(data)
          ..delete(len);
        final positionDelta = getPositionDelta(user, delta);
        _updateSelection(
            textSelection.copyWith(
              baseOffset: textSelection.baseOffset + positionDelta,
              extentOffset: textSelection.extentOffset + positionDelta,
            ),
            insertNewline: data == '\n');
      }
    }

    if (ignoreFocus) {
      ignoreFocusOnTextChange = true;
    }
    if (shouldNotifyListeners) {
      notifyListeners();
    }
    ignoreFocusOnTextChange = false;
  }

  /// Called in two cases:
  /// forward == false && textBefore.isEmpty
  /// forward == true && textAfter.isEmpty
  /// Android only
  /// see https://github.com/singerdmx/flutter-quill/discussions/514
  void handleDelete(int cursorPosition, bool forward) =>
      onDelete?.call(cursorPosition, forward);

  void formatTextStyle(int index, int len, Style style) {
    style.attributes.forEach((key, attr) {
      formatText(index, len, attr);
    });
  }

  void formatText(
    int index,
    int len,
    Attribute? attribute, {
    bool shouldNotifyListeners = true,
  }) {
    if (len == 0 &&
        attribute!.isInline &&
        attribute.key != Attribute.link.key) {
      // Add the attribute to our toggledStyle.
      // It will be used later upon insertion.
      toggledStyle = toggledStyle.put(attribute);
    }

    final change = document.format(index, len, attribute);
    // Transform selection against the composed change and give priority to
    // the change. This is needed in cases when format operation actually
    // inserts data into the document (e.g. embeds).
    final adjustedSelection = selection.copyWith(
        baseOffset: change.transformPosition(selection.baseOffset),
        extentOffset: change.transformPosition(selection.extentOffset));
    if (selection != adjustedSelection) {
      _updateSelection(adjustedSelection);
    }
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  void formatSelection(Attribute? attribute,
      {bool shouldNotifyListeners = true}) {
    formatText(
      selection.start,
      selection.end - selection.start,
      attribute,
      shouldNotifyListeners: shouldNotifyListeners,
    );
  }

  void moveCursorToStart() {
    updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
  }

  void moveCursorToPosition(int position) {
    updateSelection(
      TextSelection.collapsed(offset: position),
      ChangeSource.local,
    );
  }

  void moveCursorToEnd() {
    updateSelection(
      TextSelection.collapsed(offset: plainTextEditingValue.text.length),
      ChangeSource.local,
    );
  }

  void updateSelection(TextSelection textSelection, ChangeSource source) {
    _updateSelection(textSelection);
    notifyListeners();
  }

  void compose(Delta delta, TextSelection textSelection, ChangeSource source) {
    if (delta.isNotEmpty) {
      document.compose(delta, source);
    }

    textSelection = selection.copyWith(
      baseOffset: delta.transformPosition(selection.baseOffset, force: false),
      extentOffset: delta.transformPosition(
        selection.extentOffset,
        force: false,
      ),
    );
    if (selection != textSelection) {
      _updateSelection(textSelection);
    }

    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    // By using `_isDisposed`, make sure that `addListener` won't be called on a
    // disposed `ChangeListener`
    if (!_isDisposed) {
      super.addListener(listener);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    // By using `_isDisposed`, make sure that `removeListener` won't be called
    // on a disposed `ChangeListener`
    if (!_isDisposed) {
      super.removeListener(listener);
    }
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      document.close();
    }

    _isDisposed = true;
    super.dispose();
  }

  void _updateSelection(TextSelection textSelection,
      {bool insertNewline = false}) {
    _selection = textSelection;
    final end = document.length - 1;
    _selection = selection.copyWith(
        baseOffset: math.min(selection.baseOffset, end),
        extentOffset: math.min(selection.extentOffset, end));
    if (keepStyleOnNewLine) {
      if (insertNewline && selection.start > 0) {
        final style = document.collectStyle(selection.start - 1, 0);
        final ignoredStyles = style.attributes.values.where(
          (s) => !s.isInline || s.key == Attribute.link.key,
        );
        toggledStyle = style.removeAll(ignoredStyles.toSet());
      } else {
        toggledStyle = const Style();
      }
    } else {
      toggledStyle = const Style();
    }
    onSelectionChanged?.call(textSelection);
  }

  /// Given offset, find its leaf node in document
  Leaf? queryNode(int offset) {
    return document.querySegmentLeafNode(offset).leaf;
  }

  // Notify toolbar buttons directly with attributes
  Map<String, Attribute> toolbarButtonToggler = const {};

  /// Clipboard caches last copy to allow paste with styles. Static to allow paste between multiple instances of editor.
  static String _pastePlainText = '';
  static Delta _pasteDelta = Delta();
  static List<OffsetValue> _pasteStyleAndEmbed = <OffsetValue>[];

  String get pastePlainText => _pastePlainText;
  Delta get pasteDelta => _pasteDelta;
  List<OffsetValue> get pasteStyleAndEmbed => _pasteStyleAndEmbed;

  bool readOnly;

  /// Used to give focus to the editor following a toolbar action
  FocusNode? editorFocusNode;

  ImageUrl? _copiedImageUrl;
  ImageUrl? get copiedImageUrl => _copiedImageUrl;

  set copiedImageUrl(ImageUrl? value) {
    _copiedImageUrl = value;
    Clipboard.setData(const ClipboardData(text: ''));
  }

  bool clipboardSelection(bool copy) {
    copiedImageUrl = null;

    /// Get the text for the selected region and expand the content of Embedded objects.
    _pastePlainText = document.getPlainText(
        selection.start, selection.end - selection.start, editorConfigurations);

    /// Get the internal representation so it can be pasted into a QuillEditor with style retained.
    _pasteStyleAndEmbed = getAllIndividualSelectionStylesAndEmbed();

    /// Get the deltas for the selection so they can be pasted into a QuillEditor with styles and embeds retained.
    _pasteDelta = document.toDelta().slice(selection.start, selection.end);

    if (!selection.isCollapsed) {
      Clipboard.setData(ClipboardData(text: _pastePlainText));
      if (!copy) {
        if (readOnly) return false;
        final sel = selection;
        replaceText(sel.start, sel.end - sel.start, '',
            TextSelection.collapsed(offset: sel.start));
      }
      return true;
    }
    return false;
  }

  /// Returns whether paste operation was handled here.
  /// updateEditor is called if paste operation was successful.
  Future<bool> clipboardPaste({void Function()? updateEditor}) async {
    if (readOnly || !selection.isValid) return true;

    final pasteUsingInternalImageSuccess = await _pasteInternalImage();
    if (pasteUsingInternalImageSuccess) {
      updateEditor?.call();
      return true;
    }

    final pasteUsingHtmlSuccess = await _pasteHTML();
    if (pasteUsingHtmlSuccess) {
      updateEditor?.call();
      return true;
    }

    final pasteUsingMarkdownSuccess = await _pasteMarkdown();
    if (pasteUsingMarkdownSuccess) {
      updateEditor?.call();
      return true;
    }

    // Snapshot the input before using `await`.
    // See https://github.com/flutter/flutter/issues/11427
    final plainTextClipboardData =
        await Clipboard.getData(Clipboard.kTextPlain);
    if (pasteUsingPlainOrDelta(plainTextClipboardData?.text)) {
      updateEditor?.call();
      return true;
    }

    if (await configurations.onClipboardPaste?.call() == true) {
      updateEditor?.call();
      return true;
    }

    return false;
  }

  /// Internal method to allow unit testing
  bool pasteUsingPlainOrDelta(String? clipboardText) {
    if (clipboardText != null) {
      final mapData = _removeBacktick(clipboardText);
      final mapData2 = _remove3SharpChar(mapData['text'] as String);
      final mapData3 = _removeCodeflag(mapData2['text'] as String);
      final String? newClipboardText = mapData3['text'];

      /// Internal copy-paste preserves styles and embeds
      if (newClipboardText == _pastePlainText &&
          _pastePlainText.isNotEmpty &&
          _pasteDelta.isNotEmpty) {
        replaceText(selection.start, selection.end - selection.start,
            _pasteDelta, TextSelection.collapsed(offset: selection.end));
      } else {
        replaceText(
            selection.start,
            selection.end - selection.start,
            newClipboardText,
            TextSelection.collapsed(
                offset: selection.end + newClipboardText!.length));
      }

      final List lines = mapData2['lines'];
      final List codes = mapData3['codes'];
      // final List words = mapData['words'];

      // const hex = '#FFE0F2F1';
      // for (final emap in words) {
      //   final index = emap['index'] as int;
      //   final cnum = _numberBefore(index, codes);
      //   final lnum = _numberBefore(index, lines);
      //   formatText(index-cnum*4-lnum*4, emap['length'], const BackgroundAttribute(hex),
      //       shouldNotifyListeners: true);
      // }

      for (final emap in lines) {
        final index = emap['index'] as int;
        final num = _numberBefore(index, codes);
        formatText(index-num*4, emap['length'], const BoldAttribute(),
            shouldNotifyListeners: true);
      }

      
      for (final emap in codes) {
        formatText(
            emap['index'] as int, emap['length'], const CodeBlockAttribute(),
            shouldNotifyListeners: true);
      }
      return true;
    }
    return false;
  }

  int _numberBefore(int startIndex, List codes) {
    var num = 0;
    for (final emap in codes) {
      final index = emap['index'] as int;
      if (index > startIndex) break;
      num++;
    }
    return num;
  }

  Map<String, dynamic> _removeBacktick(String text) {
    // String text = "这是一个`包含`反引号的`字符串`和`多个词汇`。";

    // 用正则表达式匹配反引号包裹的词汇
    final exp = RegExp(r'`(.*?)`');
    final wordsInfo = [];
    final newText = StringBuffer(); // 用来构建新的字符串
    var lastIndex = 0;

    // 遍历所有匹配项
    for (final match in exp.allMatches(text)) {
      // 将匹配前的部分加到新字符串
      newText.write(text.substring(lastIndex, match.start));

      // 提取反引号包裹的实际词汇（去掉反引号）
      final word = match.group(1)!;

      // 记录实际词汇的索引（新文本中的索引）和长度
      wordsInfo.add({
        'index': newText.length, // 新文本中的实际索引
        'length': word.length, // 实际词汇的长度
      });

      // 将去掉反引号的词汇加入新字符串
      newText.write(word);

      // 更新 lastIndex 以继续处理剩余部分
      lastIndex = match.end;
    }

    // 添加最后剩余的部分
    newText.write(text.substring(lastIndex));

    // 输出剔除反引号后的新字符串
    final finalText = newText.toString();
    return {'text': finalText, 'words': wordsInfo};
  }

  Map<String, dynamic> _remove3SharpChar(String text) {
    // 分割成多行
    final lines = text.split('\n');
    final linesInfo = [];
    final newText = StringBuffer(); // 用来构建新的字符串
    var currentIndex = 0;

    // 遍历每一行
    for (final line in lines) {
      if (line.startsWith('###')) {
        // 剔除开头的 ###
        final modifiedLine = line.substring(3).trimLeft(); // 去掉 ### 并去掉多余的空格

        // 记录该行的新索引和长度
        linesInfo.add({
          'index': currentIndex, // 当前新字符串中的索引
          'length': modifiedLine.length, // 修改后行的长度
        });

        // 将修改后的行加入新的字符串
        newText.write(modifiedLine);
      } else {
        // 保持原样加入未以 ### 开头的行
        newText.write(line);
      }

      // 添加换行符
      newText.write('\n');

      // 更新 currentIndex 为下一行的起始索引
      currentIndex = newText.length;
    }

    // 剔除末尾多余的换行符
    final finalText = newText.toString().trimRight();
    return {'text': finalText, 'lines': linesInfo};
  }

  Map<String, dynamic> _removeCodeflag(String text) {
    // 正则表达式匹配以空白行+`开头，`+空白行结束的代码块
    final exp = RegExp(r'(?<=\n)\s*`([\s\S]*?)`\s*(?=\n)');
    final codeInfo = [];
    final newText = StringBuffer();
    var lastIndex = 0;

    // 遍历所有匹配的代码片段
    for (final match in exp.allMatches(text)) {
      // 将非代码部分写入新的字符串
      newText.write(text.substring(lastIndex, match.start));

      // 提取代码片段并去除反引号
      final code = match.group(1)!;

      // 记录代码片段在新字符串中的索引和长度
      codeInfo.add({
        'index': newText.length, // 新字符串中的起始索引
        'length': code.length, // 代码片段的长度
      });

      // 将代码片段写入新的字符串
      newText.write(code);

      // 更新 lastIndex 为下一个位置
      lastIndex = match.end;
    }

    // 将最后剩余的文本加到新字符串中
    newText.write(text.substring(lastIndex));

    // 输出剔除反引号后的新字符串
    final finalText = newText.toString();
    return {'text': finalText, 'codes': codeInfo};
  }

  void _pasteUsingDelta(Delta deltaFromClipboard) {
    replaceText(
      selection.start,
      selection.end - selection.start,
      deltaFromClipboard,
      TextSelection.collapsed(offset: selection.end),
    );
  }

  /// Return true if can paste internal image
  Future<bool> _pasteInternalImage() async {
    final copiedImageUrl = _copiedImageUrl;
    if (copiedImageUrl != null) {
      final index = selection.baseOffset;
      final length = selection.extentOffset - index;
      replaceText(
        index,
        length,
        BlockEmbed.image(copiedImageUrl.url),
        null,
      );
      if (copiedImageUrl.styleString.isNotEmpty) {
        formatText(
          getEmbedNode(this, index + 1).offset,
          1,
          StyleAttribute(copiedImageUrl.styleString),
        );
      }
      _copiedImageUrl = null;
      await Clipboard.setData(
        const ClipboardData(text: ''),
      );
      return true;
    }
    return false;
  }

  /// Return true if can paste using HTML
  Future<bool> _pasteHTML() async {
    final clipboardService = ClipboardServiceProvider.instance;

    Future<String?> getHTML() async {
      if (await clipboardService.canProvideHtmlTextFromFile()) {
        return await clipboardService.getHtmlTextFromFile();
      }
      if (await clipboardService.canProvideHtmlText()) {
        return await clipboardService.getHtmlText();
      }
      return null;
    }

    final htmlText = await getHTML();
    if (htmlText != null) {
      final htmlBody = html_parser.parse(htmlText).body?.outerHtml;
      // ignore: deprecated_member_use_from_same_package
      final deltaFromClipboard = DeltaX.fromHtml(htmlBody ?? htmlText);

      _pasteUsingDelta(deltaFromClipboard);

      return true;
    }
    return false;
  }

  /// Return true if can paste using Markdown
  Future<bool> _pasteMarkdown() async {
    final clipboardService = ClipboardServiceProvider.instance;

    Future<String?> getMarkdown() async {
      if (await clipboardService.canProvideMarkdownTextFromFile()) {
        return await clipboardService.getMarkdownTextFromFile();
      }
      if (await clipboardService.canProvideMarkdownText()) {
        return await clipboardService.getMarkdownText();
      }
      return null;
    }

    final markdownText = await getMarkdown();
    if (markdownText != null) {
      // ignore: deprecated_member_use_from_same_package
      final deltaFromClipboard = DeltaX.fromMarkdown(markdownText);

      _pasteUsingDelta(deltaFromClipboard);

      return true;
    }
    return false;
  }

  void replaceTextWithEmbeds(
    int index,
    int len,
    String insertedText,
    TextSelection? textSelection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    final containsEmbed =
        insertedText.codeUnits.contains(Embed.kObjectReplacementInt);
    insertedText =
        containsEmbed ? _adjustInsertedText(insertedText) : insertedText;

    replaceText(index, len, insertedText, textSelection,
        ignoreFocus: ignoreFocus, shouldNotifyListeners: shouldNotifyListeners);

    _applyPasteStyleAndEmbed(insertedText, index, containsEmbed);
  }

  void _applyPasteStyleAndEmbed(
      String insertedText, int start, bool containsEmbed) {
    if (insertedText == pastePlainText && pastePlainText != '' ||
        containsEmbed) {
      final pos = start;
      for (final p in pasteStyleAndEmbed) {
        final offset = p.offset;
        final styleAndEmbed = p.value;

        final local = pos + offset;
        if (styleAndEmbed is Embeddable) {
          replaceText(local, 0, styleAndEmbed, null);
        } else {
          final style = styleAndEmbed as Style;
          if (style.isInline) {
            formatTextStyle(local, p.length!, style);
          } else if (style.isBlock) {
            final node = document.queryChild(local).node;
            if (node != null && p.length == node.length - 1) {
              for (final attribute in style.values) {
                document.format(local, 0, attribute);
              }
            }
          }
        }
      }
    }
  }

  String _adjustInsertedText(String text) {
    final sb = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == Embed.kObjectReplacementInt) {
        continue;
      }
      sb.write(text[i]);
    }
    return sb.toString();
  }
}

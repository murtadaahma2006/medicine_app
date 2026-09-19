import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../theme/tokens.dart';

// ─────────────────────────────────────────────────────────────────────
// Sidekick — لوحة دردشة AI سياقية مرتبطة بالشرح الحالي.
//
// تُعرض جانبياً (landscape) أو كقائمة سفلية (portrait) داخل
// ConceptReaderPage. الجلسة مؤقتة (in-memory) — تُمسح عند
// مغادرة الشرح.
// ─────────────────────────────────────────────────────────────────────

/// رسالة دردشة واحدة.
class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.text,
    this.quotedText,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String role; // 'user' | 'assistant'
  String text;
  final String? quotedText;
  final DateTime timestamp;

  bool get isUser => role == 'user';
}

/// ─────────────────────────────────────────────────────────────────────
/// أفاتار الـ AI المشترك — تدرج بنفسجي مع أيقونة auto_awesome.
/// ─────────────────────────────────────────────────────────────────────
const _kAiAvatar = SizedBox(
  width: 28,
  height: 28,
  child: DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Icon(Icons.auto_awesome, color: Colors.white, size: 14),
  ),
);

/// ─────────────────────────────────────────────────────────────────────
/// [SidekickChatPanel] — لوحة الدردشة السياقية الكاملة.
///
/// تُستخدم كابن مباشر داخل `Row` (landscape) أو داخل
/// `showModalBottomSheet` (portrait).
/// ─────────────────────────────────────────────────────────────────────
class SidekickChatPanel extends StatefulWidget {
  const SidekickChatPanel({
    required this.unitId,
    required this.unitTitle,
    this.onClose,
    this.scrollController,
    super.key,
  });

  /// معرّف المحاضرة — يُعيّن هوية الجلسة.
  final String unitId;

  /// عنوان المحاضرة — يُدرج في system prompt لسياق أدق.
  final String unitTitle;

  /// إغلاق اللوحة (يستدعيه الزر × أو الشيت).
  final VoidCallback? onClose;

  /// تحكم بالتمرير من الخارج (DraggableScrollableSheet في portrait).
  final ScrollController? scrollController;

  @override
  State<SidekickChatPanel> createState() => SidekickChatPanelState();
}

class SidekickChatPanelState extends State<SidekickChatPanel> {
  final TextEditingController _controller = TextEditingController();
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  final List<_ChatMessage> _messages = <_ChatMessage>[];

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant SidekickChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId) {
      _messages.clear();
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    _isLoading.value = true;
    try {
      final List<Map<String, dynamic>> history = await DatabaseHelper.instance.getLectureChatHistory(widget.unitId);
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(history.map((Map<String, dynamic> row) {
            return _ChatMessage(
              role: row['role'] as String,
              text: row['content'] as String,
              quotedText: row['quoted_text'] as String?,
              timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
            );
          }));
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Failed to load Sidekick history: $e');
    } finally {
      if (mounted) _isLoading.value = false;
    }
  }

  // ── API العام ────────────────────────────────────────────────

  /// Public method to instantly inject text as a visual blockquote and trigger the AI.
  Future<void> injectAndExplain(String highlightedText) async {
    final String text = 'الرجاء شرح هذا النص الطبي:';
    
    // Step A: Instant UI Update
    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text, quotedText: highlightedText));
    });
    
    // Step D: Scroll
    _scrollToBottom();
    
    // Step B: Background Save (fire and forget without blocking UI)
    await DatabaseHelper.instance.insertLectureChatMessage(
      widget.unitId, 
      'user', 
      text, 
      quotedText: highlightedText,
    );
    
    // Step C: Auto-Trigger AI
    await _fetchAIResponse();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.scrollController == null) _scrollController.dispose();
    _isLoading.dispose();
    super.dispose();
  }

  // ── API العام ────────────────────────────────────────────────

  /// يُحقن رسالة مستخدم من الخارج (تحديد نص → شرح ذكي).
  void addUserMessage(String text, {String? quotedText}) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty && (quotedText == null || quotedText.trim().isEmpty)) return;
    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: trimmed, quotedText: quotedText));
    });
    DatabaseHelper.instance.insertLectureChatMessage(widget.unitId, 'user', trimmed, quotedText: quotedText);
    _scrollToBottom();
    _fetchAIResponse();
  }

  // ── المنطق ──────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _isLoading.value) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
    });
    await DatabaseHelper.instance.insertLectureChatMessage(widget.unitId, 'user', text);
    _scrollToBottom();
    await _fetchAIResponse();
  }

  Future<void> _fetchAIResponse() async {
    _isLoading.value = true;

    // بناء سياق المحادثة.
    final List<Map<String, dynamic>> apiMessages = <Map<String, dynamic>>[
      <String, dynamic>{
        'role': 'system',
        'content':
            'You are an expert AI study sidekick embedded inside a medical lecture reader. '
            'The student is currently studying: "${widget.unitTitle}". '
            'When they highlight text, explain it clearly. For follow-up questions, '
            'stay in context of this lecture. '
            'Respond primarily in Arabic, keeping English medical terms in English. '
            'Be concise (2-3 short paragraphs max). Use markdown for formatting.',
      },
    ];
    // آخر 20 رسالة.
    final int startIdx = _messages.length > 20 ? _messages.length - 20 : 0;
    for (int i = startIdx; i < _messages.length; i++) {
      final _ChatMessage msg = _messages[i];
      if (msg.text.isEmpty && msg.quotedText == null) continue;
      
      String payload = msg.text;
      if (msg.quotedText != null) {
        payload = '${msg.text}\n\n"${msg.quotedText}"';
      }
      
      apiMessages.add(<String, dynamic>{
        'role': msg.role,
        'content': payload,
      });
    }

    // placeholder لرد الـ AI.
    final int aiIdx = _messages.length;
    setState(() {
      _messages.add(_ChatMessage(role: 'assistant', text: ''));
    });

    String fullResponse = '';
    try {
      final Stream<String> stream =
          AIService.generateChatStream(apiMessages);

      await for (final String chunk in stream) {
        if (!mounted) return;
        fullResponse += chunk;
        setState(() {
          _messages[aiIdx].text = fullResponse;
        });
        if (_isLoading.value) _isLoading.value = false;
        _scrollToBottom();
      }

      if (!mounted) return;
      if (fullResponse.isEmpty) {
        setState(() => _messages.removeAt(aiIdx));
        _showError('عذراً، لم يتم استلام أي رد.');
      } else {
        await DatabaseHelper.instance.insertLectureChatMessage(widget.unitId, 'assistant', fullResponse);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeAt(aiIdx));
        _showError('تعذر الوصول للمزود، يرجى المحاولة لاحقاً.');
        debugPrint('Sidekick stream error: $e');
      }
    } finally {
      if (mounted && _isLoading.value) _isLoading.value = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
    );
  }

  Future<void> _clearChat() async {
    setState(() => _messages.clear());
    await DatabaseHelper.instance.clearLectureChatHistory(widget.unitId);
  }

  // ── البناء ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).colorScheme.brightness;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(
          left: BorderSide(color: AppColors.border(b), width: 1),
        ),
      ),
      child: Column(
        children: <Widget>[
          // ── الرأس ──
          _buildHeader(b, scheme),

          // ── قائمة الرسائل ──
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(b, scheme)
                : _buildMessageList(b, scheme),
          ),

          // ── مؤشر الكتابة ──
          ValueListenableBuilder<bool>(
            valueListenable: _isLoading,
            builder: (BuildContext context, bool loading, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: loading
                    ? _buildTypingIndicator(b, scheme)
                    : const SizedBox.shrink(),
              );
            },
          ),

          // ── حقل الإدخال ──
          _buildInputArea(b, scheme),
        ],
      ),
    );
  }

  Widget _buildHeader(Brightness b, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(
          bottom: BorderSide(color: AppColors.border(b), width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          // عنوان مع أيقونة
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF4A00E0), Color(0xFF8E2DE2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 14),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'المساعد السياقي',
              style: AppType.caption.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.text(b),
              ),
            ),
          ),
          // مسح المحادثة
          if (_messages.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  size: 18, color: AppColors.textSecondary(b)),
              tooltip: 'مسح المحادثة',
              onPressed: _clearChat,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
          // إغلاق
          if (widget.onClose != null)
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textSecondary(b)),
              tooltip: 'إغلاق',
              onPressed: widget.onClose,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Brightness b, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome,
                  size: 32, color: scheme.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'حدّد نصاً واختر «شرح ذكي»\nأو اكتب سؤالك هنا',
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary(b),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(Brightness b, ColorScheme scheme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      itemCount: _messages.length,
      itemBuilder: (BuildContext context, int index) =>
          _buildBubble(_messages[index], b, scheme),
    );
  }

  Widget _buildBubble(_ChatMessage msg, Brightness b, ColorScheme scheme) {
    if (msg.isUser) {
      if (msg.quotedText != null) {
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: scheme.primary, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: TextDirection.rtl,
              children: <Widget>[
                Icon(Icons.format_quote_rounded, color: scheme.primary, size: 20),
                const SizedBox(height: 4),
                Text(
                  msg.quotedText!,
                  style: AppType.body.copyWith(
                    color: AppColors.text(b).withValues(alpha: 0.85),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.6,
                  ),
                ),
                if (msg.text.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    msg.text,
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary(b),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: AppType.body.copyWith(
              color: Colors.white,
              fontSize: 13,
              height: 1.5,
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
          ),
        ),
      );
    }

    // ── رسالة AI ──
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: <Widget>[
          _kAiAvatar,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: MarkdownBody(
                      data: msg.text,
                      selectable: true,
                      fitContent: false,
                      styleSheet: _buildMarkdownSheet(scheme, b),
                    ),
                  ),
                  if (msg.text.isNotEmpty)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconButton(
                          icon: Icon(Icons.copy_rounded,
                              size: 14, color: scheme.onSurfaceVariant),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'نسخ',
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: msg.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('تم النسخ'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppRadius.chip),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(Brightness b, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: <Widget>[
          _kAiAvatar,
          const SizedBox(width: AppSpacing.sm),
          Text(
            'يكتب...',
            style: AppType.caption.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(Brightness b, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(b),
        border: Border(
          top: BorderSide(color: AppColors.border(b), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: _isLoading,
          builder: (BuildContext context, bool isLoading, _) {
            return Row(
              children: <Widget>[
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (BuildContext context, TextEditingValue value,
                        _) {
                      final bool canSend =
                          value.text.trim().isNotEmpty && !isLoading;
                      return TextField(
                        controller: _controller,
                        enabled: !isLoading,
                        minLines: 1,
                        maxLines: 3,
                        keyboardType: TextInputType.multiline,
                        textDirection: TextDirection.rtl,
                        style: AppType.body.copyWith(
                          fontSize: 13,
                          color: AppColors.text(b),
                        ),
                        decoration: InputDecoration(
                          hintText:
                              isLoading ? 'يرجى الانتظار...' : 'اسأل عن الشرح...',
                          hintStyle: AppType.caption.copyWith(
                            color: AppColors.textSecondary(b)
                                .withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: isLoading
                              ? scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5)
                              : scheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                          suffixIcon: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder:
                                  (Widget child, Animation<double> anim) =>
                                      ScaleTransition(
                                scale: anim,
                                child: FadeTransition(
                                  opacity: anim,
                                  child: child,
                                ),
                              ),
                              child: isLoading
                                  ? SizedBox(
                                      key: const ValueKey<String>(
                                          'loading'),
                                      width: 32,
                                      height: 32,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.all(6),
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    )
                                  : AnimatedContainer(
                                      key: const ValueKey<String>(
                                          'send'),
                                      duration: const Duration(
                                          milliseconds: 200),
                                      decoration: BoxDecoration(
                                        color: canSend
                                            ? scheme.primary
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.arrow_upward_rounded,
                                          color: canSend
                                              ? Colors.white
                                              : scheme.onSurfaceVariant
                                                  .withValues(
                                                      alpha: 0.4),
                                          size: 16,
                                        ),
                                        onPressed: canSend
                                            ? _sendMessage
                                            : null,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!isLoading) _sendMessage();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// MarkdownStyleSheet مصغّر للـ Sidekick — نفس فلسفة AiChatPage
  /// لكن بأحجام خط أصغر لتلائم اللوحة الضيقة.
  MarkdownStyleSheet _buildMarkdownSheet(
      ColorScheme scheme, Brightness b) {
    final Color bodyColor = scheme.onSurface;

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: AppType.body.copyWith(
        color: bodyColor,
        height: 1.6,
        fontSize: 13,
      ),
      pPadding: const EdgeInsets.only(bottom: 4),
      h1: AppType.cardTitle.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 17,
        height: 1.3,
      ),
      h2: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
        height: 1.3,
      ),
      h3: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 14,
        height: 1.3,
      ),
      strong: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        height: 1.6,
      ),
      em: AppType.body.copyWith(
        color: bodyColor,
        fontStyle: FontStyle.italic,
        fontSize: 13,
        height: 1.6,
      ),
      listBullet: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        height: 1.5,
      ),
      listIndent: 16,
      code: AppType.body.copyWith(
        backgroundColor: b == Brightness.dark
            ? scheme.surfaceContainerHighest
            : scheme.primary.withValues(alpha: 0.07),
        color: scheme.primary,
        fontFamily: 'monospace',
        fontSize: 12,
      ),
      codeblockDecoration: BoxDecoration(
        color: b == Brightness.dark
            ? const Color(0xFF1E2535)
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquote: AppType.body.copyWith(
        color: scheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
        fontSize: 12.5,
        height: 1.5,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: scheme.primary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
        color: scheme.primary.withValues(alpha: 0.05),
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      tableHead: AppType.body.copyWith(
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontSize: 12,
      ),
      tableBody: AppType.body.copyWith(
        color: bodyColor,
        fontSize: 12,
        height: 1.4,
      ),
      tableBorder: TableBorder.all(
        color: scheme.outlineVariant,
        width: 1,
        borderRadius: BorderRadius.circular(4),
      ),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

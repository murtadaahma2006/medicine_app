import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/models/ai_provider.dart';
import '../../../../core/services/ai_service.dart';
import '../../../../theme/tokens.dart';
import '../widgets/drug_reference_bottom_sheet.dart';

// ─────────────────────────────────────────────────────────────
// AI Avatar — shared constant widget, built once.
// ─────────────────────────────────────────────────────────────
const _kAiAvatar = SizedBox(
  width: 32,
  height: 32,
  child: DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
  ),
);

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);

  List<Map<String, dynamic>> _messages = [];
  File? _selectedImage;

  final List<AiProvider> _providers = <AiProvider>[
    AiProvider(
      id: 'default',
      name: 'Default Provider',
      baseUrl: '',
      apiKey: '',
      modelName: '',
      isDefault: true,
    ),
  ];
  late AiProvider _selectedProvider;
  static const String _providersKey = 'custom_ai_providers';

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selectedProvider = _providers.first;
    _loadHistory();
    _loadProviders();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  // ── Data & Logic ───────────────────────────────────────────

  Future<void> _loadHistory() async {
    final history = await DatabaseHelper.instance.getAiChatHistory();
    if (!mounted) return;
    setState(() {
      _messages = List<Map<String, dynamic>>.from(history);
    });
    _scrollToBottom();
  }

  Future<void> _loadProviders() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? providersJson = prefs.getString(_providersKey);
    if (providersJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(providersJson) as List<dynamic>;
        final List<AiProvider> loaded = decoded.map((dynamic e) => AiProvider.fromJson(e as Map<String, dynamic>)).toList();
        if (mounted) {
          setState(() {
            _providers.addAll(loaded);
          });
        }
      } catch (e) {
        debugPrint('Error loading providers: $e');
      }
    }
  }

  Future<void> _saveProvider(AiProvider provider) async {
    setState(() {
      _providers.add(provider);
      _selectedProvider = provider;
    });
    
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<AiProvider> customProviders = _providers.where((AiProvider p) => !p.isDefault).toList();
    final String encoded = jsonEncode(customProviders.map((AiProvider p) => p.toJson()).toList());
    await prefs.setString(_providersKey, encoded);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _sendMessage() async {
    final String text = _controller.text.trim();
    if ((text.isEmpty && _selectedImage == null) || _isLoadingNotifier.value) return;

    String? base64String;
    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      base64String = base64Encode(bytes);
    }

    // Optimistically add user message and set loading state.
    setState(() {
      _messages.add({
        'role': 'user',
        'message': text,
        if (base64String != null) 'base64Image': base64String,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      _controller.clear();
      _selectedImage = null;
    });
    _isLoadingNotifier.value = true;
    _scrollToBottom();

    // Persist user message — non-fatal if it fails.
    try {
      await DatabaseHelper.instance.insertAiChatMessage('user', text);
    } catch (e) {
      debugPrint('DB: failed to save user message — $e');
    }

    // Build conversation history for the API (last 20 messages).
    final List<Map<String, dynamic>> apiMessages = [
      {
        'role': 'system',
        'content':
            'You are a helpful and expert AI clinical assistant for a medical student. '
            'Answer concisely and accurately in Arabic, keeping medical terms in English.',
      },
    ];
    final int startIndex =
        _messages.length > 20 ? _messages.length - 20 : 0;
    for (int i = startIndex; i < _messages.length; i++) {
      final String content = _messages[i]['message'] as String;
      if (content.isEmpty && !_messages[i].containsKey('base64Image')) continue;
      
      apiMessages.add({
        'role': _messages[i]['role'] as String,
        'content': content,
        if (_messages[i].containsKey('base64Image')) 'base64Image': _messages[i]['base64Image'],
      });
    }

    // Placeholder for the AI's streaming response.
    final int aiMsgIndex = _messages.length;
    setState(() {
      _messages.add({
        'role': 'assistant',
        'message': '',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    });

    String fullResponse = '';
    try {
      final Stream<String> stream = AIService.generateChatStream(
        apiMessages,
        provider: _selectedProvider.isDefault ? null : _selectedProvider,
      );

      await for (final String chunk in stream) {
        if (!mounted) return;
        fullResponse += chunk;
        setState(() {
          _messages[aiMsgIndex]['message'] = fullResponse;
        });
        // Hide the typing indicator as soon as the first token arrives.
        if (_isLoadingNotifier.value) _isLoadingNotifier.value = false;
        _scrollToBottom();
      }

      if (!mounted) return;

      if (fullResponse.isEmpty) {
        // Stream completed but produced no output — clean up the placeholder.
        setState(() => _messages.removeAt(aiMsgIndex));
        _showErrorSnackBar('عذراً، لم يتم استلام أي رد من المزود.');
      } else {
        // Persist the complete AI response — non-fatal if it fails.
        try {
          await DatabaseHelper.instance
              .insertAiChatMessage('assistant', fullResponse);
        } catch (dbErr) {
          debugPrint('DB: failed to save assistant message — $dbErr');
        }
      }
    } catch (e) {
      // Network / provider error: remove the empty placeholder and inform user.
      if (mounted) {
        setState(() => _messages.removeAt(aiMsgIndex));
        _showErrorSnackBar('تعذر الوصول للمزود، يرجى المحاولة لاحقاً.');
        debugPrint('AI stream error: $e');
      }
    } finally {
      // ALWAYS release the loading lock — prevents infinite spinner.
      if (mounted && _isLoadingNotifier.value) _isLoadingNotifier.value = false;
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _clearChat() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح المحادثة'),
        content: const Text('هل أنت متأكد أنك تريد مسح جميع الرسائل؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.clearAiChatHistory();
      await _loadHistory();
    }
  }

  // ── UI Builders ────────────────────────────────────────────

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'كيف يمكنني مساعدتك في دراسة الطب اليوم؟',
              style: AppType.cardTitle.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(ColorScheme scheme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) =>
          _buildMessageBubble(_messages[index], scheme),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, ColorScheme scheme) {
    final bool isUser = msg['role'] == 'user';

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.80,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg['message'] as String,
            style: AppType.body.copyWith(color: Colors.white),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }

    // ── AI message ──
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: [
          _kAiAvatar,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarkdownBody(
                      data: msg['message'] as String,
                      selectable: true,
                      fitContent: false,
                      styleSheet: _buildMarkdownSheet(scheme),
                    ),
                    if ((msg['message'] as String).isNotEmpty)
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            color: scheme.onSurfaceVariant,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'نسخ',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text: msg['message'] as String));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('تم النسخ'),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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
          ),
        ],
      ),
    );
  }

  /// Returns the premium [MarkdownStyleSheet] for AI clinical responses.
  ///
  /// Design intent:
  ///  - RTL-first: relies on the [Directionality] wrapper in the bubble.
  ///  - Generous line-heights (1.6 body, 1.5 lists) for dense Arabic text.
  ///  - Primary-colored headings give clear visual hierarchy.
  ///  - Bold spans (strong) use primary color so medical terms pop.
  ///  - Soft, rounded code blocks for dosage/protocol snippets.
  MarkdownStyleSheet _buildMarkdownSheet(ColorScheme scheme) {
    final bool isDark = scheme.brightness == Brightness.dark;

    // Subtle tint for inline code — different from block code.
    final Color inlineCodeBg = isDark
        ? scheme.surfaceContainerHighest
        : scheme.primary.withValues(alpha: 0.07);

    // Block-code background — slightly darker/lighter than the bubble.
    final Color blockCodeBg = isDark
        ? const Color(0xFF1E2535)   // dark navy, easy on dark-mode eyes
        : const Color(0xFFF0F2F5);  // soft cool grey

    // Body text color — full contrast on the bubble surface.
    final Color bodyColor = scheme.onSurface;

    // Muted secondary text (captions, blockquotes).
    final Color mutedColor = scheme.onSurfaceVariant;

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      // ── Paragraphs ─────────────────────────────────────────────────────
      p: AppType.body.copyWith(
        color: bodyColor,
        height: 1.65,          // comfortable for Arabic script
        fontSize: 15,
      ),
      pPadding: const EdgeInsets.only(bottom: 6),

      // ── Headings ──────────────────────────────────────────────────────
      h1: AppType.screenTitle.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 22,
        height: 1.3,
      ),
      h1Padding: const EdgeInsets.only(top: 12, bottom: 6),

      h2: AppType.cardTitle.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
        height: 1.3,
      ),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),

      h3: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 16,
        height: 1.3,
      ),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 4),

      h4: AppType.body.copyWith(
        color: bodyColor,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),

      // ── Bold / Italic ─────────────────────────────────────────────────
      // Bold is used heavily for medical terms and clinical pearls.
      strong: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
        height: 1.65,
      ),
      em: AppType.body.copyWith(
        color: bodyColor,
        fontStyle: FontStyle.italic,
        fontSize: 15,
        height: 1.65,
      ),

      // ── Lists ─────────────────────────────────────────────────────────
      listBullet: AppType.body.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
        height: 1.55,
      ),
      listIndent: 20,
      listBulletPadding: const EdgeInsets.only(left: 4, right: 4),

      // ── Inline code ───────────────────────────────────────────────────
      code: AppType.body.copyWith(
        backgroundColor: inlineCodeBg,
        color: scheme.primary,
        fontFamily: 'monospace',
        fontSize: 13.5,
        height: 1.4,
      ),

      // ── Block code ────────────────────────────────────────────────────
      codeblockDecoration: BoxDecoration(
        color: blockCodeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      codeblockPadding: const EdgeInsets.all(14),

      // ── Blockquote ────────────────────────────────────────────────────
      blockquote: AppType.body.copyWith(
        color: mutedColor,
        fontStyle: FontStyle.italic,
        fontSize: 14.5,
        height: 1.55,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: scheme.primary.withValues(alpha: 0.5),
            width: 4,
          ),
        ),
        color: scheme.primary.withValues(alpha: 0.05),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),

      // ── Horizontal rule ───────────────────────────────────────────────
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant,
            width: 1,
          ),
        ),
      ),

      // ── Table ─────────────────────────────────────────────────────────
      tableHead: AppType.body.copyWith(
        fontWeight: FontWeight.w700,
        color: bodyColor,
        fontSize: 14,
      ),
      tableBody: AppType.body.copyWith(
        color: bodyColor,
        fontSize: 14,
        height: 1.5,
      ),
      tableBorder: TableBorder.all(
        color: scheme.outlineVariant,
        width: 1,
        borderRadius: BorderRadius.circular(6),
      ),
      tableHeadAlign: TextAlign.start,
      tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 6),
    );
  }

  Widget _buildTypingIndicator(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          _kAiAvatar,
          const SizedBox(width: AppSpacing.md),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              'المساعد يكتب...',
              style: AppType.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: _isLoadingNotifier,
          builder: (context, isLoading, _) {
            return Column(
          children: [
            if (_selectedImage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_selectedImage!, height: 80, width: 80, fit: BoxFit.cover),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _selectedImage = null),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    onPressed: isLoading ? null : _pickImage,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, child) {
                        final bool isTyping =
                            (value.text.trim().isNotEmpty || _selectedImage != null) && !isLoading;

                        return TextField(
                          controller: _controller,
                          enabled: !isLoading,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            hintText: isLoading ? 'يرجى الانتظار...' : 'اكتب رسالتك...',
                            hintStyle: AppType.body.copyWith(
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: isLoading
                                ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                                : scheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.memory_rounded, color: scheme.onSurfaceVariant, size: 20),
                                    tooltip: 'تبديل المزود',
                                    color: scheme.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                    ),
                                    onSelected: (String value) {
                                      if (value == 'ADD_NEW') {
                                        _showAddProviderDialog(scheme);
                                      } else {
                                        final provider = _providers.firstWhere((p) => p.id == value);
                                        setState(() {
                                          _selectedProvider = provider;
                                        });
                                      }
                                    },
                                    itemBuilder: (BuildContext context) {
                                      final List<PopupMenuEntry<String>> items = [];
                                      for (final AiProvider provider in _providers) {
                                        items.add(
                                          PopupMenuItem<String>(
                                            value: provider.id,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: <Widget>[
                                                Text(provider.name, style: AppType.body.copyWith(fontSize: 14)),
                                                if (_selectedProvider.id == provider.id)
                                                  Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                      items.add(const PopupMenuDivider());
                                      items.add(
                                        PopupMenuItem<String>(
                                          value: 'ADD_NEW',
                                          child: Row(
                                            children: <Widget>[
                                              Icon(Icons.add_rounded, color: scheme.primary, size: 20),
                                              const SizedBox(width: 8),
                                              Text('إضافة مزود جديد', style: AppType.body.copyWith(fontSize: 14, color: scheme.primary)),
                                            ],
                                          ),
                                        ),
                                      );
                                      return items;
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  // AnimatedSwitcher: smooth cross-fade between send & loading.
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    transitionBuilder: (child, animation) => ScaleTransition(
                                      scale: animation,
                                      child: FadeTransition(opacity: animation, child: child),
                                    ),
                                    child: isLoading
                                        ? Container(
                                          key: const ValueKey('loading'),
                                          width: 40,
                                          height: 40,
                                          padding: const EdgeInsets.all(10),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: scheme.primary,
                                          ),
                                        )
                                      : AnimatedContainer(
                                          key: const ValueKey('send'),
                                          duration: const Duration(milliseconds: 200),
                                          decoration: BoxDecoration(
                                            color: isTyping
                                                ? scheme.primary
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.arrow_upward_rounded,
                                              color: isTyping
                                                  ? Colors.white
                                                  : scheme.onSurfaceVariant
                                                      .withValues(alpha: 0.4),
                                              size: 20,
                                            ),
                                            onPressed: isTyping ? _sendMessage : null,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ), // End of suffixIcon Padding
                          ), // End of InputDecoration
                          onSubmitted: (_) {
                            if (!isLoading) _sendMessage();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

  void _showAddProviderDialog(ColorScheme scheme) {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController urlCtrl = TextEditingController();
    final TextEditingController keyCtrl = TextEditingController();
    final TextEditingController modelCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E), // Dark theme
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                textDirection: TextDirection.rtl,
                children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      'إضافة مزود مخصص',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'Provider Name (e.g. LM Studio)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: Colors.white),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'API URL',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  style: const TextStyle(color: Colors.white),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  style: const TextStyle(color: Colors.white),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'Model Name',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    final String name = nameCtrl.text.trim();
                    final String url = urlCtrl.text.trim();
                    final String key = keyCtrl.text.trim();
                    final String model = modelCtrl.text.trim();

                    if (name.isEmpty || url.isEmpty || model.isEmpty) {
                      _showErrorSnackBar('يرجى تعبئة الحقول الأساسية (الاسم، الرابط، الموديل)');
                      return;
                    }

                    final AiProvider newProvider = AiProvider(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                      baseUrl: url,
                      apiKey: key,
                      modelName: model,
                      isDefault: false,
                    );

                    _saveProvider(newProvider);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'حفظ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  // ── Main Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المساعد الذكي'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.medical_information_rounded),
            tooltip: 'مرجع الأدوية (FDA)',
            onPressed: () => DrugReferenceBottomSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _messages.isEmpty ? null : _clearChat,
            tooltip: 'مسح المحادثة',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Message list or empty state ──
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _messages.isEmpty
                  ? _buildEmptyState(scheme)
                  : _buildChatList(scheme),
            ),
          ),

          // ── Typing indicator (AnimatedSwitcher for smooth entry/exit) ──
          ValueListenableBuilder<bool>(
            valueListenable: _isLoadingNotifier,
            builder: (context, isLoading, child) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLoading
                    ? _buildTypingIndicator(scheme)
                    : const SizedBox.shrink(),
              );
            },
          ),

          // ── Input dock ──
          _buildInputArea(scheme),
        ],
      ),
    );
  }
}

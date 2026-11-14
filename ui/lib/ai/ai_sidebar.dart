import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../knowledge/kb_provider.dart';
import '../../knowledge/kb_service.dart';
import '../../theme/lumen_colors.dart';

/// The AI sidebar: chat with local Ollama models and use RAG to ground
/// responses in the user's notes.
///
/// Privacy: nothing leaves the user's machine. All requests go to the local
/// Ollama instance (http://localhost:11434 by default).
class AiSidebar extends ConsumerStatefulWidget {
  const AiSidebar({super.key});

  @override
  ConsumerState<AiSidebar> createState() => _AiSidebarState();
}

class _AiSidebarState extends ConsumerState<AiSidebar> {
  final _controller = TextEditingController();
  final _messages = <_AiMessage>[];
  bool _loading = false;
  String? _error;
  List<KbAiModel> _models = const [];
  String? _selectedModel;
  String? _embeddingModel;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final service = ref.read(kbServiceProvider);
      final models = await service.listAiModels();
      if (mounted) {
        setState(() {
          _models = models;
          if (models.isNotEmpty && _selectedModel == null) {
            _selectedModel = models.first.name;
          }
        });
      }
    } catch (_) {
      // Ollama may not be running; the user will see an error when chatting.
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _selectedModel == null || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _messages.add(_AiMessage(text: text, isUser: true));
      _controller.clear();
    });

    try {
      final service = ref.read(kbServiceProvider);

      // First, retrieve relevant context via RAG.
      final contexts = await service.ragAi(
        query: text,
        embeddingModel: _embeddingModel,
      );

      // Build a system prompt with the retrieved context.
      final contextText = contexts
          .map((c) => '--- Note: ${c.title} (${c.path}) ---\n${c.body}\n')
          .join('\n');
      final systemPrompt =
          'You are a helpful assistant for a personal journal. '
          'Answer using only the provided note context when relevant. '
          'If the context does not contain the answer, say so. '
          'Here are relevant notes:\n\n$contextText';

      final response = await service.chatAi(
        model: _selectedModel!,
        message: text,
        system: contextText.isNotEmpty ? systemPrompt : null,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _messages.add(_AiMessage(
            text: response.content,
            isUser: false,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surfaceContainer,
            border: Border(
              bottom: BorderSide(color: t.outlineVariant, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'AI Assistant',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (_models.isEmpty)
                    const Text(
                      'Ollama not running',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_models.isNotEmpty) ...[
                Text(
                  'Model',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  value: _selectedModel,
                  isDense: true,
                  items: _models
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.name,
                          child: Text(m.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedModel = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Embedding model (RAG re-ranking)',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                DropdownButton<String?>(
                  value: _embeddingModel,
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None (Tantivy only)'),
                    ),
                    ..._models
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.name,
                            child: Text(m.name),
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => _embeddingModel = v),
                ),
              ],
            ],
          ),
        ),

        // Messages
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: t.error, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'AI error: $_error',
                        style: TextStyle(color: t.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loadModels,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Align(
                      alignment: msg.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.85,
                        ),
                        decoration: BoxDecoration(
                          color: msg.isUser
                              ? t.primary.withValues(alpha: 0.15)
                              : t.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          msg.text,
                          style: TextStyle(color: t.onSurface),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surfaceContainer,
            border: Border(
              top: BorderSide(color: t.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_loading && _selectedModel != null,
                  decoration: InputDecoration(
                    hintText: _loading
                        ? 'Thinking…'
                        : _selectedModel == null
                            ? 'No model available'
                            : 'Ask about your notes…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _loading || _selectedModel == null
                      ? t.onSurfaceVariant.withValues(alpha: 0.3)
                      : t.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _loading || _selectedModel == null ? null : _send,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 18),
                  color: _loading || _selectedModel == null
                      ? t.onSurfaceVariant
                      : t.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiMessage {
  const _AiMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

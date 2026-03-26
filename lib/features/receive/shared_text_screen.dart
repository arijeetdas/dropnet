import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SharedTextScreen extends StatefulWidget {
  const SharedTextScreen({super.key, required this.text});

  final String text;

  @override
  State<SharedTextScreen> createState() => _SharedTextScreenState();
}

class _SharedTextScreenState extends State<SharedTextScreen> {
  bool _copied = false;

  bool get _isLink {
    final text = widget.text.trim();
    if (text.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(text);
    if (uri == null) {
      return false;
    }
    final hasScheme = uri.scheme == 'http' || uri.scheme == 'https';
    return hasScheme && uri.host.trim().isNotEmpty;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Text copied to clipboard.')));
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(widget.text.trim());
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Text')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      const minHeight = 120.0;
                      const maxHeight = 420.0;
                      const inset = 24.0;
                      final textStyle =
                          theme.textTheme.bodyLarge ??
                          const TextStyle(fontSize: 16);
                      final painter = TextPainter(
                        text: TextSpan(text: widget.text, style: textStyle),
                        textDirection: Directionality.of(context),
                        maxLines: null,
                      )..layout(maxWidth: (width - inset).clamp(120.0, width));
                      final targetHeight = (painter.height + inset).clamp(
                        minHeight,
                        maxHeight,
                      );
                      final capped = targetHeight >= maxHeight;

                      return Container(
                        width: width,
                        height: targetHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.outlineVariant),
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Scrollbar(
                          thumbVisibility: capped,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              widget.text,
                              style: textStyle,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _copy,
                          icon: Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                          ),
                          label: Text(_copied ? 'Copied' : 'Copy'),
                        ),
                      ),
                      if (_isLink) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openLink,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Open'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

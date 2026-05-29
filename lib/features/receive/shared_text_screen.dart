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
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Shared Text'),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.04),
              colorScheme.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primaryContainer.withValues(alpha: 0.15),
                            colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isLink ? Icons.link_rounded : Icons.description_rounded,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isLink ? 'Shared Link Received' : 'Shared Text Received',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Copy to clipboard or open in your browser.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Flexible(
                      fit: FlexFit.loose,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final textStyle = theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                letterSpacing: 0.3,
                                color: colorScheme.onSurface,
                                fontFamily: 'monospace',
                              ) ??
                              const TextStyle(fontSize: 15, height: 1.5, fontFamily: 'monospace');

                          return ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 120.0,
                              maxHeight: 460.0,
                            ),
                            child: Container(
                              width: width,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.surfaceContainerLow,
                                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(alpha: 0.02),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(22),
                              child: Scrollbar(
                                thumbVisibility: true,
                                radius: const Radius.circular(8),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    widget.text,
                                    style: textStyle,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _copy,
                            icon: Icon(
                              _copied ? Icons.check_rounded : Icons.copy_rounded,
                              size: 18,
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            label: Text(
                              _copied ? 'Copied to Clipboard' : 'Copy Text',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        if (_isLink) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openLink,
                              icon: const Icon(Icons.open_in_new_rounded, size: 18),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: colorScheme.primary, width: 1.5),
                              ),
                              label: const Text(
                                'Open Link',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
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
      ),
    );
  }
}

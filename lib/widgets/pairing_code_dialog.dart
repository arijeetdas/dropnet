import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PairingCodeDialog extends StatefulWidget {
  const PairingCodeDialog({
    super.key,
    required this.deviceName,
    required this.fileName,
    this.displayCode,
    this.expectedCode,
    this.onCodeSubmitted,
  });

  final String deviceName;
  final String fileName;
  final String? displayCode;
  final String? expectedCode;
  final ValueChanged<String>? onCodeSubmitted;

  @override
  State<PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<PairingCodeDialog> {
  late final TextEditingController _codeController;
  late final FocusNode _focusNode;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isDisplayMode => widget.displayCode != null;
  bool get _isInputMode =>
      widget.onCodeSubmitted != null || widget.expectedCode != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 720;
    final canSubmit = _codeController.text.length == 6;

    return Dialog.fullscreen(
      child: SafeArea(
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          body: Stack(
            children: [
              _buildBackdrop(theme),
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 32 : 20,
                    20,
                    isWide ? 32 : 20,
                    24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.surface.withValues(alpha: 0.98),
                            colorScheme.surfaceContainerLow.withValues(
                              alpha: 0.98,
                            ),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.12),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isWide ? 32 : 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(theme),
                            const SizedBox(height: 24),
                            _buildHero(theme),
                            const SizedBox(height: 24),
                            _buildContextCards(theme, isWide: isWide),
                            if (_isInputMode && _errorText != null) ...[
                              const SizedBox(height: 18),
                              _buildErrorBanner(theme),
                            ],
                            const SizedBox(height: 24),
                            if (_isDisplayMode)
                              _buildDisplayCode(theme)
                            else
                              _buildInputCode(theme),
                            const SizedBox(height: 28),
                            _buildActions(
                              theme,
                              isWide: isWide,
                              canSubmit: canSubmit,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackdrop(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return IgnorePointer(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.surface,
                  colorScheme.surfaceContainerLowest,
                  colorScheme.surface,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.18),
                    colorScheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: -150,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.tertiary.withValues(alpha: 0.14),
                    colorScheme.tertiary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isDisplayMode
                    ? Icons.shield_rounded
                    : Icons.verified_user_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _isDisplayMode
                    ? 'Secure Pairing Code'
                    : 'Verification Required',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (_isDisplayMode)
          IconButton.filledTonal(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
  }

  Widget _buildHero(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer,
                colorScheme.secondaryContainer,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Icon(
            _isDisplayMode ? Icons.key_rounded : Icons.password_rounded,
            size: 42,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isDisplayMode ? 'Share this code' : 'Verify this pairing request',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _isDisplayMode
              ? 'Send the 6-digit code below to ${widget.deviceName}. They must enter it on their device to complete verification.'
              : 'Enter the 6-digit code shown on ${widget.deviceName}. Only continue if the device details match what you expect.',
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.45,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildContextCards(ThemeData theme, {required bool isWide}) {
    if (isWide) {
      return Row(
        children: [
          Expanded(
            child: _buildContextCard(
              theme,
              icon: Icons.devices_rounded,
              label: 'Device',
              value: widget.deviceName,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildContextCard(
              theme,
              icon: Icons.insert_drive_file_rounded,
              label: 'Request',
              value: widget.fileName,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildContextCard(
          theme,
          icon: Icons.devices_rounded,
          label: 'Device',
          value: widget.deviceName,
        ),
        const SizedBox(height: 12),
        _buildContextCard(
          theme,
          icon: Icons.insert_drive_file_rounded,
          label: 'Request',
          value: widget.fileName,
        ),
      ],
    );
  }

  Widget _buildContextCard(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: colorScheme.surface.withValues(alpha: 0.74),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            ),
            child: Icon(icon, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorText!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayCode(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final code = widget.displayCode ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.55),
                colorScheme.surface.withValues(alpha: 0.88),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Verification Code',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: colorScheme.surface.withValues(alpha: 0.8),
                    ),
                    child: Text(
                      'One-time use',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Ask ${widget.deviceName} to enter these exact digits.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _buildCodeStrip(theme, code: code, emphasize: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code copied to clipboard')),
            );
          },
          icon: const Icon(Icons.copy_all_rounded),
          label: const Text('Copy Code'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildInputCode(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: colorScheme.surface.withValues(alpha: 0.84),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Enter the 6-digit code',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: colorScheme.secondaryContainer.withValues(
                        alpha: 0.55,
                      ),
                    ),
                    child: Text(
                      '6 digits',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'The code must match the one shown on ${widget.deviceName}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _codeController,
                        builder: (context, _) {
                          final code = _codeController.text;
                          final selectionOffset =
                              _codeController.selection.baseOffset;
                          final activeIndex =
                              selectionOffset >= 0 && selectionOffset < 6
                              ? selectionOffset
                              : (code.length < 6 ? code.length : 5);
                          return _buildCodeStrip(
                            theme,
                            code: code,
                            activeIndex: activeIndex,
                            emphasize: false,
                          );
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          focusNode: _focusNode,
                          controller: _codeController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onChanged: (value) {
                            setState(() {
                              if (_errorText != null) _errorText = null;
                            });
                            if (value.length == 6) {
                              _focusNode.unfocus();
                            }
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStrip(
    ThemeData theme, {
    required String code,
    required bool emphasize,
    int? activeIndex,
  }) {
    final colorScheme = theme.colorScheme;
    const gap = 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final digits = code.padRight(6).split('');
        final maxBoxWidth = emphasize ? 80.0 : 64.0;
        final boxWidth = ((constraints.maxWidth - 5 * gap) / 6).clamp(
          36.0,
          maxBoxWidth,
        );
        final boxHeight = boxWidth * (emphasize ? 1.2 : 1.25);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int index = 0; index < 6; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: boxWidth,
                height: boxHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(emphasize ? 24 : 18),
                  gradient: LinearGradient(
                    colors: [
                      activeIndex == index
                          ? colorScheme.primaryContainer.withValues(alpha: 0.8)
                          : index < code.length
                          ? colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.78,
                            )
                          : colorScheme.surface.withValues(alpha: 0.74),
                      activeIndex == index
                          ? colorScheme.secondaryContainer.withValues(
                              alpha: 0.78,
                            )
                          : colorScheme.surface.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: activeIndex == index
                        ? colorScheme.primary
                        : index < code.length
                        ? colorScheme.primary.withValues(alpha: 0.22)
                        : colorScheme.outlineVariant,
                    width: activeIndex == index || emphasize ? 1.8 : 1.0,
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      index < code.length ? digits[index] : '',
                      style:
                          (emphasize
                                  ? theme.textTheme.displaySmall
                                  : theme.textTheme.headlineMedium)
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.primary,
                                letterSpacing: emphasize ? 0 : 1.5,
                              ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildActions(
    ThemeData theme, {
    required bool isWide,
    required bool canSubmit,
  }) {
    final primaryButton = _isInputMode
        ? FilledButton.icon(
            onPressed: canSubmit
                ? () {
                    final entered = _codeController.text;
                    final expected = widget.expectedCode;
                    if (expected != null && entered != expected) {
                      setState(() {
                        _errorText =
                            'Incorrect code. Verify it with ${widget.deviceName} and try again.';
                      });
                      return;
                    }
                    widget.onCodeSubmitted?.call(entered);
                    Navigator.of(context).pop(true);
                  }
                : null,
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Verify Code'),
          )
        : FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Done'),
          );

    final secondaryButton = OutlinedButton.icon(
      onPressed: () => Navigator.of(context).pop(false),
      icon: const Icon(Icons.close_rounded),
      label: const Text('Cancel'),
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: SizedBox(height: 52, child: secondaryButton)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: SizedBox(height: 52, child: primaryButton)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 52, child: primaryButton),
        const SizedBox(height: 12),
        SizedBox(height: 52, child: secondaryButton),
      ],
    );
  }
}

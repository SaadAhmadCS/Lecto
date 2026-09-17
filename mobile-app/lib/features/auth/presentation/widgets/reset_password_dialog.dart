import 'package:flutter/material.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Asks for an email and sends a Firebase password-reset link to it.
/// Pops with the email the link was sent to, or null if cancelled.
class ResetPasswordDialog extends StatefulWidget {
  final AuthService authService;
  final String initialEmail;

  const ResetPasswordDialog({
    super.key,
    required this.authService,
    this.initialEmail = '',
  });

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await widget.authService.resetPassword(email);
      if (mounted) Navigator.of(context).pop(email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = ErrorMessages.from(e, action: 'send the reset link');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.darkSurface,
      title: const Text('Reset password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We\'ll email you a link to choose a new password.',
            style: TextStyle(color: AppColors.textSecondaryDark),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            autofocus: widget.initialEmail.isEmpty,
            enabled: !_isSending,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send link'),
        ),
      ],
    );
  }
}

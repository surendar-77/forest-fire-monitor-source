import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Sign in, or create an account. New accounts start as viewers: they see
/// every sensor with its location and the alerts; an administrator can give
/// them a responder or admin role later.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _creating = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_creating) {
        await widget.auth.signUp(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await widget.auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AuthService.describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above first.');
      return;
    }

    try {
      await widget.auth.sendPasswordReset(email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AuthService.describeError(error));
      }
    }
  }

  void _switchMode() {
    setState(() {
      _creating = !_creating;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 64,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Forest Fire Monitor',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _creating
                            ? 'Create an account to see the sensors, their locations and alerts.'
                            : 'Sign in to your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      if (_creating) ...[
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => (value?.trim() ?? '').isEmpty
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          return text.contains('@')
                              ? null
                              : 'Enter a valid email';
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        autofillHints: [
                          _creating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: _creating
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _busy || _creating ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _creating ? 'At least 6 characters' : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) return 'Enter your password';
                          if (_creating && text.length < 6) {
                            return 'At least 6 characters';
                          }
                          return null;
                        },
                      ),
                      if (_creating) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _busy ? null : _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value != _passwordController.text
                              ? 'Passwords do not match'
                              : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: TextStyle(color: colors.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_creating ? 'Create account' : 'Sign in'),
                      ),
                      const SizedBox(height: 8),
                      if (!_creating)
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      const Divider(height: 24),
                      TextButton(
                        onPressed: _busy ? null : _switchMode,
                        child: Text(
                          _creating
                              ? 'Already have an account? Sign in'
                              : 'New here? Create an account',
                        ),
                      ),
                      if (_creating)
                        Text(
                          'New accounts can view sensors, their locations and alerts. '
                          'An administrator can give you more access.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

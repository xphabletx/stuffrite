// lib/screens/sign_in_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _withGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.signInWithGoogle(); // runs migrations internally
      // AuthGate will route onward automatically.
    } on FirebaseAuthException catch (e) {
      final msg = e.message ?? 'Authentication error.';
      setState(() => _error = msg);
      _showSnack(msg);
    } catch (e) {
      final msg = e.toString();
      setState(() => _error = msg);
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInEmail() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      const msg = 'Email and password required';
      setState(() => _error = msg);
      _showSnack(msg);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthService.signInWithEmail(email: email, password: pass);
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No user found for that email.';
          break;
        case 'wrong-password':
          msg = 'Incorrect password.';
          break;
        case 'invalid-email':
          msg = 'Invalid email format.';
          break;
        default:
          msg = e.message ?? 'Authentication error.';
      }
      setState(() => _error = msg);
      _showSnack(msg);
    } catch (e) {
      final msg = e.toString();
      setState(() => _error = msg);
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      const msg = 'Enter your email to reset password';
      setState(() => _error = msg);
      _showSnack(msg);
      return;
    }
    try {
      await AuthService.sendPasswordReset(email);
      _showSnack('Password reset email sent');
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Failed to send reset email');
    }
  }

  // ---- CREATE ACCOUNT BOTTOM SHEET ----
  Future<void> _openCreateAccountSheet() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController(text: _email.text.trim());
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    String? sheetError;
    bool sheetBusy = false;

    String? emailValidator(String? v) {
      final val = (v ?? '').trim();
      if (val.isEmpty) return 'Email required';
      final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(val);
      if (!ok) return 'Enter a valid email';
      return null;
    }

    String? passValidator(String? v) {
      if ((v ?? '').isEmpty) return 'Password required';
      if ((v ?? '').length < 6) return 'Min 6 characters';
      return null;
    }

    String? confirmValidator(String? v) {
      if ((v ?? '').isEmpty) return 'Confirm your password';
      if (v != passCtrl.text) return 'Passwords do not match';
      return null;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: StatefulBuilder(
                  builder: (ctx2, setSheet) {
                    Future<void> onCreate() async {
                      if (!formKey.currentState!.validate()) return;
                      setSheet(() {
                        sheetError = null;
                        sheetBusy = true;
                      });
                      try {
                        await AuthService.createWithEmail(
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text,
                          displayName: null,
                        );
                        if (!ctx2.mounted) return; // guard ctx2 after await
                        Navigator.of(ctx2).pop();
                        _showSnack('Account created. You are signed in.');
                      } on FirebaseAuthException catch (e) {
                        switch (e.code) {
                          case 'email-already-in-use':
                            sheetError = 'That email is already in use.';
                            break;
                          case 'invalid-email':
                            sheetError = 'Invalid email format.';
                            break;
                          case 'operation-not-allowed':
                            sheetError = 'Email/password sign-up is disabled.';
                            break;
                          case 'weak-password':
                            sheetError = 'Password is too weak.';
                            break;
                          default:
                            sheetError = e.message ?? 'Sign-up error.';
                        }
                        setSheet(() {});
                        _showSnack(sheetError!);
                      } catch (e) {
                        sheetError = e.toString();
                        setSheet(() {});
                        _showSnack(sheetError!);
                      } finally {
                        setSheet(() => sheetBusy = false);
                      }
                    }

                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Form(
                            key: formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  textCapitalization: TextCapitalization.none,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                  validator: emailValidator,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: passCtrl,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Password',
                                  ),
                                  validator: passValidator,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: confirmCtrl,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm Password',
                                  ),
                                  validator: confirmValidator,
                                  onFieldSubmitted: (_) => onCreate(),
                                ),
                              ],
                            ),
                          ),
                          if (sheetError != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(
                                  255,
                                  0,
                                  0,
                                  0,
                                ).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                sheetError!,
                                style: const TextStyle(
                                  color: Color.fromARGB(255, 0, 0, 0),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              onPressed: sheetBusy ? null : onCreate,
                              child: sheetBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Create account'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Sign in', style: TextStyle(color: Colors.black)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(
                                255,
                                0,
                                0,
                                0,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color.fromARGB(255, 0, 0, 0),
                              ),
                            ),
                          ),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textCapitalization: TextCapitalization.none,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Email'),
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          onSubmitted: (_) => _signInEmail(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: busy ? null : _forgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: busy ? null : _signInEmail,
                                child: const Text('Sign in'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : _openCreateAccountSheet,
                                child: const Text('Create account'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.g_mobiledata,
                              size: 28,
                              color: Colors.black,
                            ),
                            label: const Text('Continue with Google'),
                            onPressed: busy ? null : _withGoogle,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Solo Mode is automatic after sign-in. If you’ve joined a workspace before, we’ll reopen it.',
                          style: TextStyle(color: Colors.grey.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

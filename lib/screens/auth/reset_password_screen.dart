import 'package:flutter/material.dart';

import '../../service/api_service.dart';
import '../../service/auth_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Opened from the Forgot Password screen. The route argument is the reset
// token (a String) when the backend returned one (development). When there is
// no token argument, the user types the reset code from the email.
class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _isLoading = false;
  bool _done = false;
  String? _errorMessage;

  bool get _needsCode => widget.token == null || widget.token!.isEmpty;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_isLoading) return; // block double taps
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.resetPassword(
        token: _needsCode ? _codeController.text.trim() : widget.token!,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _done = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  // Clears the stack so Login is the only screen left.
  void _goToLogin() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.softGrey, fontSize: 15),
      prefixIcon: Icon(icon, color: AppColors.softGrey, size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.blushBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: border(AppColors.softPink),
      focusedBorder: border(AppColors.primaryPink, 1.5),
      errorBorder: border(Colors.red.shade400),
      focusedErrorBorder: border(Colors.red.shade400, 1.5),
    );
  }

  Widget _eyeButton(bool hidden, VoidCallback onTap) {
    return IconButton(
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: AppColors.softGrey,
        size: 22,
      ),
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [AppColors.blushBackground, AppColors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.deepPink, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Center(
                            child: Image.asset(
                              'asset/logo.png',
                              height: 72,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (_done) _buildSuccess() else _buildForm(),
                          const SizedBox(height: 24),
                        ],
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

  // Lock with a shield badge, drawn with icons only.
  Widget _buildIllustration({bool success = false}) {
    return Center(
      child: SizedBox(
        width: 84,
        height: 72,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.softPink,
                shape: BoxShape.circle,
              ),
              child: Icon(
                success ? Icons.check_rounded : Icons.lock_rounded,
                color: AppColors.primaryPink,
                size: 38,
              ),
            ),
            if (!success)
              Positioned(
                right: 0,
                bottom: 2,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPink,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: AppColors.white, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create New Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a strong password to keep your ModelLive account secure.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.softGrey, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 24),
        _buildIllustration(),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Column(
            children: [
              // Only shown when the code was not passed from the previous screen.
              if (_needsCode) ...[
                TextFormField(
                  controller: _codeController,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: _fieldDecoration(
                    hint: 'Reset code from your email',
                    icon: Icons.vpn_key_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the reset code.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _passwordController,
                obscureText: _hidePassword,
                textInputAction: TextInputAction.next,
                decoration: _fieldDecoration(
                  hint: 'New password',
                  icon: Icons.lock_outline,
                  suffix: _eyeButton(_hidePassword,
                      () => setState(() => _hidePassword = !_hidePassword)),
                ),
                // No password rules are documented in the project, so we only
                // check it is not empty. The backend reports any others.
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a new password.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmController,
                obscureText: _hideConfirm,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _resetPassword(),
                decoration: _fieldDecoration(
                  hint: 'Confirm new password',
                  icon: Icons.lock_outline,
                  suffix: _eyeButton(_hideConfirm,
                      () => setState(() => _hideConfirm = !_hideConfirm)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your new password.';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.blushBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
        ],
        PinkButton(
          text: 'Reset Password',
          loading: _isLoading,
          onPressed: _resetPassword,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Remember your password? ',
              style: TextStyle(color: AppColors.softGrey, fontSize: 14),
            ),
            GestureDetector(
              onTap: _goToLogin,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Login',
                  style: TextStyle(
                    color: AppColors.primaryPink,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIllustration(success: true),
        const SizedBox(height: 24),
        const Text(
          'Password Updated',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your password has been reset. You can now log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.softGrey, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 32),
        PinkButton(text: 'Back to Login', onPressed: _goToLogin),
      ],
    );
  }
}

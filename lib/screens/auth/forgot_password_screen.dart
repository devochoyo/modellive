import 'package:flutter/material.dart';

import '../../service/api_service.dart';
import '../../service/auth_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _requestSent = false;
  String? _resetToken; // only returned by the backend in development
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // Validates the email, then calls the existing AuthService.
  // In development the backend may return "reset_token"; it is passed on to
  // the Reset Password screen. Otherwise the user types the code from the email.
  Future<void> _sendResetLink() async {
    if (_isLoading) return; // block double taps
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result =
          await AuthService.forgotPassword(email: _emailController.text.trim());
      _resetToken = result['reset_token'] as String?;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _requestSent = true;
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

  void _goToLogin() => Navigator.pop(context);

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
              // Back button, top-left.
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.deepPink, size: 22),
                    onPressed: _goToLogin,
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
                          if (_requestSent) _buildSuccess() else _buildForm(),
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

  // Small lock + mail icon composition (no image asset needed).
  Widget _buildIllustration({IconData? icon}) {
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
                icon ?? Icons.lock_reset_rounded,
                color: AppColors.primaryPink,
                size: 38,
              ),
            ),
            if (icon == null)
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
                  child: const Icon(Icons.mail_rounded,
                      color: AppColors.white, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Forgot Password?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Don't worry! Enter your email address and we'll help you reset your password.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.softGrey, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 24),
        _buildIllustration(),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onFieldSubmitted: (_) => _sendResetLink(),
            decoration: InputDecoration(
              hintText: 'Email address',
              hintStyle:
                  const TextStyle(color: AppColors.softGrey, fontSize: 15),
              prefixIcon: const Icon(Icons.email_outlined,
                  color: AppColors.softGrey, size: 22),
              filled: true,
              fillColor: AppColors.blushBackground,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              enabledBorder: border(AppColors.softPink),
              focusedBorder: border(AppColors.primaryPink, 1.5),
              errorBorder: border(Colors.red.shade400),
              focusedErrorBorder: border(Colors.red.shade400, 1.5),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Please enter your email address.';
              if (!email.contains('@') || !email.contains('.')) {
                return 'Please enter a valid email address.';
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: 20),
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
        _buildPinkButton(
          text: 'Send Reset Link',
          onPressed: _isLoading ? null : _sendResetLink,
          loading: _isLoading,
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

  // Shown after the request was accepted.
  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIllustration(icon: Icons.mark_email_read_rounded),
        const SizedBox(height: 24),
        const Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'If an account exists with this email, password reset instructions will be sent.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.softGrey, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 32),
        _buildPinkButton(
          text: 'Enter Reset Code',
          onPressed: () => Navigator.pushNamed(
            context,
            '/reset-password',
            arguments: _resetToken,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _goToLogin,
          child: const Text(
            'Back to Login',
            style: TextStyle(
              color: AppColors.primaryPink,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinkButton({
    required String text,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPink,
          disabledBackgroundColor: AppColors.primaryPink,
          foregroundColor: AppColors.white,
          elevation: 4,
          shadowColor: AppColors.primaryPink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: loading
            ? const TypingDots(color: AppColors.white)
            : Text(
                text,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

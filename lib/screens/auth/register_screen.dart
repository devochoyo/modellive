import 'package:flutter/material.dart';

import '../../model/country_model.dart';
import '../../service/api_service.dart';
import '../../service/auth_service.dart';
import '../../widget/common_widgets.dart';
import '../../widget/country_picker.dart';
import '../colors.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _countryFieldKey = GlobalKey<FormFieldState<String>>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _countryController = TextEditingController();
  final _referralCodeController = TextEditingController();

  CountryModel? _country; // picked from the country list
  bool _hidePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Backend rule: 3-30 lowercase letters, numbers or underscores.
  static final RegExp _usernameRule = RegExp(r'^[a-z0-9_]{3,30}$');

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _countryController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  // Opens the searchable country list and shows the chosen country in the field.
  Future<void> _pickCountry() async {
    FocusScope.of(context).unfocus();
    final picked = await showCountryPicker(context, selected: _country);
    if (picked == null) return; // the sheet was closed
    setState(() {
      _country = picked;
      _countryController.text = '${picked.flag}  ${picked.name}';
    });
    _countryFieldKey.currentState?.validate(); // clears the "select a country" error
  }

  // Validates the form, then registers with the existing AuthService.
  // AuthService saves the tokens securely, so the user is already logged in.
  Future<void> _register() async {
    if (_isLoading) return; // block double taps
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.register(
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        fullName: _fullNameController.text.trim(),
        password: _passwordController.text,
        country: _country!.code,
        referralCode: _referralCodeController.text.trim().toUpperCase(),
      );
      if (!mounted) return;
      // Same temporary destination as the login screen.
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
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

  // Same input look as the login screen. The label lives inside as hint text.
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
                      child: _buildContent(),
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

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset(
            'asset/logo.png',
            height: 72,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Create Account',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Join ModelLive and start connecting with people.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.softGrey, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 28),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _fullNameController,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: _fieldDecoration(
                  hint: 'Full name',
                  icon: Icons.person_outline,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your full name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: _fieldDecoration(
                  hint: 'Username',
                  icon: Icons.alternate_email,
                ).copyWith(
                  helperText:
                      '3–30 characters. Letters, numbers and underscores only.',
                  helperMaxLines: 2,
                  helperStyle:
                      const TextStyle(color: AppColors.softGrey, fontSize: 12),
                ),
                validator: (value) {
                  final username = value?.trim() ?? '';
                  if (username.isEmpty) return 'Please choose a username.';
                  if (!_usernameRule.hasMatch(username)) {
                    return 'Use 3–30 lowercase letters, numbers or underscores.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: _fieldDecoration(
                  hint: 'Email address',
                  icon: Icons.email_outlined,
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
              const SizedBox(height: 16),
              // Tapping opens the country list, where the user can search.
              TextFormField(
                key: _countryFieldKey,
                controller: _countryController,
                readOnly: true,
                onTap: _pickCountry,
                decoration: _fieldDecoration(
                  hint: 'Country',
                  icon: Icons.public_rounded,
                  suffix: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.softGrey, size: 26),
                ),
                validator: (value) {
                  if (_country == null) return 'Please select your country.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _hidePassword,
                textInputAction: TextInputAction.next,
                decoration: _fieldDecoration(
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.softGrey,
                      size: 22,
                    ),
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                  ),
                ),
                // No password rules are documented in the project, so we only
                // check that it is not empty. The backend reports any others.
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _referralCodeController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                onFieldSubmitted: (_) => _register(),
                decoration: _fieldDecoration(
                  hint: 'Referral code (optional)',
                  icon: Icons.card_giftcard_rounded,
                ),
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
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _register,
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
            child: _isLoading
                ? const TypingDots(color: AppColors.white)
                : const Text(
                    'Create Account',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Already have an account? ',
              style: TextStyle(color: AppColors.softGrey, fontSize: 14),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context), // back to the login screen
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
        const SizedBox(height: 24),
      ],
    );
  }
}

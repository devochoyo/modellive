import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../service/api_service.dart';
import '../../service/payment_method_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Add a bank account for withdrawals.
// Open it with: await Navigator.pushNamed(context, '/add-payment-method')
// It returns true after the method was saved.
//
// Backend rules (see PaymentMethodService):
//   United States -> routing number
//   Nigeria       -> no routing number and no SWIFT code
//   Any other     -> SWIFT code
// The full account number is only sent to the backend, never stored here.
class AddPaymentMethodScreen extends StatefulWidget {
  const AddPaymentMethodScreen({super.key});

  @override
  State<AddPaymentMethodScreen> createState() => _AddPaymentMethodScreenState();
}

// A country the user can pick, with its usual currency.
class _Country {
  final String code; // 2-letter code sent to the backend
  final String name;
  final String currency;

  const _Country(this.code, this.name, this.currency);
}

class _AddPaymentMethodScreenState extends State<AddPaymentMethodScreen> {
  static const List<_Country> _countries = [
    _Country('NG', 'Nigeria', 'NGN'),
    _Country('US', 'United States', 'USD'),
    _Country('GB', 'United Kingdom', 'GBP'),
    _Country('CA', 'Canada', 'CAD'),
    _Country('GH', 'Ghana', 'GHS'),
    _Country('KE', 'Kenya', 'KES'),
    _Country('ZA', 'South Africa', 'ZAR'),
    _Country('TZ', 'Tanzania', 'TZS'),
    _Country('UG', 'Uganda', 'UGX'),
    _Country('EG', 'Egypt', 'EGP'),
    _Country('AU', 'Australia', 'AUD'),
    _Country('DE', 'Germany', 'EUR'),
    _Country('FR', 'France', 'EUR'),
    _Country('IT', 'Italy', 'EUR'),
    _Country('ES', 'Spain', 'EUR'),
    _Country('NL', 'Netherlands', 'EUR'),
    _Country('IN', 'India', 'INR'),
    _Country('PK', 'Pakistan', 'PKR'),
    _Country('PH', 'Philippines', 'PHP'),
    _Country('AE', 'United Arab Emirates', 'AED'),
    _Country('BR', 'Brazil', 'BRL'),
    _Country('MX', 'Mexico', 'MXN'),
  ];

  static const List<String> _currencies = [
    'NGN', 'USD', 'GBP', 'EUR', 'CAD', 'GHS', 'KES', 'ZAR', 'TZS', 'UGX',
    'EGP', 'AUD', 'INR', 'PKR', 'PHP', 'AED', 'BRL', 'MXN',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bankController = TextEditingController();
  final _accountController = TextEditingController();
  final _routingController = TextEditingController();
  final _swiftController = TextEditingController();

  _Country? _country;
  String? _currency;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _bankController.dispose();
    _accountController.dispose();
    _routingController.dispose();
    _swiftController.dispose();
    super.dispose();
  }

  bool get _isUS => _country?.code == 'US';
  bool get _isNigeria => _country?.code == 'NG';
  bool get _needsSwift => _country != null && !_isUS && !_isNigeria;

  void _pickCountry(_Country? country) {
    setState(() {
      _country = country;
      // The currency follows the country (it can still be changed).
      _currency = country?.currency;
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await PaymentMethodService.addPaymentMethod(
        country: _country!.code,
        currency: _currency!,
        accountName: _nameController.text.trim(),
        bankName: _bankController.text.trim(),
        accountNumber: _accountController.text.replaceAll(' ', ''),
        routingNumber: _isUS ? _routingController.text.trim() : null,
        swiftCode: _needsSwift
            ? _swiftController.text.trim().toUpperCase()
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment method saved.')),
      );
      // The Payout screen reloads the list when it gets this result.
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Could not save the payment method. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _errorMessage = message;
    });
  }

  InputDecoration _decoration(String label, {String? hint}) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.softGrey),
      hintStyle: const TextStyle(color: AppColors.softGrey, fontSize: 14),
      filled: true,
      fillColor: AppColors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: border(AppColors.softPink),
      focusedBorder: border(AppColors.primaryPink, 1.5),
      errorBorder: border(Colors.red.shade400),
      focusedErrorBorder: border(Colors.red.shade400, 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blushBackground,
      appBar: AppBar(
        backgroundColor: AppColors.blushBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.deepPink),
        title: const Text(
          'Add Payment Method',
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Where should we send your money?',
                    style: TextStyle(color: AppColors.softGrey, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<_Country>(
                    value: _country,
                    isExpanded: true,
                    decoration: _decoration('Country'),
                    items: _countries
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: _saving ? null : _pickCountry,
                    validator: (value) =>
                        value == null ? 'Please select your country.' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _currency,
                    isExpanded: true,
                    decoration: _decoration('Currency'),
                    items: _currencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _currency = value),
                    validator: (value) =>
                        value == null ? 'Please select a currency.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('Account holder name',
                        hint: 'Full name on the account'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'Please enter the account holder name.';
                      }
                      if (text.length < 2) return 'This name is too short.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _bankController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('Bank name'),
                    validator: (value) {
                      if ((value?.trim() ?? '').isEmpty) {
                        return 'Please enter the bank name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _accountController,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                    ],
                    decoration: _decoration('Account number',
                        hint: 'Account number or IBAN'),
                    validator: (value) {
                      final text = (value ?? '').replaceAll(' ', '');
                      if (text.isEmpty) {
                        return 'Please enter the account number.';
                      }
                      if (text.length < 4 || text.length > 34) {
                        return 'The account number must have 4 to 34 characters.';
                      }
                      return null;
                    },
                  ),
                  // Only the field the selected country needs.
                  if (_isUS) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _routingController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      decoration: _decoration('Routing number',
                          hint: '9-digit ABA routing number'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Please enter the routing number.';
                        }
                        if (text.length != 9) {
                          return 'A US routing number has 9 digits.';
                        }
                        return null;
                      },
                    ),
                  ],
                  if (_needsSwift) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _swiftController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: _decoration('SWIFT / BIC code',
                          hint: '8 or 11 characters'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Please enter the SWIFT code.';
                        }
                        if (text.length != 8 && text.length != 11) {
                          return 'A SWIFT code has 8 or 11 characters.';
                        }
                        return null;
                      },
                    ),
                  ],
                  if (_isNigeria)
                    const Padding(
                      padding: EdgeInsets.only(top: 12, left: 4),
                      child: Text(
                        'No routing number or SWIFT code is needed for Nigeria.',
                        style:
                            TextStyle(color: AppColors.softGrey, fontSize: 12),
                      ),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  PinkButton(
                    text: 'Save Payment Method',
                    width: double.infinity,
                    loading: _saving,
                    onPressed: _save,
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          color: AppColors.softGrey, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Your account number is stored securely.',
                        style:
                            TextStyle(color: AppColors.softGrey, fontSize: 12),
                      ),
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

import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/payment_method_model.dart';
import '../../model/wallet_model.dart';
import '../../service/api_service.dart';
import '../../service/payment_method_service.dart';
import '../../service/payout_service.dart';
import '../../service/wallet_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Diamond balance and the start of a withdrawal.
// Open it with: Navigator.pushNamed(context, '/payout')
//
// Only diamonds can be withdrawn. Every number comes from the backend and
// nothing is deducted here. "Continue" opens the Withdrawal screen
// ('/withdrawal') with these arguments (a Map):
//   'diamonds'      -> int, the amount to withdraw
//   'paymentMethod' -> PaymentMethodModel, the selected method
//   'calculation'   -> Map from GET /payouts/calculate
class PayoutScreen extends StatefulWidget {
  const PayoutScreen({super.key});

  @override
  State<PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends State<PayoutScreen> {
  final TextEditingController _amountController = TextEditingController();

  WalletModel? _wallet;
  Map<String, dynamic> _summary = {};
  List<PaymentMethodModel> _methods = [];
  PaymentMethodModel? _selectedMethod;

  bool _isLoading = true;
  bool _isRetrying = false;
  String? _errorMessage;

  // Calculation of the typed amount (GET /payouts/calculate).
  Map<String, dynamic>? _calculation;
  bool _calculating = false;
  String? _calcError;
  int _calcToken = 0; // only the newest answer is used
  Timer? _typingTimer;

  bool _continuing = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  // ---------- Loading ----------

  Future<void> _loadAll({bool retry = false, bool silent = false}) async {
    if (!silent) {
      setState(() {
        if (retry) {
          _isRetrying = true;
        } else {
          _isLoading = true;
        }
      });
    }

    try {
      final results = await Future.wait([
        WalletService.getWallet(),
        PayoutService.getPayoutSummary(),
        PaymentMethodService.getPaymentMethods(),
      ]);
      if (!mounted) return;

      final methods = results[2] as List<PaymentMethodModel>;
      setState(() {
        _wallet = results[0] as WalletModel;
        _summary = results[1] as Map<String, dynamic>;
        _methods = methods;
        _selectedMethod = _pickMethod(methods);
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
      _scheduleCalculation(immediately: true);
    } on ApiException catch (e) {
      _showLoadError(e.message, silent);
    } catch (_) {
      _showLoadError('Could not load your payout details.', silent);
    }
  }

  void _showLoadError(String message, bool silent) {
    if (!mounted) return;
    if (silent && _wallet != null) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  // Keep the current choice if it still exists, else the default method.
  PaymentMethodModel? _pickMethod(List<PaymentMethodModel> methods) {
    if (methods.isEmpty) return null;
    final currentId = _selectedMethod?.id;
    for (var m in methods) {
      if (m.id == currentId) return m;
    }
    for (var m in methods) {
      if (m.isDefault) return m;
    }
    return methods.first;
  }

  Future<void> _openAddPaymentMethod() async {
    await Navigator.pushNamed(context, '/add-payment-method');
    if (!mounted) return;
    // A method may have been added: ask the backend again.
    _loadAll(silent: true);
  }

  // ---------- Amount and calculation ----------

  int get _balance => _wallet?.diamonds ?? 0;

  // null when the text is empty or not a whole number.
  int? get _amount => int.tryParse(_amountController.text.trim());

  // Message for the amount field, or null when the amount is fine.
  String? _amountProblem({bool whenEmpty = false}) {
    final text = _amountController.text.trim();
    if (text.isEmpty) return whenEmpty ? 'Enter the diamonds to withdraw.' : null;
    final amount = _amount;
    if (amount == null) return 'Enter a whole number of diamonds.';
    if (amount <= 0) return 'The amount must be more than zero.';
    if (amount > _balance) return 'You only have $_balance diamonds available.';
    return null;
  }

  void _onAmountChanged(String _) {
    setState(() {
      _calculation = null;
      _calcError = null;
    });
    _scheduleCalculation();
  }

  // Waits until typing stops, then asks the backend.
  void _scheduleCalculation({bool immediately = false}) {
    _typingTimer?.cancel();
    if (_amount == null || _amountProblem() != null) {
      setState(() {
        _calculation = null;
        _calculating = false;
      });
      return;
    }
    if (immediately) {
      _calculate();
    } else {
      _typingTimer =
          Timer(const Duration(milliseconds: 500), () => _calculate());
    }
  }

  // GET /payouts/calculate. The currency of the chosen payment method is used.
  Future<Map<String, dynamic>?> _calculate() async {
    final amount = _amount;
    if (amount == null || _amountProblem() != null) return null;

    final token = ++_calcToken;
    setState(() {
      _calculating = true;
      _calcError = null;
    });

    try {
      final result = await PayoutService.calculateWithdrawal(
        diamonds: amount,
        currency: _selectedMethod?.currency,
      );
      if (!mounted || token != _calcToken) return null;
      setState(() {
        _calculation = result;
        _calculating = false;
      });
      return result;
    } on ApiException catch (e) {
      if (mounted && token == _calcToken) {
        setState(() {
          _calcError = e.message;
          _calculating = false;
        });
      }
    } catch (_) {
      if (mounted && token == _calcToken) {
        setState(() {
          _calcError = 'Could not calculate the payout.';
          _calculating = false;
        });
      }
    }
    return null;
  }

  void _selectMethod(PaymentMethodModel method) {
    setState(() {
      _selectedMethod = method;
      _calculation = null;
    });
    _scheduleCalculation(immediately: true);
  }

  void _useMaxAmount() {
    _amountController.text = _balance.toString();
    _onAmountChanged(_amountController.text);
  }

  // ---------- Continue ----------

  Future<void> _continue() async {
    if (_continuing) return;
    final problem = _amountProblem(whenEmpty: true);
    if (problem != null) {
      setState(() {}); // show the message under the field
      _snack(problem);
      return;
    }
    final method = _selectedMethod;
    if (method == null) {
      _snack('Add a payment method first.');
      return;
    }

    setState(() => _continuing = true);
    // Use the fresh calculation for exactly this amount.
    var calculation = _calculation;
    if (calculation == null) calculation = await _calculate();
    if (!mounted) return;
    setState(() => _continuing = false);

    if (calculation == null) {
      _snack(_calcError ?? 'Could not calculate the payout.');
      return;
    }

    await Navigator.pushNamed(context, '/withdrawal', arguments: {
      'diamonds': _amount!,
      'paymentMethod': method,
      'calculation': calculation,
    });
    if (!mounted) return;
    // The balance may have changed after a withdrawal.
    _loadAll(silent: true);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatNumber(int n) {
    final digits = n.toString();
    String result = '';
    for (int i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      result += digits[i];
      if (fromEnd > 1 && fromEnd % 3 == 1) result += ',';
    }
    return result;
  }

  // ---------- Build ----------

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
          'Payout',
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Withdrawal History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () =>
                Navigator.pushNamed(context, '/withdrawal-history'),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const LoadingView(message: 'Loading payout...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadAll(retry: true),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceCard(),
            const SizedBox(height: 24),
            _buildMethodSection(),
            const SizedBox(height: 24),
            _buildAmountSection(),
            const SizedBox(height: 28),
            PinkButton(
              text: 'Continue',
              width: double.infinity,
              loading: _continuing,
              onPressed: (_balance <= 0 || _methods.isEmpty) ? null : _continue,
            ),
            const SizedBox(height: 18),
            _buildHistoryTile(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    final rate = _summary['usd_per_diamond']?.toString() ?? '0.20';
    final availableUsd = _summary['available_usd']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryPink, AppColors.deepPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available Diamonds',
              style: TextStyle(color: AppColors.softPink, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.diamond_rounded,
                  color: AppColors.white, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatNumber(_balance),
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              availableUsd == null
                  ? 'Rate: 1 diamond = USD $rate'
                  : 'Estimated value: USD $availableUsd  ·  1 diamond = USD $rate',
              style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.deepPink,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ---------- Payment methods ----------

  Widget _buildMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Payment Method'),
        const SizedBox(height: 10),
        if (_methods.isEmpty)
          _buildNoMethod()
        else ...[
          for (final method in _methods) _buildMethodTile(method),
          if (_methods.length < PaymentMethodService.maxPaymentMethods)
            TextButton.icon(
              onPressed: _openAddPaymentMethod,
              icon: const Icon(Icons.add_rounded,
                  color: AppColors.primaryPink, size: 20),
              label: const Text('Add another method',
                  style: TextStyle(
                      color: AppColors.primaryPink,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ],
    );
  }

  Widget _buildNoMethod() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.softPink, width: 1.5),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.softPink,
            child: Icon(Icons.account_balance_rounded,
                color: AppColors.primaryPink, size: 28),
          ),
          const SizedBox(height: 12),
          const Text(
            'No payment method yet',
            style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add a bank account to receive your withdrawals.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.softGrey, fontSize: 13),
          ),
          const SizedBox(height: 14),
          PinkButton(
            text: 'Add Payment Method',
            height: 48,
            width: double.infinity,
            onPressed: _openAddPaymentMethod,
          ),
        ],
      ),
    );
  }

  Widget _buildMethodTile(PaymentMethodModel method) {
    final selected = method.id == _selectedMethod?.id;
    return GestureDetector(
      onTap: () => _selectMethod(method),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.softPink : AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primaryPink : AppColors.softPink,
            width: selected ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_rounded,
                color: AppColors.deepPink, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.bankName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.darkBackground,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${method.accountNumberMasked}  ·  ${method.currency}',
                    style: const TextStyle(
                        color: AppColors.softGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primaryPink : AppColors.softGrey,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Amount ----------

  Widget _buildAmountSection() {
    final problem = _amountProblem();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Withdrawal Amount'),
        const SizedBox(height: 10),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _onAmountChanged,
          style: const TextStyle(
              color: AppColors.darkBackground,
              fontSize: 18,
              fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Diamonds to withdraw',
            hintStyle:
                const TextStyle(color: AppColors.softGrey, fontSize: 15),
            prefixIcon: const Icon(Icons.diamond_rounded,
                color: AppColors.diamondBlue, size: 22),
            suffixIcon: TextButton(
              onPressed: _balance > 0 ? _useMaxAmount : null,
              child: const Text('MAX',
                  style: TextStyle(
                      color: AppColors.primaryPink,
                      fontWeight: FontWeight.bold)),
            ),
            errorText: problem,
            filled: true,
            fillColor: AppColors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            enabledBorder: _border(AppColors.softPink),
            focusedBorder: _border(AppColors.primaryPink, 1.5),
            errorBorder: _border(Colors.red.shade400),
            focusedErrorBorder: _border(Colors.red.shade400, 1.5),
          ),
        ),
        if (_balance <= 0) ...[
          const SizedBox(height: 8),
          const Text(
            'You have no diamonds to withdraw yet. Diamonds come from the flowers you receive.',
            style: TextStyle(color: AppColors.softGrey, fontSize: 13),
          ),
        ],
        const SizedBox(height: 14),
        _buildEstimate(problem),
      ],
    );
  }

  OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Widget _buildEstimate(String? problem) {
    Widget child;

    if (_amount == null || problem != null) {
      child = const Text(
        'Enter an amount to see your estimated payout.',
        style: TextStyle(color: AppColors.softGrey, fontSize: 13),
      );
    } else if (_calculating) {
      child = const Center(child: TypingDots(color: AppColors.primaryPink));
    } else if (_calcError != null) {
      child = Text(_calcError!,
          style: TextStyle(color: Colors.red.shade400, fontSize: 13));
    } else if (_calculation != null) {
      final calc = _calculation!;
      final usd = calc['usd_amount']?.toString() ?? '-';
      final localAmount = calc['local_amount'];
      final currency = calc['currency']?.toString();

      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Estimated payout',
              style: TextStyle(color: AppColors.softGrey, fontSize: 13)),
          const SizedBox(height: 4),
          if (localAmount != null && currency != null)
            Text(
              '$currency $localAmount',
              style: const TextStyle(
                  color: AppColors.deepPink,
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            ),
          Text(
            'USD $usd',
            style: TextStyle(
                color: localAmount != null
                    ? AppColors.softGrey
                    : AppColors.deepPink,
                fontSize: localAmount != null ? 14 : 26,
                fontWeight: FontWeight.bold),
          ),
          if (localAmount == null && currency != null && currency != 'USD')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No exchange rate is set for $currency yet.',
                style:
                    const TextStyle(color: AppColors.softGrey, fontSize: 12),
              ),
            ),
        ],
      );
    } else {
      child = const SizedBox(height: 4);
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softPink, width: 1.2),
      ),
      child: child,
    );
  }

  Widget _buildHistoryTile() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/withdrawal-history'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.softPink, width: 1.2),
        ),
        child: const Row(
          children: [
            Icon(Icons.history_rounded, color: AppColors.deepPink),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Withdrawal History',
                style: TextStyle(
                    color: AppColors.darkBackground,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.softGrey),
          ],
        ),
      ),
    );
  }
}

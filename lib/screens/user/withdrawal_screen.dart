import 'dart:async';

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

// Submit a withdrawal request with available diamonds.
// Open it from the Payout screen with:
//   Navigator.pushNamed(context, '/withdrawal', arguments: {
//     'diamonds': int, 'paymentMethod': PaymentMethodModel,
//     'calculation': Map (from GET /payouts/calculate)
//   })
// The backend deducts the diamonds and controls the status. Nothing is
// deducted or completed locally.
class WithdrawalScreen extends StatefulWidget {
  final int? initialDiamonds;
  final PaymentMethodModel? initialMethod;
  final Map<String, dynamic>? initialCalculation;

  const WithdrawalScreen({
    super.key,
    this.initialDiamonds,
    this.initialMethod,
    this.initialCalculation,
  });

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  final TextEditingController _amountController = TextEditingController();

  WalletModel? _wallet;
  List<PaymentMethodModel> _methods = [];
  PaymentMethodModel? _selectedMethod;

  bool _isLoading = true;
  bool _isRetrying = false;
  String? _errorMessage;

  Map<String, dynamic>? _calculation;
  bool _calculating = false;
  String? _calcError;
  int _calcToken = 0; // only the newest answer is used
  Timer? _typingTimer;

  bool _submitting = false;
  bool _showErrors = false; // validation messages appear after the first try

  int get _balance => _wallet?.diamonds ?? 0;
  int? get _amount => int.tryParse(_amountController.text.trim());

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialMethod;
    _calculation = widget.initialCalculation;
    if (widget.initialDiamonds != null) {
      _amountController.text = widget.initialDiamonds.toString();
    }
    _loadAll();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  // ---------- Loading ----------

  Future<void> _loadAll({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

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
        _methods = methods;
        _selectedMethod = _pickMethod(methods);
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
      _scheduleCalculation(immediately: true);
    } on ApiException catch (e) {
      _showLoadError(e.message);
    } catch (_) {
      _showLoadError('Could not load your withdrawal details.');
    }
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  // Keep the method chosen on the Payout screen if it still exists.
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

  // ---------- Calculation (backend) ----------

  void _onAmountChanged(String _) {
    setState(() {});
    _scheduleCalculation();
  }

  void _scheduleCalculation({bool immediately = false}) {
    _typingTimer?.cancel();
    final amount = _amount;
    if (amount == null || amount <= 0 || _selectedMethod == null) {
      _calcToken++;
      setState(() {
        _calculation = null;
        _calcError = null;
        _calculating = false;
      });
      return;
    }
    // Wait for the user to stop typing so the backend is not called per key.
    _typingTimer = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 500),
      _calculate,
    );
  }

  Future<Map<String, dynamic>?> _calculate() async {
    final amount = _amount;
    final method = _selectedMethod;
    if (amount == null || amount <= 0 || method == null) return null;

    final token = ++_calcToken;
    setState(() {
      _calculating = true;
      _calcError = null;
    });

    try {
      final result = await PayoutService.calculateWithdrawal(
        diamonds: amount,
        currency: method.currency,
      );
      if (!mounted || token != _calcToken) return null;
      setState(() {
        _calculation = result;
        _calculating = false;
      });
      return result;
    } on ApiException catch (e) {
      _calcFailed(token, e.message);
    } catch (_) {
      _calcFailed(token, 'Could not calculate the payout.');
    }
    return null;
  }

  void _calcFailed(int token, String message) {
    if (!mounted || token != _calcToken) return;
    setState(() {
      _calculation = null;
      _calculating = false;
      _calcError = message;
    });
  }

  // ---------- Validation ----------

  String? _amountProblem() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return 'Enter the number of diamonds to withdraw.';
    final amount = int.tryParse(text);
    if (amount == null || amount <= 0) {
      return 'Enter a whole number greater than zero.';
    }
    if (_balance <= 0) return 'You have no diamonds to withdraw.';
    if (amount > _balance) {
      return 'You only have ${_formatNumber(_balance)} diamonds available.';
    }
    return null;
  }

  // ---------- Submit ----------

  Future<void> _submit() async {
    if (_submitting) return; // no duplicate submissions
    setState(() => _showErrors = true);

    final problem = _amountProblem();
    if (problem != null) {
      _snack(problem);
      return;
    }
    final method = _selectedMethod;
    if (method == null) {
      _snack('Select a payment method first.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await PayoutService.requestWithdrawal(
        diamonds: _amount!,
        paymentMethodId: method.id,
      );
      if (!mounted) return;

      // Reload the real balances from the backend (nothing is deducted here).
      try {
        await Future.wait([
          WalletService.getWallet(),
          PayoutService.getPayoutSummary(),
        ]);
      } catch (_) {
        // The history screen loads fresh data anyway.
      }
      if (!mounted) return;

      final status = _statusLabel(result.withdrawal.status);
      _snack('Withdrawal request submitted. Status: $status. '
          'It is not completed yet.');
      setState(() => _submitting = false);
      // The Payout screen stays underneath; the history replaces this screen.
      Navigator.pushReplacementNamed(context, '/withdrawal-history');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(e.message);
      if (e.statusCode == 402) _loadAll(retry: true); // balance changed
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Could not submit your withdrawal. Please try again.');
    }
  }

  String _statusLabel(String status) {
    if (status.isEmpty) return status;
    return status[0].toUpperCase() + status.substring(1);
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
          'Withdraw Diamonds',
          style: TextStyle(
            color: AppColors.deepPink,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const LoadingView(message: 'Loading...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadAll(retry: true),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 20),
          _buildAmountField(),
          const SizedBox(height: 20),
          _buildPaymentMethod(),
          const SizedBox(height: 20),
          _buildEstimate(),
          const SizedBox(height: 14),
          _buildStatusNote(),
          const SizedBox(height: 24),
          PinkButton(
            text: 'Submit Withdrawal',
            width: double.infinity,
            loading: _submitting,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text(
                'Back to Payout',
                style: TextStyle(
                  color: AppColors.deepPink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.diamondBlue.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: AppColors.diamondBlue.withOpacity(0.45), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.diamond_rounded,
                color: AppColors.diamondBlue, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available diamonds',
                  style: TextStyle(
                    color: AppColors.softGrey,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatNumber(_balance),
                    style: const TextStyle(
                      color: AppColors.darkBackground,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountField() {
    final problem = _showErrors ? _amountProblem() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Diamonds to withdraw'),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          enabled: !_submitting,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _onAmountChanged,
          style: const TextStyle(
            color: AppColors.darkBackground,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: 'Enter amount',
            errorText: problem,
            filled: true,
            fillColor: AppColors.white,
            prefixIcon: const Icon(Icons.diamond_rounded,
                color: AppColors.diamondBlue),
            suffixIcon: TextButton(
              onPressed: _submitting || _balance <= 0
                  ? null
                  : () {
                      _amountController.text = _balance.toString();
                      _onAmountChanged(_amountController.text);
                    },
              child: const Text('MAX',
                  style: TextStyle(
                      color: AppColors.deepPink, fontWeight: FontWeight.bold)),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.softPink),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.softPink),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.primaryPink, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethod() {
    if (_methods.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.softPink),
        ),
        child: Column(
          children: [
            const Text(
              'You have no payment method yet.',
              style: TextStyle(color: AppColors.softGrey),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.pushNamed(context, '/add-payment-method');
                if (mounted) _loadAll(retry: true);
              },
              child: const Text('Add Payment Method',
                  style: TextStyle(color: AppColors.deepPink)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Payment method'),
        const SizedBox(height: 8),
        for (var method in _methods) _methodTile(method),
      ],
    );
  }

  Widget _methodTile(PaymentMethodModel method) {
    final selected = method.id == _selectedMethod?.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _submitting
            ? null
            : () {
                setState(() => _selectedMethod = method);
                _scheduleCalculation(immediately: true); // currency may differ
              },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.softPink : AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primaryPink : AppColors.softPink,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  color: AppColors.deepPink),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${method.accountName} · ${method.accountNumberMasked}'
                      ' · ${method.currency}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.softGrey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryPink),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEstimate() {
    final calc = _calculation;
    final currency = _selectedMethod?.currency ?? '';
    final localAmount = calc?['local_amount'];
    final usdAmount = calc?['usd_amount'];

    Widget content;
    if (_calculating) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: TypingDots(),
      );
    } else if (_calcError != null) {
      content = Text(_calcError!,
          style: const TextStyle(color: AppColors.deepPink, fontSize: 14));
    } else if (calc == null) {
      content = const Text(
        'Enter an amount to see your estimated payout.',
        style: TextStyle(color: AppColors.softGrey, fontSize: 14),
      );
    } else if (localAmount != null) {
      content = Column(
        children: [
          Text(
            '$localAmount ${calc['currency'] ?? currency}',
            style: const TextStyle(
              color: AppColors.deepPink,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (usdAmount != null)
            Text('≈ $usdAmount USD',
                style: const TextStyle(color: AppColors.softGrey, fontSize: 13)),
        ],
      );
    } else {
      // No exchange rate for this currency: only the USD amount is known.
      content = Column(
        children: [
          Text(
            '$usdAmount USD',
            style: const TextStyle(
              color: AppColors.deepPink,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'No exchange rate is set for $currency yet.',
            style: const TextStyle(color: AppColors.softGrey, fontSize: 13),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.softPink),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Estimated payout'),
              if (currency.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.softPink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(currency,
                      style: const TextStyle(
                          color: AppColors.deepPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _buildStatusNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purple.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.purple, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your request starts as Pending and is reviewed before it is '
              'paid. Follow it in Withdrawal History. Rejected requests are '
              'refunded by the system.',
              style: TextStyle(color: AppColors.darkBackground, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.darkBackground,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

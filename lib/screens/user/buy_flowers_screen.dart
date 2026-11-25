import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/wallet_model.dart';
import '../../service/api_service.dart';
import '../../service/purchase_service.dart';
import '../../service/wallet_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Buy flowers with coins or diamonds.
// Open it with: Navigator.pushNamed(context, '/buy-flowers')
//
// Balances come from GET /wallet and the prices from GET /wallet/rates.
// The backend takes the payment; this screen never changes a balance itself.
class BuyFlowersScreen extends StatefulWidget {
  const BuyFlowersScreen({super.key});

  @override
  State<BuyFlowersScreen> createState() => _BuyFlowersScreenState();
}

class _BuyFlowersScreenState extends State<BuyFlowersScreen> {
  static const int _maxQuantity = 10000; // same limit as PurchaseService

  final TextEditingController _quantityController =
      TextEditingController(text: '1');

  WalletModel? _wallet;
  num? _coinsPerFlower; // from /wallet/rates
  num? _diamondsPerFlower; // from /wallet/rates

  String _payWith = 'coins'; // "coins" or "diamonds"
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isBuying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  // ---------- Loading ----------

  Future<void> _loadData({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final wallet = await WalletService.getWallet();
      final rates = await WalletService.getWalletRates();
      final coinsPerFlower = _toNumber(rates['coins_per_flower']);
      final diamondsPerFlower = _toNumber(rates['diamonds_per_flower']);

      if (coinsPerFlower == null || diamondsPerFlower == null) {
        throw ApiException('The flower prices are not available right now.');
      }
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _coinsPerFlower = coinsPerFlower;
        _diamondsPerFlower = diamondsPerFlower;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showLoadError(e.message);
    } catch (_) {
      _showLoadError('Could not load your balance. Please try again.');
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

  // The backend may send a rate as a number or as text.
  num? _toNumber(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  // ---------- Quantity and cost ----------

  // null when the box is empty or outside 1 - 10000.
  int? _quantity() {
    final quantity = int.tryParse(_quantityController.text);
    if (quantity == null || quantity < 1 || quantity > _maxQuantity) return null;
    return quantity;
  }

  num? _totalCost() {
    final quantity = _quantity();
    if (quantity == null) return null;
    final rate = _payWith == 'coins' ? _coinsPerFlower! : _diamondsPerFlower!;
    return quantity * rate;
  }

  bool _hasEnough() {
    final cost = _totalCost();
    if (cost == null) return true;
    final balance = _payWith == 'coins' ? _wallet!.coins : _wallet!.diamonds;
    return cost <= balance;
  }

  void _changeQuantity(int change) {
    final current = int.tryParse(_quantityController.text) ?? 0;
    int next = current + change;
    if (next < 1) next = 1;
    if (next > _maxQuantity) next = _maxQuantity;
    setState(() => _quantityController.text = next.toString());
  }

  // ---------- Buying ----------

  Future<void> _buy() async {
    final quantity = _quantity();
    if (_isBuying || quantity == null || !_hasEnough()) return;

    setState(() => _isBuying = true);
    try {
      final result = await PurchaseService.purchaseFlowers(
        quantity: quantity,
        payWith: _payWith,
      );
      final bought = result['flowers_bought'] ?? quantity;

      // The new balance comes from the backend.
      String message = 'You bought $bought flowers.';
      try {
        final wallet = await WalletService.getWallet();
        if (mounted) setState(() => _wallet = wallet);
      } catch (_) {
        message = 'You bought $bought flowers. Could not refresh your balance.';
      }

      if (!mounted) return;
      setState(() => _isBuying = false);
      _showMessage(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBuying = false);
      _showMessage(e is ApiException
          ? e.message
          : 'Could not buy flowers. Please try again.');
    }
  }

  Future<void> _openBuyCoins() async {
    await Navigator.pushNamed(context, '/buy-coins');
    if (!mounted) return;
    try {
      final wallet = await WalletService.getWallet();
      if (mounted) setState(() => _wallet = wallet);
    } catch (_) {
      // Keep the balance that is already on screen.
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // "coin" for a rate of 1, otherwise "coins" (same for diamonds).
  String _unitName(bool isCoins, num rate) {
    final name = isCoins ? 'coin' : 'diamond';
    return rate == 1 ? name : '${name}s';
  }

  // 1250000 -> 1,250,000. Prices with decimals keep two decimals.
  String _formatNumber(num value) {
    if (value != value.roundToDouble()) return value.toStringAsFixed(2);
    final digits = value.toInt().toString();
    String result = '';
    for (int i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      result += digits[i];
      if (fromEnd > 1 && fromEnd % 3 == 1) result += ',';
    }
    return result;
  }

  // ---------- Screen ----------

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
          'Buy Flowers',
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
        onRetry: () => _loadData(retry: true),
      );
    }

    final canBuy = _quantity() != null && _hasEnough();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFlowerImage(),
                const SizedBox(height: 24),
                _sectionTitle('Pay with'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildPayCard('coins')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPayCard('diamonds')),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionTitle('Quantity'),
                const SizedBox(height: 10),
                _buildQuantityRow(),
                const SizedBox(height: 20),
                _buildTotalBox(),
                if (!_hasEnough()) ...[
                  const SizedBox(height: 16),
                  _buildInsufficientBox(),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPink.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Opacity(
            opacity: canBuy || _isBuying ? 1 : 0.5,
            child: PinkButton(
              text: 'Buy Flowers',
              width: double.infinity,
              loading: _isBuying,
              onPressed: canBuy ? _buy : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.darkBackground,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildFlowerImage() {
    return Center(
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          color: AppColors.softPink,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Image.asset('asset/flower.png', width: 92, height: 92),
        ),
      ),
    );
  }

  // One card per payment method, with the balance and the price per flower.
  Widget _buildPayCard(String method) {
    final isCoins = method == 'coins';
    final selected = _payWith == method;
    final balance = isCoins ? _wallet!.coins : _wallet!.diamonds;
    final rate = isCoins ? _coinsPerFlower! : _diamondsPerFlower!;

    return GestureDetector(
      onTap: _isBuying ? null : () => setState(() => _payWith = method),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.softPink : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryPink : AppColors.softPink,
            width: selected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isCoins
                    ? const Icon(Icons.monetization_on_rounded,
                        color: AppColors.gold, size: 30)
                    : const Icon(Icons.diamond_rounded,
                        color: AppColors.diamondBlue, size: 28),
                const Spacer(),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primaryPink : AppColors.softGrey,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isCoins ? 'Coins' : 'Diamonds',
              style: const TextStyle(
                color: AppColors.softGrey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatNumber(balance),
                style: const TextStyle(
                  color: AppColors.darkBackground,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatNumber(rate)} ${_unitName(isCoins, rate)} per flower',
              style: const TextStyle(
                color: AppColors.deepPink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityRow() {
    return Row(
      children: [
        _roundButton(Icons.remove_rounded, () => _changeQuantity(-1)),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _quantityController,
            enabled: !_isBuying,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '0',
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.softPink),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: AppColors.primaryPink, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _roundButton(Icons.add_rounded, () => _changeQuantity(1)),
      ],
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isBuying ? null : onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: AppColors.softPink,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primaryPink, size: 26),
      ),
    );
  }

  Widget _buildTotalBox() {
    final cost = _totalCost();
    final unit = _payWith == 'coins' ? 'Coins' : 'Diamonds';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPink.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Total cost',
              style: TextStyle(
                color: AppColors.darkBackground,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            cost == null ? '--' : '${_formatNumber(cost)} $unit',
            style: const TextStyle(
              color: AppColors.deepPink,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsufficientBox() {
    final isCoins = _payWith == 'coins';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.softPink,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryPink.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.deepPink, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCoins
                      ? 'You do not have enough coins for this purchase.'
                      : 'You do not have enough diamonds for this purchase.',
                  style: const TextStyle(
                    color: AppColors.deepPink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          // Only coins can be bought, so only coins get a Buy Coins button.
          if (isCoins) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openBuyCoins,
                icon: const Icon(Icons.monetization_on_rounded, size: 20),
                label: const Text(
                  'Buy Coins',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPink,
                  backgroundColor: AppColors.white,
                  side: const BorderSide(
                      color: AppColors.primaryPink, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

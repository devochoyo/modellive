import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../model/coin_package_model.dart';
import '../../model/wallet_model.dart';
import '../../service/api_service.dart';
import '../../service/purchase_service.dart';
import '../../service/wallet_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// Buy coins with Google Play Billing.
// Open it with: Navigator.pushNamed(context, '/buy-coins')
//
// Safety: this screen never adds coins itself. PurchaseService sends the
// Google Play purchase token to the backend, consumes the purchase only after
// the backend confirmed it, and then calls onCompleted. Only then is the
// success message shown, and the balance is reloaded from the backend.
class BuyCoinsScreen extends StatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends State<BuyCoinsScreen> {
  WalletModel? _wallet;
  bool _walletRefreshing = false;

  List<CoinPackageModel> _packages = [];
  // Google Play details (with the localized price), by product id.
  final Map<String, ProductDetails> _products = {};
  String? _selectedProductId;

  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isBuying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Callbacks first, so nothing delivered by the listener is missed.
    PurchaseService.onPending = _onPending;
    PurchaseService.onCancelled = _onCancelled;
    PurchaseService.onFailed = _onFailed;
    PurchaseService.onCompleted = _onCompleted;
    PurchaseService.startListening();

    _loadWallet();
    _loadPackages();
  }

  @override
  void dispose() {
    // The listener keeps running so a purchase in progress still gets
    // verified. Only this screen's callbacks are removed.
    PurchaseService.onPending = null;
    PurchaseService.onCancelled = null;
    PurchaseService.onFailed = null;
    PurchaseService.onCompleted = null;
    super.dispose();
  }

  // ---------- Loading ----------

  Future<void> _loadWallet() async {
    if (mounted) setState(() => _walletRefreshing = true);
    try {
      final wallet = await WalletService.getWallet();
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _walletRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _walletRefreshing = false);
    }
  }

  Future<void> _loadPackages({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final available = await PurchaseService.isStoreAvailable();
      if (!available) {
        _showLoadError(
            'Coin purchases are temporarily unavailable. Please try again later.');
        return;
      }

      final packages = await PurchaseService.getCoinPackages();
      final products = await PurchaseService.loadProducts(packages);
      if (!mounted) return;

      setState(() {
        _packages = packages;
        _products.clear();
        for (var product in products) {
          _products[product.id] = product;
        }
        // Forget a selection that is no longer available.
        if (_selectedProductId != null &&
            !_products.containsKey(_selectedProductId)) {
          _selectedProductId = null;
        }
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showLoadError(e.message);
    } catch (_) {
      _showLoadError(
          'Coin purchases are temporarily unavailable. Please try again later.');
    }

    if (retry) _loadWallet();
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  // ---------- Purchase ----------

  Future<void> _buy() async {
    if (_isBuying) return;
    final product = _products[_selectedProductId];
    if (product == null) return;

    setState(() => _isBuying = true);
    try {
      // The result arrives in the callbacks below.
      await PurchaseService.startPurchase(product);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBuying = false);
      _showMessage(e is ApiException
          ? e.message
          : 'The purchase could not be started. Please try again.');
    }
  }

  void _onPending() {
    if (!mounted) return;
    setState(() => _isBuying = true);
  }

  void _onCancelled() {
    if (!mounted) return;
    setState(() => _isBuying = false);
    _showMessage('Purchase cancelled.');
  }

  void _onFailed(String message) {
    if (!mounted) return;
    setState(() => _isBuying = false);
    _showMessage(message);
  }

  // Called only after the backend verified the purchase.
  void _onCompleted(Map<String, dynamic> result) {
    if (!mounted) return;
    setState(() => _isBuying = false);
    _showSuccessDialog();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.monetization_on_rounded,
                      color: AppColors.gold, size: 56),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Purchase Successful!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.deepPink,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your coins have been added to your ModelLive wallet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.softGrey,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                PinkButton(
                  text: 'Done',
                  width: double.infinity,
                  height: 50,
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
          ),
        );
      },
    );

    // The new balance comes from the backend, never from a local sum.
    if (mounted) _loadWallet();
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
          'Buy Coins',
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
    if (_isLoading) return const LoadingView(message: 'Loading coin packages...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadPackages(retry: true),
      );
    }
    if (_packages.isEmpty) {
      return const EmptyStateView(
        icon: Icons.monetization_on_outlined,
        title: 'No Packages Yet',
        message: 'Coin packages are not available right now. Please check back soon.',
      );
    }

    final canBuy = _selectedProductId != null &&
        _products.containsKey(_selectedProductId);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIntro(),
                const SizedBox(height: 20),
                _buildBalanceBox(),
                const SizedBox(height: 22),
                _buildPackageGrid(),
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
          // Disabled until an available package is selected.
          child: Opacity(
            opacity: canBuy || _isBuying ? 1 : 0.5,
            child: PinkButton(
              text: 'Buy Coins',
              width: double.infinity,
              loading: _isBuying,
              onPressed: canBuy ? _buy : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get More Coins',
                style: TextStyle(
                  color: AppColors.deepPink,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Purchase coins to send beautiful flowers and support your favorite creators.',
                style: TextStyle(
                  color: AppColors.softGrey,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Small stack of coins.
        SizedBox(
          width: 84,
          height: 76,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: Icon(Icons.monetization_on_rounded,
                    color: AppColors.gold.withOpacity(0.55), size: 40),
              ),
              Positioned(
                right: 0,
                bottom: 4,
                child: Icon(Icons.monetization_on_rounded,
                    color: AppColors.gold.withOpacity(0.75), size: 44),
              ),
              const Positioned(
                left: 16,
                top: 0,
                child: Icon(Icons.monetization_on_rounded,
                    color: AppColors.gold, size: 56),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceBox() {
    Widget amount;
    if (_walletRefreshing) {
      amount = const TypingDots(dotSize: 6);
    } else {
      amount = Text(
        _wallet == null ? '--' : _formatNumber(_wallet!.coins),
        style: const TextStyle(
          color: AppColors.darkBackground,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.monetization_on_rounded,
                color: AppColors.gold, size: 30),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Your Coin Balance',
              style: TextStyle(
                color: AppColors.darkBackground,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          amount,
        ],
      ),
    );
  }

  Widget _buildPackageGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: _packages.map(_buildPackageCard).toList(),
    );
  }

  Widget _buildPackageCard(CoinPackageModel package) {
    final product = _products[package.productId];
    final available = product != null;
    final selected = _selectedProductId == package.productId;

    return GestureDetector(
      onTap: (!available || _isBuying)
          ? null
          : () => setState(() => _selectedProductId = package.productId),
      child: Opacity(
        opacity: available ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(12),
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
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on_rounded,
                        color: AppColors.gold, size: 36),
                    const SizedBox(height: 6),
                    Text(
                      '${package.coins} Coins',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.darkBackground,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The price comes from Google Play, never from this app.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        product != null ? product.price : 'Unavailable',
                        style: TextStyle(
                          color: available
                              ? AppColors.deepPink
                              : AppColors.softGrey,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primaryPink : AppColors.softGrey,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 1250000 -> 1,250,000
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
}

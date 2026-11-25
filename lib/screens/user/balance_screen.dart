import 'package:flutter/material.dart';

import '../../model/wallet_model.dart';
import '../../service/api_service.dart';
import '../../service/wallet_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// The logged-in user's wallet. Every number comes from the backend.
// Open it with: Navigator.pushNamed(context, '/balance')
class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  WalletModel? _wallet;
  bool _isLoading = true;
  bool _isRetrying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  // [silent] reloads without hiding the balances (used after returning
  // from the Buy Coins screen).
  Future<void> _loadWallet({bool retry = false, bool silent = false}) async {
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
      final wallet = await WalletService.getWallet();
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showLoadError(e.message, silent);
    } catch (_) {
      _showLoadError('Could not load your balance. Please try again.', silent);
    }
  }

  void _showLoadError(String message, bool silent) {
    if (!mounted) return;
    // A silent refresh that fails keeps the balances already on screen.
    if (silent && _wallet != null) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  Future<void> _openBuyCoins() async {
    await Navigator.pushNamed(context, '/buy-coins');
    if (!mounted) return;
    // Coins may have been bought: ask the backend for the real balance.
    _loadWallet(silent: true);
  }

  Future<void> _openBuyFlowers() async {
    await Navigator.pushNamed(context, '/buy-flowers');
    if (!mounted) return;
    _loadWallet(silent: true);
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
          'My Balance',
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
    if (_isLoading) return const LoadingView(message: 'Loading balance...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadWallet(retry: true),
      );
    }

    final wallet = _wallet!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Wallet',
            style: TextStyle(
              color: AppColors.deepPink,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Manage your ModelLive balance.',
            style: TextStyle(color: AppColors.softGrey, fontSize: 15),
          ),
          const SizedBox(height: 24),
          // Two cards in a row, the third one full width below.
          Row(
            children: [
              Expanded(
                child: _buildBalanceCard(
                  label: 'Coins',
                  value: wallet.coins,
                  background: AppColors.gold.withOpacity(0.16),
                  border: AppColors.gold.withOpacity(0.45),
                  icon: const Icon(Icons.monetization_on_rounded,
                      color: AppColors.gold, size: 38),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildBalanceCard(
                  label: 'Diamonds',
                  value: wallet.diamonds,
                  background: AppColors.diamondBlue.withOpacity(0.14),
                  border: AppColors.diamondBlue.withOpacity(0.45),
                  icon: const Icon(Icons.diamond_rounded,
                      color: AppColors.diamondBlue, size: 36),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBalanceCard(
            label: 'Flowers',
            value: wallet.flowers,
            background: AppColors.softPink,
            border: AppColors.primaryPink.withOpacity(0.35),
            icon: Image.asset('asset/flower.png', width: 40, height: 40),
          ),
          const SizedBox(height: 28),
          PinkButton(
            text: 'Buy Coins',
            width: double.infinity,
            onPressed: _openBuyCoins,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: _openBuyFlowers,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepPink,
                side: const BorderSide(color: AppColors.primaryPink, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Buy Flowers',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard({
    required String label,
    required int value,
    required Color background,
    required Color border,
    required Widget icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border, width: 1.2),
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
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.softGrey,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatNumber(value),
              style: const TextStyle(
                color: AppColors.darkBackground,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

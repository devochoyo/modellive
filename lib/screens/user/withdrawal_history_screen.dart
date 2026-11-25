import 'package:flutter/material.dart';

import '../../model/payment_method_model.dart';
import '../../model/withdrawal_model.dart';
import '../../service/api_service.dart';
import '../../service/payment_method_service.dart';
import '../../service/payout_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// The user's withdrawal requests. This screen only SHOWS the status the
// backend sends. It never changes a status or a balance.
// Open it with: Navigator.pushNamed(context, '/withdrawal-history')
class WithdrawalHistoryScreen extends StatefulWidget {
  const WithdrawalHistoryScreen({super.key});

  @override
  State<WithdrawalHistoryScreen> createState() =>
      _WithdrawalHistoryScreenState();
}

class _WithdrawalHistoryScreenState extends State<WithdrawalHistoryScreen> {
  static const int _perPage = 20;

  final ScrollController _scrollController = ScrollController();
  final List<WithdrawalModel> _withdrawals = [];
  // A withdrawal only knows its payment method id, so the methods are loaded
  // to show the bank name and the masked account number.
  final Map<int, PaymentMethodModel> _methods = {};

  int _page = 1;
  bool _isLoading = true;
  bool _isRetrying = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPaymentMethods();
    _loadWithdrawals();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final methods = await PaymentMethodService.getPaymentMethods();
      if (!mounted) return;
      setState(() {
        for (var method in methods) {
          _methods[method.id] = method;
        }
      });
    } catch (_) {
      // The history still works without the bank details.
    }
  }

  Future<void> _loadWithdrawals({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final list = await PayoutService.getWithdrawals(page: 1, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _withdrawals
          ..clear()
          ..addAll(list);
        _page = 1;
        _hasMore = list.length == _perPage;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showLoadError(e.message);
    } catch (_) {
      _showLoadError('Could not load your withdrawals. Please try again.');
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading || _errorMessage != null) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final list = await PayoutService.getWithdrawals(
        page: _page + 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        _withdrawals.addAll(list);
        _hasMore = list.length == _perPage;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) _loadMore();
  }

  void _openDetails(WithdrawalModel withdrawal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _WithdrawalDetailsSheet(
        withdrawal: withdrawal,
        method: _methods[withdrawal.paymentMethodId],
      ),
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
          'Withdrawal History',
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
    if (_isLoading) return const LoadingView(message: 'Loading withdrawals...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadWithdrawals(retry: true),
      );
    }
    if (_withdrawals.isEmpty) {
      return const EmptyStateView(
        icon: Icons.receipt_long_rounded,
        title: 'No Withdrawals Yet',
        message: 'Your withdrawal requests will appear here.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _loadWithdrawals,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _withdrawals.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _withdrawals.length) {
            return SizedBox(
              height: 48,
              child: _isLoadingMore ? const Center(child: TypingDots()) : null,
            );
          }
          return _buildCard(_withdrawals[index]);
        },
      ),
    );
  }

  Widget _buildCard(WithdrawalModel withdrawal) {
    final method = _methods[withdrawal.paymentMethodId];
    final hasLocal =
        withdrawal.localCurrency != null && withdrawal.localAmount != null;

    return GestureDetector(
      onTap: () => _openDetails(withdrawal),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '\$${withdrawal.usdAmount}',
                    style: const TextStyle(
                      color: AppColors.darkBackground,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusChip(status: withdrawal.status),
              ],
            ),
            if (hasLocal) ...[
              const SizedBox(height: 2),
              Text(
                '${withdrawal.localCurrency} ${withdrawal.localAmount}',
                style: const TextStyle(color: AppColors.softGrey, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            _infoRow(Icons.diamond_rounded, AppColors.diamondBlue,
                '${withdrawal.diamonds} diamonds'),
            const SizedBox(height: 6),
            _infoRow(Icons.calendar_today_rounded, AppColors.softGrey,
                _formatDate(withdrawal.createdAt)),
            if (method != null) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.account_balance_rounded, AppColors.softGrey,
                  '${method.bankName} · ${method.accountNumberMasked}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.darkBackground, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

// 14 Nov 2026
String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

// 14 Nov 2026, 09:30
String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)}, $hour:$minute';
}

// The same colors and label for a status everywhere on this screen.
// Statuses: pending, approved, processing, completed, rejected.
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color background;
    switch (status) {
      case 'approved':
        textColor = const Color(0xFF0284C7);
        background = AppColors.diamondBlue.withOpacity(0.18);
        break;
      case 'processing':
        textColor = AppColors.purple;
        background = AppColors.purple.withOpacity(0.12);
        break;
      case 'completed':
        textColor = const Color(0xFF15803D);
        background = const Color(0xFF16A34A).withOpacity(0.14);
        break;
      case 'rejected':
        textColor = AppColors.deepPink;
        background = AppColors.softPink;
        break;
      default: // pending
        textColor = const Color(0xFFB7791F);
        background = AppColors.gold.withOpacity(0.22);
    }

    final label = status.isEmpty
        ? ''
        : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Bottom sheet with the full details (GET /payouts/withdrawals/<id>).
class _WithdrawalDetailsSheet extends StatefulWidget {
  final WithdrawalModel withdrawal; // shown until the details arrive
  final PaymentMethodModel? method;

  const _WithdrawalDetailsSheet({required this.withdrawal, this.method});

  @override
  State<_WithdrawalDetailsSheet> createState() =>
      _WithdrawalDetailsSheetState();
}

class _WithdrawalDetailsSheetState extends State<_WithdrawalDetailsSheet> {
  WithdrawalModel? _details;
  bool _isLoading = true;
  bool _isRetrying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final details = await PayoutService.getWithdrawalDetails(
          withdrawalId: widget.withdrawal.id);
      if (!mounted) return;
      setState(() {
        _details = details;
        _errorMessage = null;
        _isLoading = false;
        _isRetrying = false;
      });
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not load the details. Please try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
      _isRetrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.softPink,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Withdrawal Details',
                style: TextStyle(
                  color: AppColors.deepPink,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: LoadingView(message: 'Loading details...'),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ErrorRetryView(
          message: _errorMessage!,
          retrying: _isRetrying,
          onRetry: () => _loadDetails(retry: true),
        ),
      );
    }

    final w = _details!;
    final method = widget.method;
    final hasNote = w.adminNote != null && w.adminNote!.isNotEmpty;

    return Column(
      children: [
        _detailRow('Status', child: _StatusChip(status: w.status)),
        _detailRow('Amount', text: '\$${w.usdAmount}'),
        if (w.localCurrency != null && w.localAmount != null)
          _detailRow('Local amount', text: '${w.localCurrency} ${w.localAmount}'),
        _detailRow('Diamonds used', text: '${w.diamonds}'),
        _detailRow('Rate per diamond', text: '\$${w.usdPerDiamond}'),
        _detailRow('Requested', text: _formatDateTime(w.createdAt)),
        if (w.updatedAt != null)
          _detailRow('Last update', text: _formatDateTime(w.updatedAt!)),
        if (method != null) ...[
          _detailRow('Bank', text: method.bankName),
          _detailRow('Account', text: method.accountNumberMasked),
        ],
        if (hasNote) _detailRow('Note', text: w.adminNote!),
        if (w.status == 'rejected') ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.softPink,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Diamonds from a rejected request are returned to your wallet.',
              style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailRow(String label, {String? text, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.softGrey, fontSize: 14),
            ),
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: child ??
                  Text(
                    text ?? '',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.darkBackground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

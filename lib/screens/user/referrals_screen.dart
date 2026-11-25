import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/referral_model.dart';
import '../../service/api_service.dart';
import '../../service/referral_service.dart';
import '../../widget/common_widgets.dart';
import '../colors.dart';

// How many people the user referred, the coins earned from them, and who they
// are. The reward is paid by the backend; this screen only SHOWS the numbers.
// Open it with: Navigator.pushNamed(context, '/referrals')
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  static const int _perPage = 20;

  final ScrollController _scrollController = ScrollController();
  final List<ReferralModel> _referrals = [];
  ReferralSummaryModel? _summary;

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
    _loadReferrals();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadReferrals({bool retry = false}) async {
    setState(() {
      if (retry) {
        _isRetrying = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final summary = await ReferralService.getSummary();
      final list =
          await ReferralService.getReferrals(page: 1, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _referrals
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
      _showLoadError('Could not load your referrals. Please try again.');
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
      final list = await ReferralService.getReferrals(
        page: _page + 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        _referrals.addAll(list);
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

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _summary!.referralCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied.')),
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
          'Referrals',
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
    if (_isLoading) return const LoadingView(message: 'Loading referrals...');
    if (_errorMessage != null) {
      return ErrorRetryView(
        message: _errorMessage!,
        retrying: _isRetrying,
        onRetry: () => _loadReferrals(retry: true),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _loadReferrals,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        // Row 0 is the summary, then one row per person, then the loader.
        itemCount: _referrals.length + 2,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) return _buildSummary(_summary!);
          if (index == _referrals.length + 1) {
            return SizedBox(
              height: 48,
              child: _isLoadingMore ? const Center(child: TypingDots()) : null,
            );
          }
          return _buildPersonCard(_referrals[index - 1]);
        },
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryPink.withOpacity(0.10),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  // Totals, the user's own code and the "People You Referred" title.
  Widget _buildSummary(ReferralSummaryModel summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                label: 'People Referred',
                value: summary.totalReferrals.toString(),
                background: AppColors.softPink,
                border: AppColors.primaryPink.withOpacity(0.35),
                icon: const Icon(Icons.people_alt_rounded,
                    color: AppColors.primaryPink, size: 34),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildStatCard(
                label: 'Coins Earned',
                value: summary.totalEarnedCoins.toString(),
                background: AppColors.gold.withOpacity(0.16),
                border: AppColors.gold.withOpacity(0.45),
                icon: const Icon(Icons.monetization_on_rounded,
                    color: AppColors.gold, size: 36),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCodeCard(summary),
        const SizedBox(height: 24),
        const Text(
          'People You Referred',
          style: TextStyle(
            color: AppColors.darkBackground,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (_referrals.isEmpty) ...[
          const SizedBox(height: 28),
          const EmptyStateView(
            icon: Icons.person_add_alt_1_rounded,
            title: 'No Referrals Yet',
            message: 'Share your code. Friends who sign up with it will show up here.',
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color background,
    required Color border,
    required Widget icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          icon,
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.darkBackground,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.softGrey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(ReferralSummaryModel summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Referral Code',
            style: TextStyle(color: AppColors.softGrey, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.blushBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.softPink),
                  ),
                  child: Text(
                    summary.referralCode,
                    style: const TextStyle(
                      color: AppColors.deepPink,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _copyCode,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryPink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.copy_rounded,
                      color: AppColors.white, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Earn ${summary.rewardPercent}% of the coins a friend buys on their '
            'first purchase. It is a ModelLive reward, so nothing is taken from your friend.',
            style: const TextStyle(
              color: AppColors.softGrey,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonCard(ReferralModel person) {
    final name = (person.fullName != null && person.fullName!.isNotEmpty)
        ? person.fullName!
        : person.username;

    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/public-profile', arguments: person.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            UserAvatar(url: person.avatarUrl, name: name, radius: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkBackground,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    person.joinedAt == null
                        ? '@${person.username}'
                        : '@${person.username} · Joined ${_formatDate(person.joinedAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.softGrey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildEarning(person),
          ],
        ),
      ),
    );
  }

  // "+5" once the friend has bought coins, "Pending" before their first purchase.
  Widget _buildEarning(ReferralModel person) {
    if (!person.hasPurchased) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.blushBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Pending',
          style: TextStyle(color: AppColors.softGrey, fontSize: 12),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.monetization_on_rounded,
            color: AppColors.gold, size: 20),
        const SizedBox(width: 4),
        Text(
          '+${person.coinsEarned}',
          style: const TextStyle(
            color: Color(0xFF15803D),
            fontSize: 16,
            fontWeight: FontWeight.bold,
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

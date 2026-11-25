import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/user/balance_screen.dart';
import 'screens/user/buy_coins_screen.dart';
import 'screens/user/buy_flowers_screen.dart';
import 'screens/user/add_payment_method_screen.dart';
import 'screens/user/host_live_screen.dart';
import 'screens/user/payout_screen.dart';
import 'screens/user/viewer_live_screen.dart';
import 'screens/user/individual_chat_screen.dart';
import 'screens/user/notifications_screen.dart';
import 'screens/user/public_profile_screen.dart';
import 'screens/user/referrals_screen.dart';
import 'screens/user/withdrawal_history_screen.dart';
import 'screens/user/withdrawal_screen.dart';
import 'model/payment_method_model.dart';
import 'widget/bottom_navigation_bar.dart';
import 'screens/colors.dart';
import 'model/conversation_model.dart';
import 'model/live_stream_model.dart';
import 'model/user_model.dart';
import 'service/api_service.dart';
import 'service/diagnostics_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Diagnostics.installErrorHooks();
  Diagnostics.log('APP',
      'ModelLive started. Diagnostics build v4 is active. Tap Go Live to see the live-stream steps here.');
  final startRoute = await _chooseStartRoute();
  runApp(ModelLiveApp(startRoute: startRoute));
  // If the last run crashed, print the report and show it on screen.
  Diagnostics.checkPreviousRun();
}

// New user -> onboarding. Seen onboarding -> login.
// Already logged in (a token is stored) -> home.
Future<String> _chooseStartRoute() async {
  try {
    final seen = await const FlutterSecureStorage()
        .read(key: OnboardingScreen.doneKey);
    if (seen != 'true') return '/onboarding';

    final token = await ApiService.getAccessToken();
    if (token != null) return '/home';
    return '/login';
  } catch (_) {
    return '/onboarding';
  }
}

class ModelLiveApp extends StatelessWidget {
  final String startRoute;

  const ModelLiveApp({super.key, required this.startRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ModelLive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryPink),
      ),
      navigatorKey: ApiService.navigatorKey,
      initialRoute: startRoute,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  // Simple route table. _PlaceholderScreen is only used for pages that
  // belong to later batches.
  static Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    Widget page;
    switch (settings.name) {
      case '/onboarding':
        page = const OnboardingScreen();
        break;
      case '/login':
        page = const LoginScreen();
        break;
      case '/register':
        page = const RegisterScreen();
        break;
      case '/forgot-password':
        page = const ForgotPasswordScreen();
        break;
      case '/reset-password':
        // The argument is the reset token (String) when the backend returned one.
        page = ResetPasswordScreen(token: settings.arguments as String?);
        break;
      case '/home':
        // Batch 7: the main screen holds the bottom navigation bar.
        page = const MainScreen(initialIndex: 0);
        break;
      case '/friends':
        page = const MainScreen(initialIndex: 1);
        break;
      case '/notifications':
        page = const NotificationsScreen();
        break;
      // The argument is a LiveStreamModel (with its host).
      case '/viewer-live':
        final liveArg = settings.arguments;
        page = liveArg is LiveStreamModel
            ? ViewerLiveScreen(stream: liveArg)
            : const _PlaceholderScreen(title: 'Live Stream');
        break;
      // Batch 6. The optional argument is the live title (String).
      case '/host-live':
        final titleArg = settings.arguments;
        page = HostLiveScreen(title: titleArg is String ? titleArg : null);
        break;
      // Batch 4: the argument is a UserModel (or the user id as an int).
      case '/public-profile':
        final arg = settings.arguments;
        final userId = arg is UserModel ? arg.id : (arg is int ? arg : 0);
        page = PublicProfileScreen(userId: userId);
        break;
      case '/personal-profile':
        page = const MainScreen(initialIndex: 3);
        break;
      case '/balance':
        page = const BalanceScreen();
        break;
      case '/referrals':
        page = const ReferralsScreen();
        break;
      case '/buy-coins':
        page = const BuyCoinsScreen();
        break;
      // Batch 5.
      case '/chat-list':
        page = const MainScreen(initialIndex: 2);
        break;
      // The argument is a ConversationModel (from the chat list) or a
      // UserModel (from a public profile).
      case '/individual-chat':
        final chatArg = settings.arguments;
        if (chatArg is ConversationModel) {
          page = IndividualChatScreen(
            user: chatArg.user,
            conversationId: chatArg.conversationId,
          );
        } else {
          page = IndividualChatScreen(user: chatArg as UserModel);
        }
        break;
      case '/buy-flowers':
        page = const BuyFlowersScreen();
        break;
      case '/withdrawal-history':
        page = const WithdrawalHistoryScreen();
        break;
      // Batch 6.
      case '/payout':
        page = const PayoutScreen();
        break;
      case '/add-payment-method':
        page = const AddPaymentMethodScreen();
        break;
      // Batch 7. The argument is a Map with 'diamonds', 'paymentMethod' and
      // 'calculation' (all optional here; the screen loads what it needs).
      case '/withdrawal':
        final wArg = settings.arguments;
        final wMap = wArg is Map ? wArg : const {};
        page = WithdrawalScreen(
          initialDiamonds: wMap['diamonds'] is int ? wMap['diamonds'] : null,
          initialMethod: wMap['paymentMethod'] is PaymentMethodModel
              ? wMap['paymentMethod']
              : null,
          initialCalculation: wMap['calculation'] is Map<String, dynamic>
              ? wMap['calculation']
              : null,
        );
        break;
      default:
        page = const LoginScreen();
    }
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}

// Temporary screen for pages that belong to later batches.
class _PlaceholderScreen extends StatelessWidget {
  final String title;

  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title screen coming soon')),
    );
  }
}

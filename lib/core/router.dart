import 'package:go_router/go_router.dart';
import '../features/admin/admin_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/role_screen.dart';
import '../features/courts/notifications_screen.dart';
import '../features/booking/court_detail_screen.dart';
import '../features/booking/my_bookings_screen.dart';
import '../features/booking/pay_deposit_screen.dart';
import '../features/courts/courts_screen.dart';
import '../features/owner/owner_screen.dart';

final appRouter = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, _) => const LoginScreen()),
  GoRoute(path: '/role', builder: (_, _) => const RoleScreen()),
  GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
  GoRoute(path: '/courts', builder: (_, _) => const CourtsScreen()),
  GoRoute(
      path: '/courts/:id',
      builder: (_, s) => CourtDetailScreen(courtId: s.pathParameters['id']!)),
  GoRoute(path: '/bookings', builder: (_, _) => const MyBookingsScreen()),
  GoRoute(
      path: '/bookings/:id/pay',
      builder: (_, s) => PayDepositScreen(bookingId: s.pathParameters['id']!)),
  GoRoute(path: '/owner', builder: (_, _) => const OwnerScreen()),
  GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
]);

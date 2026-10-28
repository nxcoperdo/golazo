import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/admin/admin_shell.dart';
import '../features/auth/consent_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/password_reset_screens.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/booking/court_detail_screen.dart';
import '../features/booking/pay_deposit_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/owner/court_form_screen.dart';
import '../features/owner/court_manage_screen.dart';
import '../features/owner/owner_shell.dart';
import '../features/owner/stats_screen.dart';
import '../features/player/player_shell.dart';

/// Pantallas que se ven sin sesión.
const _publicPaths = ['/login', '/register', '/forgot', '/reset'];

String homeFor(Role r) => switch (r) {
      Role.player => '/home',
      Role.owner => '/owner',
      Role.admin => '/admin',
    };

/// Qué rol puede abrir cada zona de la app.
Role? _zoneRole(String path) {
  if (path.startsWith('/owner')) return Role.owner;
  if (path.startsWith('/admin')) return Role.admin;
  if (path.startsWith('/home') || path.startsWith('/courts') || path.startsWith('/bookings')) {
    return Role.player;
  }
  return null; // perfil, verificación, splash: cualquier rol
}

final routerProvider = Provider<GoRouter>((ref) {
  // Hace que el router vuelva a evaluar sus redirecciones cuando cambia la sesión.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  String? redirect(context, GoRouterState s) {
    final path = s.uri.path;
    final session = ref.read(sessionProvider);

    // Confirmar el correo funciona con o sin sesión.
    if (path == '/verify') return null;

    if (session.isLoading || session.hasError) return path == '/splash' ? null : '/splash';

    final user = session.value;
    if (user == null) {
      return _publicPaths.contains(path) ? null : '/login';
    }
    // Sin la aceptación vigente de los textos legales no se puede usar la app.
    if (user.consentRequired) return path == '/consent' ? null : '/consent';
    if (path == '/consent') return homeFor(user.role);
    // Con sesión no tiene sentido ver login/registro/splash: se va al inicio de su rol.
    if (path == '/' || path == '/splash' || path == '/login' || path == '/register') {
      return homeFor(user.role);
    }
    final zone = _zoneRole(path);
    if (zone != null && zone != user.role) return homeFor(user.role);
    return null;
  }

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset', builder: (_, s) => ResetPasswordScreen(token: s.uri.queryParameters['token'])),
      GoRoute(path: '/verify', builder: (_, s) => VerifyEmailScreen(token: s.uri.queryParameters['token'])),
      GoRoute(path: '/consent', builder: (_, _) => const ConsentScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),

      // Jugador
      GoRoute(
          path: '/home',
          builder: (_, s) => PlayerShell(tab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
      GoRoute(path: '/courts/:id', builder: (_, s) => CourtDetailScreen(courtId: s.pathParameters['id']!)),
      GoRoute(path: '/bookings/:id/pay', builder: (_, s) => PayDepositScreen(bookingId: s.pathParameters['id']!)),

      // Dueño
      GoRoute(
          path: '/owner',
          builder: (_, s) => OwnerShell(tab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
      GoRoute(path: '/owner/courts/new', builder: (_, _) => const CourtFormScreen()),
      GoRoute(path: '/owner/courts/:id', builder: (_, s) => CourtManageScreen(courtId: s.pathParameters['id']!)),
      GoRoute(path: '/owner/stats', builder: (_, _) => const StatsScreen()),

      // Administrador
      GoRoute(
          path: '/admin',
          builder: (_, s) => AdminShell(tab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
    ],
  );
});

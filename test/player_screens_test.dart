import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/widgets/legal_consent.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/auth/profile_screen.dart';
import 'package:golazo/features/notifications/notifications_screen.dart';
import 'package:golazo/features/player/my_bookings_screen.dart';

import 'courts_screens_test.dart' show FakeApi;

Booking mkBooking(String id, String court, BookingStatus status,
        {int days = 3, bool lastMinute = false, bool reviewed = false, bool cancellable = true, int deposit = 54000}) =>
    Booking(
      id: id,
      courtId: 'c-$id',
      courtName: court,
      startAt: DateTime.now().toUtc().add(Duration(days: days)),
      hours: 2,
      total: 180000,
      deposit: deposit,
      lastMinute: lastMinute,
      status: status,
      cancellable: cancellable,
      reviewed: reviewed,
    );

class PlayerApi extends FakeApi {
  PlayerApi({super.user, List<Booking>? bookings, List<AppNotification>? notices})
      : list = bookings ?? [],
        notices = notices ?? [];

  List<Booking> list;
  List<AppNotification> notices;
  final cancelled = <String>[];
  final reviewsSent = <String>[];
  final profileCalls = <String>[];
  int markedAll = 0;
  String? deletedWith;
  bool deleted = false;

  @override
  Future<List<Booking>> myBookings() async => list;

  @override
  Future<Booking> cancelBooking(String id) async {
    cancelled.add(id);
    return list.firstWhere((b) => b.id == id);
  }

  @override
  Future<void> reviewBooking(String bookingId, int stars, String? body) async =>
      reviewsSent.add('$bookingId:$stars:$body');

  @override
  Future<NotificationsPage> notifications({int limit = 50}) async =>
      NotificationsPage(unread: notices.where((n) => n.unread).length, items: notices);

  @override
  Future<void> markAllNotificationsRead() async => markedAll++;

  @override
  Future<AppUser> updateProfile({String? name, String? phone}) async {
    profileCalls.add('name=$name phone=$phone');
    return AppUser(
      id: 'u1',
      name: name ?? 'Alejandro Martínez',
      email: 'alejandro@correo.com',
      role: Role.player,
      phone: phone ?? '3001234567',
      emailVerified: true,
    );
  }

  @override
  Future<void> changePassword(String current, String next) async => profileCalls.add('pw:$current>$next');

  @override
  Future<void> resendVerification() async => profileCalls.add('resend');

  @override
  Future<void> deleteAccount({String? password}) async {
    deleted = true;
    deletedWith = password;
  }
}

const me = AppUser(
  id: 'u1',
  name: 'Alejandro Martínez',
  email: 'alejandro@correo.com',
  role: Role.player,
  phone: '3001234567',
  emailVerified: true,
);

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pumpScreen(WidgetTester t, Widget screen, FakeApi api, {List<Uri>? opened}) async {
  tallPhone(t);
  await t.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api),
      if (opened != null) openUrlProvider.overrideWithValue((u) async { opened.add(u); return true; }),
    ],
    child: MaterialApp(home: screen),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  group('mis reservas', () {
    PlayerApi api0() => PlayerApi(user: me, bookings: [
          mkBooking('b1', 'La Bombonera 5', BookingStatus.confirmed, lastMinute: true, cancellable: false),
          mkBooking('b2', 'Golazo Arena', BookingStatus.pendingPayment, days: 5, deposit: 14000),
          mkBooking('b3', 'Distrito Fútbol', BookingStatus.confirmed, days: -10, cancellable: false),
          mkBooking('b4', 'Cancha El Potrero', BookingStatus.cancelled, days: -20, cancellable: false),
        ]);

    testWidgets('próximas: estados, totales, aviso de último momento y acciones', (t) async {
      await pumpScreen(t, const MyBookingsScreen(), api0());
      expect(find.text('Mis reservas'), findsOneWidget);
      expect(find.text('Tu agenda'.toUpperCase()), findsOneWidget);
      expect(find.text('La Bombonera 5'), findsOneWidget);
      expect(find.text('Confirmada'), findsOneWidget);
      expect(find.text('Falta comprobante'), findsOneWidget);
      expect(find.text('Reserva de último momento · Sin cancelación'), findsOneWidget);
      expect(find.textContaining(r'$180.000', findRichText: true), findsWidgets);
      expect(find.text('Pagar anticipo'), findsOneWidget);
      // Solo la reserva sin pagar se puede cancelar.
      expect(find.text('Cancelar'), findsOneWidget);
      // Las anteriores no aparecen en "Próximas".
      expect(find.text('Distrito Fútbol'), findsNothing);
    });

    testWidgets('anteriores: Completada con Calificar y Cancelada', (t) async {
      await pumpScreen(t, const MyBookingsScreen(), api0());
      await t.tap(find.text('Anteriores'));
      await t.pumpAndSettle();
      expect(find.text('Distrito Fútbol'), findsOneWidget);
      expect(find.text('Completada'), findsOneWidget);
      expect(find.text('Calificar'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('La Bombonera 5'), findsNothing);
    });

    testWidgets('cancelar pide confirmación en una hoja y cancela', (t) async {
      final api = api0();
      await pumpScreen(t, const MyBookingsScreen(), api);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.text('¿Cancelar la reserva?'), findsOneWidget);
      await t.tap(find.text('Sí, cancelar reserva'));
      await t.pumpAndSettle();
      expect(api.cancelled, ['b2']);
      expect(find.text('Reserva cancelada'), findsOneWidget);
    });

    testWidgets('Volver cierra la hoja sin cancelar', (t) async {
      final api = api0();
      await pumpScreen(t, const MyBookingsScreen(), api);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Volver'));
      await t.pumpAndSettle();
      expect(api.cancelled, isEmpty);
    });

    testWidgets('calificar: Publicar reseña se habilita al elegir estrellas y envía comentario', (t) async {
      final api = api0();
      await pumpScreen(t, const MyBookingsScreen(), api);
      await t.tap(find.text('Anteriores'));
      await t.pumpAndSettle();
      await t.tap(find.text('Calificar'));
      await t.pumpAndSettle();
      expect(find.text('Califica la cancha'), findsOneWidget);
      expect(find.textContaining('Distrito Fútbol'), findsWidgets);
      final publish = find.widgetWithText(FilledButton, 'Publicar reseña');
      expect(t.widget<FilledButton>(publish).onPressed, isNull);

      await t.tap(find.byTooltip('4 estrellas'));
      await t.pump();
      expect(t.widget<FilledButton>(publish).onPressed, isNotNull);
      await t.enterText(find.byType(TextField), 'Muy buena cancha');
      await t.tap(publish);
      await t.pumpAndSettle();
      expect(api.reviewsSent, ['b3:4:Muy buena cancha']);
      expect(find.text('¡Gracias por tu reseña!'), findsOneWidget);
    });

    testWidgets('sin reservas muestra un mensaje', (t) async {
      await pumpScreen(t, const MyBookingsScreen(), PlayerApi(user: me));
      expect(find.textContaining('Aún no tienes reservas próximas'), findsOneWidget);
    });
  });

  group('avisos', () {
    List<AppNotification> notices() => [
          AppNotification(id: 'n1', title: 'Reserva confirmada', body: 'El dueño aprobó tu pago.', createdAt: DateTime.now().toUtc()),
          AppNotification(
              id: 'n2',
              title: 'Tu partido es pronto',
              body: 'Tu reserva comienza en 2 horas.',
              createdAt: DateTime.now().toUtc(),
              readAt: DateTime.now().toUtc()),
        ];

    testWidgets('lista los avisos con punto rojo solo en los no leídos', (t) async {
      await pumpScreen(t, const NotificationsScreen(embedded: true), PlayerApi(user: me, notices: notices()));
      expect(find.text('Avisos'), findsOneWidget);
      expect(find.text('Reserva confirmada'), findsOneWidget);
      expect(find.text('Tu partido es pronto'), findsOneWidget);
      final dots = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == const Color(0xFFD23B34) &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle);
      expect(dots, findsOneWidget);
    });

    testWidgets('Marcar leídas llama a la API', (t) async {
      final api = PlayerApi(user: me, notices: notices());
      await pumpScreen(t, const NotificationsScreen(embedded: true), api);
      await t.tap(find.text('Marcar leídas'));
      await t.pumpAndSettle();
      expect(api.markedAll, 1);
    });

    testWidgets('sin avisos', (t) async {
      await pumpScreen(t, const NotificationsScreen(embedded: true), PlayerApi(user: me));
      expect(find.text('No tienes notificaciones'), findsOneWidget);
    });
  });

  group('perfil', () {
    testWidgets('muestra iniciales, nombre, rol, correo confirmado y celular', (t) async {
      await pumpScreen(t, const ProfileScreen(embedded: true), PlayerApi(user: me));
      expect(find.text('AM'), findsOneWidget);
      expect(find.text('Alejandro Martínez'), findsNWidgets(2)); // tarjeta verde y fila Nombre
      expect(find.text('Jugador'), findsOneWidget);
      expect(find.text('Confirmado'), findsOneWidget);
      expect(find.text('+57 3001234567'), findsOneWidget);
      expect(find.text('Borrar mi cuenta'), findsOneWidget);
    });

    testWidgets('enlaces legales: términos, privacidad y soporte abren las páginas del servidor', (t) async {
      final opened = <Uri>[];
      await pumpScreen(t, const ProfileScreen(embedded: true), PlayerApi(user: me), opened: opened);
      for (final label in ['Términos y Condiciones', 'Política de privacidad', 'Soporte']) {
        await t.ensureVisible(find.text(label));
        await t.tap(find.text(label));
        await t.pump();
      }
      expect(opened.map((u) => u.path), ['/legal/terminos', '/legal/privacidad', '/legal/soporte']);
    });

    testWidgets('correo sin confirmar ofrece Reenviar', (t) async {
      final api = PlayerApi(user: const AppUser(id: 'u1', name: 'Ana Gómez', email: 'ana@correo.com', role: Role.player, phone: '3001234567'));
      await pumpScreen(t, const ProfileScreen(embedded: true), api);
      expect(find.text('Sin confirmar'), findsOneWidget);
      await t.tap(find.text('Reenviar'));
      await t.pumpAndSettle();
      expect(api.profileCalls, ['resend']);
    });

    testWidgets('cambiar nombre en una hoja', (t) async {
      final api = PlayerApi(user: me);
      await pumpScreen(t, const ProfileScreen(embedded: true), api);
      await t.tap(find.text('Nombre'));
      await t.pumpAndSettle();
      expect(find.text('Cambiar nombre'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'Alejandro Pérez');
      await t.tap(find.text('Guardar cambios'));
      await t.pumpAndSettle();
      expect(api.profileCalls, ['name=Alejandro Pérez phone=null']);
      expect(find.text('Datos actualizados'), findsOneWidget);
    });

    testWidgets('celular inválido muestra el error y no guarda', (t) async {
      final api = PlayerApi(user: me);
      await pumpScreen(t, const ProfileScreen(embedded: true), api);
      await t.tap(find.text('Celular'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), '12345');
      await t.tap(find.text('Guardar cambios'));
      await t.pumpAndSettle();
      expect(find.text('Celular de 10 dígitos que empiece por 3'), findsOneWidget);
      expect(api.profileCalls, isEmpty);
    });

    testWidgets('cambiar contraseña valida y envía las dos claves', (t) async {
      final api = PlayerApi(user: me);
      await pumpScreen(t, const ProfileScreen(embedded: true), api);
      await t.tap(find.text('Cambiar contraseña'));
      await t.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'clave-vieja');
      await t.enterText(fields.at(1), 'corta');
      await t.tap(find.text('Guardar cambios'));
      await t.pumpAndSettle();
      expect(find.text('Mínimo 8 caracteres'), findsWidgets);
      expect(api.profileCalls, isEmpty);
      await t.enterText(fields.at(1), 'clave-nueva-1');
      await t.tap(find.text('Guardar cambios'));
      await t.pumpAndSettle();
      expect(api.profileCalls, ['pw:clave-vieja>clave-nueva-1']);
    });

    testWidgets('borrar cuenta pide la contraseña en una hoja roja', (t) async {
      final api = PlayerApi(user: me);
      await pumpScreen(t, const ProfileScreen(embedded: true), api);
      await t.ensureVisible(find.text('Borrar mi cuenta'));
      await t.pumpAndSettle();
      await t.tap(find.text('Borrar mi cuenta'));
      await t.pumpAndSettle();
      expect(find.text('Eliminar definitivamente'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'mi-clave-123');
      await t.tap(find.text('Eliminar definitivamente'));
      await t.pumpAndSettle();
      expect(api.deleted, isTrue);
      expect(api.deletedWith, 'mi-clave-123');
    });
  });
}

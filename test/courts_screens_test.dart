import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golazo/core/format.dart';
import 'package:golazo/core/location.dart';
import 'package:golazo/data/golazo_api.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/booking/court_detail_screen.dart';
import 'package:golazo/features/player/courts_screen.dart';

Court mkCourt(String id, String name, String city,
        {bool covered = false, List<int> types = const [5], int price = 80000, bool deposit = false, int reviews = 0}) =>
    Court(
      id: id,
      name: name,
      city: city,
      address: 'Cra 7 # 10-20',
      covered: covered,
      types: types,
      pricePerHour: price,
      openHour: 8,
      closeHour: 23,
      requiresDeposit: deposit,
      depositPercent: 30,
      status: CourtStatus.active,
      lat: 4.7,
      lng: -74,
      description: 'Cancha sintética iluminada.',
      rating: reviews > 0 ? 4.5 : 0,
      reviewCount: reviews,
    );

class FakeApi extends Fake implements GolazoApi {
  FakeApi({this.user});
  final AppUser? user;

  final all = [
    mkCourt('1', 'La Bombonera', 'Bogotá', covered: true, types: [5, 7], price: 90000, deposit: true, reviews: 2),
    mkCourt('2', 'Golazo Arena', 'Bogotá', price: 70000),
    mkCourt('3', 'El Potrero', 'Medellín', covered: true, price: 100000),
  ];
  final lastFilters = <String, Object?>{};
  String? updatedPhone;

  @override
  Future<AppUser?> restore() async => user;

  @override
  Future<List<String>> cities() async => ['Bogotá', 'Medellín'];

  @override
  Future<List<Court>> courts({
    String? city,
    int? maxPrice,
    bool? covered,
    int? courtType,
    double? lat,
    double? lng,
    double? radiusKm,
    int limit = 50,
    int offset = 0,
  }) async {
    lastFilters
      ..['city'] = city
      ..['covered'] = covered
      ..['courtType'] = courtType
      ..['maxPrice'] = maxPrice
      ..['lat'] = lat;
    return all
        .where((c) =>
            (city == null || c.city == city) &&
            (covered == null || c.covered == covered) &&
            (courtType == null || c.types.contains(courtType)) &&
            (maxPrice == null || c.pricePerHour <= maxPrice))
        .toList();
  }

  @override
  Future<Court> court(String id) async => all.firstWhere((c) => c.id == id);

  @override
  Future<List<HourSlot>> availability(String courtId, DateTime coDay) async =>
      [for (var h = 8; h < 14; h++) HourSlot(h, h != 10)]; // 10:00 AM ocupada

  @override
  Future<List<Review>> reviews(String courtId) async => courtId != '1'
      ? []
      : [
          Review(id: 'r1', stars: 5, createdAt: DateTime.now().subtract(const Duration(days: 3)), authorName: 'Laura M.', body: 'Impecable.'),
          Review(id: 'r2', stars: 4, createdAt: DateTime.now().subtract(const Duration(days: 20)), authorName: 'Andrés P.', body: 'Muy buena.'),
        ];

  final reports = <String>[];

  @override
  Future<void> reportReview(String reviewId, {String? reason}) async => reports.add('$reviewId:$reason');

  // ---- Reservas y pago del anticipo ----
  int created = 0;
  int bookingFetches = 0;
  final uploads = <String>[];
  Booking current = Booking(
    id: 'b1',
    courtId: '1',
    courtName: 'La Bombonera',
    startAt: DateTime.utc(2026, 10, 20, 20),
    hours: 2,
    total: 180000,
    deposit: 54000,
    lastMinute: false,
    status: BookingStatus.pendingPayment,
    cancellable: true,
    payBy: DateTime.now().add(const Duration(minutes: 29, seconds: 42)),
    paymentMethods: const [PaymentMethod(label: 'Nequi', account: '300 456 7890', holder: 'Carlos Rodríguez')],
  );

  @override
  Future<Booking> createBooking(String courtId, DateTime startAt, int hours) async {
    created++;
    return current;
  }

  @override
  Future<Booking> booking(String id) async {
    bookingFetches++;
    return current;
  }

  @override
  Future<void> uploadBookingProof(String bookingId, Uint8List bytes, String filename) async {
    uploads.add(filename);
    current = Booking(
      id: current.id,
      courtId: current.courtId,
      courtName: current.courtName,
      startAt: current.startAt,
      hours: current.hours,
      total: current.total,
      deposit: current.deposit,
      lastMinute: current.lastMinute,
      status: BookingStatus.pendingReview,
      cancellable: true,
    );
  }

  @override
  Future<List<Booking>> myBookings() async => [];

  @override
  Future<AppUser> updateProfile({String? name, String? phone}) async {
    updatedPhone = phone;
    return AppUser(id: 'u1', name: 'Ana', role: Role.player, phone: phone);
  }
}

const withPhone = AppUser(id: 'u1', name: 'Ana', role: Role.player, phone: '3001234567');
const noPhone = AppUser(id: 'u1', name: 'Ana', role: Role.player);

/// Fila horizontal de chips de filtro (el campo de búsqueda también tiene un Scrollable horizontal).
final _chipsRow = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal);
final _chipScrollable = find.descendant(of: _chipsRow, matching: find.byType(Scrollable));

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pumpScreen(WidgetTester t, Widget screen, FakeApi api, {Locate? locate}) async {
  tallPhone(t);
  await t.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api),
      if (locate != null) locationProvider.overrideWithValue(locate),
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

  group('lista de canchas', () {
    testWidgets('muestra las canchas y el contador', (t) async {
      await pumpScreen(t, const CourtsScreen(), FakeApi(user: withPhone));
      expect(find.text('Encuentra tu cancha'), findsOneWidget);
      expect(find.text('3 canchas disponibles'), findsOneWidget);
      expect(find.text('La Bombonera'), findsOneWidget);
      expect(find.text('Fútbol 5 · 7'), findsOneWidget); // ofrece dos tipos
      expect(find.text('Anticipo 30 %'), findsOneWidget);
      expect(find.textContaining(r'$90.000', findRichText: true), findsOneWidget);
    });

    testWidgets('la búsqueda ignora mayúsculas y tildes', (t) async {
      await pumpScreen(t, const CourtsScreen(), FakeApi(user: withPhone));
      await t.enterText(find.byType(TextField), 'medellin');
      await t.pump();
      expect(find.text('1 cancha disponible'), findsOneWidget);
      expect(find.text('El Potrero'), findsOneWidget);
      expect(find.text('La Bombonera'), findsNothing);
    });

    testWidgets('el chip Techada filtra en el servidor', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpScreen(t, const CourtsScreen(), api);
      final techada = find.descendant(of: _chipsRow, matching: find.text('Techada'));
      await t.scrollUntilVisible(techada, 150, scrollable: _chipScrollable);
      await t.ensureVisible(techada);
      await t.pumpAndSettle();
      await t.tap(techada);
      await t.pumpAndSettle();
      expect(api.lastFilters['covered'], isTrue);
      expect(find.text('2 canchas disponibles'), findsOneWidget);
      expect(find.text('Golazo Arena'), findsNothing);
    });

    testWidgets('filtrar por tipo de cancha', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpScreen(t, const CourtsScreen(), api);
      await t.scrollUntilVisible(find.text('Tipo'), 150, scrollable: _chipScrollable);
      await t.ensureVisible(find.text('Tipo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tipo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Fútbol 7').last);
      await t.pumpAndSettle();
      expect(api.lastFilters['courtType'], 7);
      expect(find.text('1 cancha disponible'), findsOneWidget);
    });

    testWidgets('el precio se elige en una hoja inferior', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpScreen(t, const CourtsScreen(), api);
      await t.scrollUntilVisible(find.text('Sin límite de precio'), 150, scrollable: _chipScrollable);
      await t.ensureVisible(find.text('Sin límite de precio'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sin límite de precio'));
      await t.pumpAndSettle();
      expect(find.text('Precio por hora'), findsOneWidget);
      expect(find.text(r'Hasta $120.000 por hora'), findsOneWidget);

      await t.tap(find.text(r'Hasta $80.000 por hora'));
      await t.pumpAndSettle();
      expect(api.lastFilters['maxPrice'], 80000);
      expect(find.text(r'Hasta $80 mil'), findsOneWidget);
      expect(find.text('1 cancha disponible'), findsOneWidget); // solo Golazo Arena ($70.000)

      // Volver a abrir y quitar el límite.
      await t.ensureVisible(find.text(r'Hasta $80 mil'));
      await t.pumpAndSettle();
      await t.tap(find.text(r'Hasta $80 mil'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sin límite'));
      await t.pumpAndSettle();
      expect(api.lastFilters['maxPrice'], isNull);
      expect(find.text('3 canchas disponibles'), findsOneWidget);
    });

    testWidgets('Techada ✓ y la píldora de anticipo dentro de la tarjeta', (t) async {
      await pumpScreen(t, const CourtsScreen(), FakeApi(user: withPhone));
      expect(find.text('Anticipo 30 %'), findsOneWidget);
      final techada = find.descendant(of: _chipsRow, matching: find.text('Techada'));
      await t.scrollUntilVisible(techada, 150, scrollable: _chipScrollable);
      await t.ensureVisible(techada);
      await t.pumpAndSettle();
      await t.tap(techada);
      await t.pumpAndSettle();
      expect(find.text('Techada ✓'), findsOneWidget);
    });

    testWidgets('Cerca de mí: muestra Ubicando… y luego filtra por cercanía', (t) async {
      final api = FakeApi(user: withPhone);
      final gps = Completer<({double lat, double lng})>();
      await pumpScreen(t, const CourtsScreen(), api, locate: () => gps.future);
      await t.tap(find.text('Cerca de mí'));
      await t.pump();
      expect(find.text('Ubicando…'), findsOneWidget);
      gps.complete((lat: 4.7, lng: -74.0));
      await t.pumpAndSettle();
      expect(find.text('Cerca de mí'), findsOneWidget);
      expect(api.lastFilters['lat'], 4.7);
    });

    testWidgets('Cerca de mí sin permiso: avisa que active la ubicación', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpScreen(t, const CourtsScreen(), api, locate: () async => throw const LocationUnavailable());
      await t.tap(find.text('Cerca de mí'));
      await t.pumpAndSettle();
      expect(find.text('Activa la ubicación para mostrar canchas cercanas.'), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
      expect(api.lastFilters['lat'], isNull);
      await t.tap(find.text('Entendido'));
      await t.pumpAndSettle();
      expect(find.text('Activa la ubicación para mostrar canchas cercanas.'), findsNothing);
    });

    testWidgets('sin resultados ofrece limpiar la búsqueda', (t) async {
      await pumpScreen(t, const CourtsScreen(), FakeApi(user: withPhone));
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pump();
      expect(find.text('No encontramos canchas con esos filtros'), findsOneWidget);
      await t.tap(find.text('Limpiar búsqueda'));
      await t.pumpAndSettle();
      expect(find.text('3 canchas disponibles'), findsOneWidget);
    });
  });

  group('detalle de cancha', () {
    testWidgets('muestra los datos de la cancha y las reseñas', (t) async {
      await pumpScreen(t, const CourtDetailScreen(courtId: '1'), FakeApi(user: withPhone));
      expect(find.text('La Bombonera'), findsOneWidget);
      expect(find.text('Fútbol 5 · 7'), findsWidgets);
      expect(find.text('Anticipo 30 %'), findsOneWidget);
      expect(find.text('Sobre la cancha'), findsOneWidget);
      expect(find.text('8:00 AM – 11:00 PM'), findsOneWidget);
      expect(find.text('2 reseñas'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Laura M.'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Hace 3 días'), findsOneWidget);
    });

    testWidgets('reportar una reseña: elige el motivo en una hoja y se envía con ese motivo', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpScreen(t, const CourtDetailScreen(courtId: '1'), api);
      await t.scrollUntilVisible(find.text('Laura M.'), 300, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.text('Reportar').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Reportar').first);
      await t.pumpAndSettle();
      expect(find.text('Reportar reseña'), findsOneWidget);
      expect(find.text('Cuéntanos por qué esta reseña debería revisarse.'), findsOneWidget);
      for (final m in ['Lenguaje ofensivo', 'Información falsa', 'Contenido no relacionado', 'Otro motivo']) {
        expect(find.text(m), findsOneWidget);
      }
      await t.tap(find.text('Información falsa'));
      await t.pumpAndSettle();
      expect(api.reports, ['r1:Información falsa']);
      expect(find.text('Gracias, la revisaremos'), findsOneWidget);
      expect(find.text('Reportar reseña'), findsNothing);
    });

    testWidgets('reportar una reseña: Cancelar no envía nada', (t) async {
      final api = FakeApi(user: withPhone);
      await pumpScreen(t, const CourtDetailScreen(courtId: '1'), api);
      await t.scrollUntilVisible(find.text('Laura M.'), 300, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.text('Reportar').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Reportar').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(api.reports, isEmpty);
      expect(find.text('Reportar reseña'), findsNothing);
    });

    testWidgets('elegir horas: total y límite de 4 horas seguidas', (t) async {
      await pumpScreen(t, const CourtDetailScreen(courtId: '2'), FakeApi(user: withPhone));
      expect(find.text('Selecciona una hora'), findsOneWidget);
      final reservar = find.widgetWithText(FilledButton, 'Reservar');
      expect(t.widget<FilledButton>(reservar).onPressed, isNull);

      await t.tap(find.text('8:00 AM'));
      await t.pump();
      await t.tap(find.text('9:00 AM'));
      await t.pump();
      expect(find.textContaining('2 h'), findsOneWidget); // con o sin anticipo (depende de la hora actual)
      expect(find.textContaining(r'$140.000', findRichText: true), findsOneWidget); // 2 x 70.000
      expect(t.widget<FilledButton>(reservar).onPressed, isNotNull);

      // La hora ocupada (10:00 AM) no se puede elegir.
      await t.tap(find.text('10:00 AM'), warnIfMissed: false);
      await t.pump();
      expect(find.textContaining('2 h'), findsOneWidget);
    });

    testWidgets('sin celular guardado pide el celular antes de reservar', (t) async {
      await pumpScreen(t, const CourtDetailScreen(courtId: '2'), FakeApi(user: noPhone));
      await t.tap(find.text('8:00 AM'));
      await t.pump();
      final reservar = find.widgetWithText(FilledButton, 'Reservar');
      await t.scrollUntilVisible(find.text('Tu celular de contacto'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Tu celular de contacto'), findsOneWidget);
      expect(t.widget<FilledButton>(reservar).onPressed, isNull);

      final phone = find.descendant(of: find.byType(Form), matching: find.byType(TextFormField));
      await t.enterText(phone, '12345');
      await t.pump();
      expect(find.text('Celular de 10 dígitos que empiece por 3'), findsOneWidget);
      expect(t.widget<FilledButton>(reservar).onPressed, isNull);

      await t.enterText(phone, '3001234567');
      await t.pump();
      expect(t.widget<FilledButton>(reservar).onPressed, isNotNull);
    });

    testWidgets('con celular guardado no muestra el campo', (t) async {
      await pumpScreen(t, const CourtDetailScreen(courtId: '2'), FakeApi(user: withPhone));
      expect(find.text('Tu celular de contacto'), findsNothing);
    });
  });

  test('agoLabel', () {
    final now = DateTime.utc(2026, 10, 14, 18);
    expect(agoLabel(now, now), 'Hoy');
    expect(agoLabel(now.subtract(const Duration(days: 1)), now), 'Ayer');
    expect(agoLabel(now.subtract(const Duration(days: 3)), now), 'Hace 3 días');
    expect(agoLabel(now.subtract(const Duration(days: 14)), now), 'Hace 2 semanas');
    expect(agoLabel(now.subtract(const Duration(days: 65)), now), 'Hace 2 meses');
  });

  test('Court.fromJson lee el tipo y usa Fútbol 5 si falta', () {
    Map<String, dynamic> json([Object? type]) => {
          'id': 'c1', 'name': 'X', 'city': 'Cali', 'address': 'Av 1', 'covered': false,
          'pricePerHour': 50000, 'openHour': 8, 'closeHour': 22, 'requiresDeposit': false,
          'depositPercent': 30, 'status': 'active', 'lat': 3.4, 'lng': -76.5,
          'courtType': ?type,
        };
    expect(Court.fromJson(json(7)).types, [7]); // servidor antiguo: solo courtType
    expect(Court.fromJson(json()).types, [5]);
    expect(Court.fromJson({...json(), 'courtTypes': [7, 5]}).types, [5, 7]); // ordenados
    expect(courtTypeLabel(11), 'Fútbol 11');
    expect(courtTypesLabel([7, 5]), 'Fútbol 5 · 7');
  });
}

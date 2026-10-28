import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golazo/core/api/api_client.dart';
import 'package:golazo/core/widgets/ui.dart';
import 'package:golazo/data/models.dart';
import 'package:golazo/data/providers.dart';
import 'package:golazo/features/admin/admin_chat_tab.dart';
import 'package:golazo/features/chat/chat_screen.dart';
import 'package:golazo/features/chat/chats_screen.dart';

import 'courts_screens_test.dart' show FakeApi;
import 'owner_screens_test.dart' show png;

const player = AppUser(id: 'u1', name: 'Pablo Pérez', email: 'pablo@correo.com', role: Role.player, phone: '3001234567', emailVerified: true);
const ownerUser = AppUser(id: 'o1', name: 'Carlos Rodríguez', email: 'carlos@correo.com', role: Role.owner, phone: '3004567890', emailVerified: true);
const adminUser = AppUser(id: 'a1', name: 'Admin', email: 'admin@golazo.co', role: Role.admin, emailVerified: true);

ChatThread mkThread(String id,
        {bool open = true, int unread = 0, String? last = 'Hola, ¿hay balones?', bool support = false, bool blocked = false}) =>
    ChatThread(
      id: id,
      kind: support ? 'support' : 'court',
      courtId: support ? null : 'c1',
      courtName: support ? null : 'La Bombonera 5',
      participantId: 'u1',
      participantName: 'Pablo Pérez',
      ownerId: support ? null : 'o1',
      ownerName: support ? null : 'Carlos Rodríguez',
      lastMessageAt: DateTime.now().toUtc(),
      lastBody: last,
      lastSenderId: 'o1',
      unread: unread,
      open: open,
      blocked: blocked,
    );

ChatMessage mkMsg(int seq, String sender, String? body, {bool image = false, bool hidden = false, bool support = false}) => ChatMessage(
      id: 'm$seq',
      seq: seq,
      senderId: sender,
      senderName: sender == 'u1' ? 'Pablo Pérez' : 'Carlos Rodríguez',
      fromSupport: support,
      body: body,
      hasImage: image,
      hidden: hidden,
      createdAt: DateTime.now().toUtc().subtract(Duration(minutes: 30 - seq)),
    );

class ChatApi extends FakeApi {
  ChatApi({super.user = player, List<ChatThread>? threads, List<ChatMessage>? messages, this.open = true})
      : threadList = threads ?? [],
        messageList = messages ?? [];

  List<ChatThread> threadList;
  List<ChatMessage> messageList;
  bool open;
  bool blocked = false;
  final calls = <String>[];

  List<SupportInboxItem> inbox = [];
  List<AdminChatThread> courtChats = [];
  List<ChatReport> chatReports = [];

  @override
  Future<List<ChatThread>> chatThreads() async => threadList;

  @override
  Future<ChatThread> openSupportChat() async {
    calls.add('openSupport');
    return mkThread('s1', support: true, last: null);
  }

  @override
  Future<ChatThread> openBookingChat(String bookingId) async {
    calls.add('openBooking:$bookingId');
    return mkThread('t1');
  }

  @override
  Future<ChatPage> chatMessages(String threadId, {int? after, bool admin = false}) async {
    calls.add('msgs:${after ?? '-'}:${admin ? 'admin' : 'user'}');
    final list = after == null ? messageList : messageList.where((m) => m.seq > after).toList();
    return ChatPage(open: open, blocked: blocked, messages: list);
  }

  @override
  Future<ChatMessage> sendChatMessage(String threadId, {String? body, Uint8List? image, String? filename, bool admin = false}) async {
    if (!open) throw const ApiException('Este chat está cerrado', code: 'CHAT_CLOSED', status: 409);
    calls.add('send:${body ?? '-'}:${image == null ? '-' : filename}:${admin ? 'admin' : 'user'}');
    final m = mkMsg(messageList.length + 1, admin ? 'a1' : 'u1', body, image: image != null, support: admin);
    messageList = [...messageList, m];
    return m;
  }

  @override
  Future<Uint8List> chatImage(String messageId) async => Uint8List.fromList(png);

  @override
  Future<void> reportChatMessage(String messageId, {String? reason}) async => calls.add('report:$messageId:${reason ?? ''}');

  @override
  Future<void> blockChatUser(String userId) async {
    calls.add('block:$userId');
    blocked = true;
    open = false;
  }

  @override
  Future<void> unblockChatUser(String userId) async {
    calls.add('unblock:$userId');
    blocked = false;
    open = true;
  }

  @override
  Future<List<SupportInboxItem>> adminSupportInbox() async => inbox;

  @override
  Future<List<AdminChatThread>> adminCourtChats({String? search}) async {
    calls.add('courtChats:${search ?? ''}');
    return courtChats;
  }

  @override
  Future<List<ChatReport>> adminChatReports() async => chatReports;

  @override
  Future<void> resolveChatReport(String id) async {
    calls.add('resolve:$id');
    chatReports = chatReports.where((r) => r.id != id).toList();
  }

  @override
  Future<void> hideChatMessage(String messageId) async {
    calls.add('hide:$messageId');
    chatReports = chatReports.where((r) => r.messageId != messageId).toList();
  }
}

void tallPhone(WidgetTester t) {
  t.view.physicalSize = const Size(411, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Pantalla dentro de un router mínimo (la pestaña abre '/chat/:id' al tocar un chat).
Future<void> pumpRouted(WidgetTester t, ChatApi api, Widget home, {Duration poll = const Duration(seconds: 4)}) async {
  tallPhone(t);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(
        path: '/chat/:id',
        builder: (_, s) => ChatScreen(threadId: s.pathParameters['id']!, args: s.extra as ChatArgs?, pollEvery: poll)),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api),
      pickImageProvider.overrideWithValue((_) async => PickedImage(Uint8List.fromList(png), 'foto.jpg')),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await t.pumpAndSettle();
}

Future<void> pumpChat(WidgetTester t, ChatApi api,
    {ChatArgs args = const ChatArgs(title: 'La Bombonera 5', subtitle: 'Dueño: Carlos Rodríguez', peerId: 'o1'),
    Duration poll = const Duration(seconds: 4)}) async {
  tallPhone(t);
  await t.pumpWidget(ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api),
      pickImageProvider.overrideWithValue((_) async => PickedImage(Uint8List.fromList(png), 'foto.jpg')),
    ],
    child: MaterialApp(home: ChatScreen(threadId: 't1', args: args, pollEvery: poll)),
  ));
  await t.pumpAndSettle();
}

/// Desmonta la pantalla para cancelar el temporizador de consulta antes de terminar la prueba.
Future<void> close(WidgetTester t) async => t.pumpWidget(const SizedBox());

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await manrope.load();
  });

  group('lista de mensajes', () {
    testWidgets('jugador: soporte fijo arriba y el chat con la cancha, con no leídos y candado si está cerrado', (t) async {
      final api = ChatApi(threads: [mkThread('t1', unread: 2), mkThread('t2', open: false, last: 'Gracias')]);
      await pumpRouted(t, api, const ChatsScreen());
      expect(find.text('Mensajes'), findsOneWidget);
      expect(find.text('Soporte Golazo'), findsOneWidget);
      expect(find.text('Escríbenos tus dudas'), findsOneWidget);
      expect(find.text('La Bombonera 5'), findsNWidgets(2));
      expect(find.text('Hola, ¿hay balones?'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // no leídos
      expect(find.byIcon(Icons.lock_outline), findsOneWidget); // el cerrado
    });

    testWidgets('dueño: ve el nombre del jugador y la cancha', (t) async {
      final api = ChatApi(user: ownerUser, threads: [mkThread('t1')]);
      await pumpRouted(t, api, const ChatsScreen());
      expect(find.text('Pablo Pérez'), findsOneWidget);
      expect(find.text('La Bombonera 5'), findsOneWidget);
    });

    testWidgets('sin chats de cancha explica cuándo aparecen', (t) async {
      await pumpRouted(t, ChatApi(), const ChatsScreen());
      expect(find.textContaining('Cuando reserves una cancha'), findsOneWidget);
    });

    testWidgets('tocar un chat lo abre con sus mensajes', (t) async {
      final api = ChatApi(threads: [mkThread('t1')], messages: [mkMsg(1, 'o1', 'Sí, tenemos balones')]);
      await pumpRouted(t, api, const ChatsScreen());
      await t.tap(find.text('La Bombonera 5'));
      await t.pumpAndSettle();
      expect(find.text('Sí, tenemos balones'), findsOneWidget);
      expect(find.text('DUEÑO: CARLOS RODRÍGUEZ'), findsOneWidget); // el subtítulo va en mayúsculas
      await close(t);
    });

    testWidgets('soporte: sin hilo previo lo crea y entra', (t) async {
      final api = ChatApi();
      await pumpRouted(t, api, const ChatsScreen());
      await t.tap(find.text('Soporte Golazo'));
      await t.pumpAndSettle();
      expect(api.calls, contains('openSupport'));
      expect(find.text('Todavía no hay mensajes.\nEscribe el primero.'), findsOneWidget);
      await close(t);
    });
  });

  group('conversación', () {
    testWidgets('muestra los mensajes de los dos lados y el composer', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'u1', 'Hola, ¿hay balones?'), mkMsg(2, 'o1', 'Sí, los dejo en la entrada')]);
      await pumpChat(t, api);
      expect(find.text('Hola, ¿hay balones?'), findsOneWidget);
      expect(find.text('Sí, los dejo en la entrada'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // Mis mensajes a la derecha, los del otro a la izquierda.
      expect(t.getTopLeft(find.text('Hola, ¿hay balones?')).dx, greaterThan(t.getTopLeft(find.text('Sí, los dejo en la entrada')).dx));
      await close(t);
    });

    testWidgets('enviar: agrega el mensaje, limpia el campo y no envía vacíos', (t) async {
      final api = ChatApi();
      await pumpChat(t, api);
      await t.tap(find.byTooltip('Enviar'));
      await t.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('send')), isEmpty);
      await t.enterText(find.byType(TextField), '  Llego en 10 minutos  ');
      await t.tap(find.byTooltip('Enviar'));
      await t.pumpAndSettle();
      expect(api.calls, contains('send:Llego en 10 minutos:-:user'));
      expect(find.text('Llego en 10 minutos'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      await close(t);
    });

    testWidgets('adjuntar foto: se ve el archivo y se envía con el texto', (t) async {
      final api = ChatApi();
      await pumpChat(t, api);
      await t.tap(find.byTooltip('Adjuntar foto'));
      await t.pumpAndSettle();
      expect(find.text('foto.jpg'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Mira el balón');
      await t.tap(find.byTooltip('Enviar'));
      await t.pumpAndSettle();
      expect(api.calls, contains('send:Mira el balón:foto.jpg:user'));
      expect(find.byType(ChatImage), findsOneWidget);
      expect(find.text('foto.jpg'), findsNothing); // el adjunto ya se envió
      await close(t);
    });

    testWidgets('los mensajes nuevos llegan solos con la consulta periódica', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'u1', 'Hola')]);
      await pumpChat(t, api, poll: const Duration(milliseconds: 200));
      expect(find.text('Hola'), findsOneWidget);
      api.messageList = [...api.messageList, mkMsg(2, 'o1', 'Ya te abrimos')];
      await t.pump(const Duration(milliseconds: 250));
      await t.pump();
      expect(find.text('Ya te abrimos'), findsOneWidget);
      // Pidió solo lo posterior al último que ya tenía.
      expect(api.calls, contains('msgs:1:user'));
      await close(t);
    });

    testWidgets('chat cerrado: sin campo de texto y con el aviso', (t) async {
      final api = ChatApi(open: false, messages: [mkMsg(1, 'u1', 'Gracias por todo')]);
      await pumpChat(t, api);
      expect(find.text('Gracias por todo'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Chat cerrado'), findsOneWidget);
      await close(t);
    });

    testWidgets('si el servidor lo cerró mientras escribía, pasa a cerrado', (t) async {
      final api = ChatApi();
      await pumpChat(t, api);
      api.open = false;
      await t.enterText(find.byType(TextField), 'Hola');
      await t.tap(find.byTooltip('Enviar'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Chat cerrado'), findsOneWidget);
      await close(t);
    });

    testWidgets('mensaje oculto por moderación', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'o1', null, hidden: true)]);
      await pumpChat(t, api);
      expect(find.text('Mensaje oculto por moderación'), findsOneWidget);
      await close(t);
    });

    testWidgets('mensajes de soporte se marcan como «Soporte Golazo»', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'a1', 'Hola, ya lo revisamos', support: true)]);
      await pumpChat(t, api, args: const ChatArgs(title: 'Soporte Golazo'));
      expect(find.text('Soporte Golazo'), findsNWidgets(2)); // título y etiqueta del mensaje
      await close(t);
    });
  });

  group('moderación', () {
    testWidgets('mantener pulsado un mensaje ajeno permite reportarlo', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'o1', 'Mensaje ofensivo')]);
      await pumpChat(t, api);
      await t.longPress(find.text('Mensaje ofensivo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reportar mensaje'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Insultos');
      await t.tap(find.widgetWithText(FilledButton, 'Enviar reporte'));
      await t.pumpAndSettle();
      expect(api.calls, contains('report:m1:Insultos'));
      expect(find.text('Gracias, lo revisaremos'), findsOneWidget);
      await close(t);
    });

    testWidgets('no se puede reportar un mensaje propio', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'u1', 'Mi mensaje')]);
      await pumpChat(t, api);
      await t.longPress(find.text('Mi mensaje'));
      await t.pumpAndSettle();
      expect(find.text('Reportar mensaje'), findsNothing);
      await close(t);
    });

    testWidgets('bloquear y desbloquear desde el menú', (t) async {
      final api = ChatApi(messages: [mkMsg(1, 'o1', 'Hola')]);
      await pumpChat(t, api);
      await t.tap(find.byTooltip('Más opciones'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bloquear'));
      await t.pumpAndSettle();
      expect(find.text('¿Bloquear a esta persona?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Bloquear'));
      await t.pumpAndSettle();
      expect(api.calls, contains('block:o1'));
      expect(find.textContaining('Bloqueaste a esta persona'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      // Desbloquear
      await t.tap(find.byTooltip('Más opciones'));
      await t.pumpAndSettle();
      await t.tap(find.text('Desbloquear'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Desbloquear'));
      await t.pumpAndSettle();
      expect(api.calls, contains('unblock:o1'));
      expect(find.byType(TextField), findsOneWidget);
      await close(t);
    });

    testWidgets('soporte no tiene menú de bloqueo', (t) async {
      await pumpChat(t, ChatApi(), args: const ChatArgs(title: 'Soporte Golazo'));
      expect(find.byTooltip('Más opciones'), findsNothing);
      await close(t);
    });
  });

  group('administrador', () {
    testWidgets('chat de cancha visto por el admin: solo lectura con el nombre de quien escribe', (t) async {
      final api = ChatApi(user: adminUser, messages: [mkMsg(1, 'u1', 'Hola dueño')]);
      await pumpChat(t, api, args: const ChatArgs(title: 'La Bombonera 5', subtitle: 'Pablo ↔ Carlos', admin: true, readOnly: true));
      expect(find.text('Hola dueño'), findsOneWidget);
      expect(find.text('Pablo Pérez'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Solo lectura (moderación).'), findsOneWidget);
      expect(api.calls, contains('msgs:-:admin'));
      await close(t);
    });

    testWidgets('chat de soporte: el admin responde con las rutas de administración', (t) async {
      final api = ChatApi(user: adminUser, messages: [mkMsg(1, 'u1', 'Necesito ayuda')]);
      await pumpChat(t, api, args: const ChatArgs(title: 'Pablo Pérez', subtitle: 'Soporte · jugador', admin: true));
      await t.enterText(find.byType(TextField), 'Ya te ayudamos');
      await t.tap(find.byTooltip('Enviar'));
      await t.pumpAndSettle();
      expect(api.calls, contains('send:Ya te ayudamos:-:admin'));
      await close(t);
    });

    testWidgets('bandeja: los que esperan respuesta llevan la etiqueta y abren el chat', (t) async {
      final api = ChatApi(user: adminUser, messages: [mkMsg(1, 'u1', 'Necesito ayuda')])
        ..inbox = [
          SupportInboxItem(
              id: 's1', participantName: 'Pablo Pérez', participantEmail: 'pablo@correo.com', participantRole: 'player',
              lastBody: 'Necesito ayuda', lastMessageAt: DateTime.now().toUtc(), needsReply: true),
          SupportInboxItem(id: 's2', participantName: 'Carlos R.', participantRole: 'owner', lastBody: 'Gracias', needsReply: false),
        ];
      await pumpRouted(t, api, const AdminChatTab());
      expect(find.text('Soporte'), findsWidgets);
      expect(find.text('Responder'), findsOneWidget);
      expect(find.text('Jugador · pablo@correo.com'), findsOneWidget);
      await t.tap(find.text('Pablo Pérez'));
      await t.pumpAndSettle();
      expect(find.text('Necesito ayuda'), findsWidgets);
      expect(api.calls, contains('msgs:-:admin'));
      await close(t);
    });

    testWidgets('chats de canchas: lista, busca y abre en solo lectura', (t) async {
      final api = ChatApi(user: adminUser, messages: [mkMsg(1, 'u1', 'Hola dueño')])
        ..courtChats = [
          const AdminChatThread(id: 't1', courtName: 'La Bombonera 5', playerName: 'Pablo', ownerName: 'Carlos', messages: 7, lastBody: 'Hola dueño'),
        ];
      await pumpRouted(t, api, const AdminChatTab());
      await t.tap(find.text('Chats'));
      await t.pumpAndSettle();
      expect(find.text('La Bombonera 5'), findsOneWidget);
      expect(find.text('Pablo ↔ Carlos · 7 mensajes'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Bombonera');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(api.calls, contains('courtChats:Bombonera'));
      await t.tap(find.text('La Bombonera 5'));
      await t.pumpAndSettle();
      expect(find.text('Solo lectura (moderación).'), findsOneWidget);
      await close(t);
    });

    testWidgets('reportes: ocultar el mensaje y descartar', (t) async {
      final api = ChatApi(user: adminUser)
        ..chatReports = [
          ChatReport(
              id: 'r1', messageId: 'm9', threadId: 't1', senderName: 'Pablo', reporterName: 'Carlos',
              reason: 'Insultos', body: 'Mensaje feo', courtName: 'La Bombonera 5', createdAt: DateTime.now().toUtc()),
          ChatReport(id: 'r2', messageId: 'm10', threadId: 't1', senderName: 'Pablo', reporterName: 'Carlos', body: 'Otro', createdAt: DateTime.now().toUtc()),
        ];
      await pumpRouted(t, api, const AdminChatTab());
      await t.tap(find.text('Reportes'));
      await t.pumpAndSettle();
      expect(find.text('Mensaje feo'), findsOneWidget);
      expect(find.text('Motivo: Insultos'), findsOneWidget);
      await t.tap(find.text('Ocultar mensaje').first);
      await t.pumpAndSettle();
      expect(find.text('¿Ocultar el mensaje?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Ocultar mensaje').last);
      await t.pumpAndSettle();
      expect(api.calls, contains('hide:m9'));
      await t.tap(find.text('Descartar'));
      await t.pumpAndSettle();
      expect(api.calls, contains('resolve:r2'));
      expect(find.text('No hay mensajes reportados.'), findsOneWidget);
    });
  });
}

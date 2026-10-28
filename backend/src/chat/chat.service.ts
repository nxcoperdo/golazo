import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { AuthUser } from '../auth/auth.guard.js';
import { Db } from '../db/db.service.js';
import { PushService } from '../notifications/push.service.js';
import { StorageService } from '../storage/storage.service.js';
import { LIVE_BOOKING_STATUSES, cleanBody, isChatOpen, preview } from './chat.rules.js';

const LIVE = LIVE_BOOKING_STATUSES.map((s) => `'${s}'`).join(',');

/** Reserva viva del jugador en la cancha del hilo / bloqueo entre las dos partes. */
const HAS_LIVE = `EXISTS (SELECT 1 FROM bookings b WHERE b.court_id = t.court_id AND b.player_id = t.participant_id
    AND NOT b.owner_block AND b.status IN (${LIVE}) AND b.end_at > now())`;
const IS_BLOCKED = `EXISTS (SELECT 1 FROM chat_blocks k WHERE (k.blocker_id = t.participant_id AND k.blocked_id = c.owner_id)
    OR (k.blocker_id = c.owner_id AND k.blocked_id = t.participant_id))`;

const THREAD_FROM = `
  FROM chat_threads t
  LEFT JOIN courts c ON c.id = t.court_id
  LEFT JOIN users ou ON ou.id = c.owner_id
  JOIN users pu ON pu.id = t.participant_id
  LEFT JOIN LATERAL (
    SELECT body, image_path, sender_id FROM chat_messages
    WHERE thread_id = t.id AND hidden_at IS NULL ORDER BY seq DESC LIMIT 1) lm ON true`;

/** $1 = quien consulta (para los no leídos). */
const THREAD_SELECT = `
  t.id, t.kind, t.court_id AS "courtId", c.name AS "courtName",
  t.participant_id AS "participantId", pu.name AS "participantName", pu.role AS "participantRole",
  c.owner_id AS "ownerId", ou.name AS "ownerName",
  t.last_message_at AS "lastMessageAt",
  lm.body AS "lastBody", (lm.image_path IS NOT NULL) AS "lastHasImage", lm.sender_id AS "lastSenderId",
  (t.kind = 'court' AND ${HAS_LIVE}) AS "hasLiveBooking",
  (t.kind = 'court' AND ${IS_BLOCKED}) AS "blocked",
  (SELECT COUNT(*)::int FROM chat_messages m
    WHERE m.thread_id = t.id AND m.sender_id <> $1 AND m.hidden_at IS NULL
      AND m.seq > COALESCE((SELECT r.last_seq FROM chat_reads r WHERE r.thread_id = t.id AND r.user_id = $1), 0)) AS unread`;

interface ThreadRow {
  id: string;
  kind: 'court' | 'support';
  courtId: string | null;
  courtName: string | null;
  participantId: string;
  participantName: string;
  participantRole: string;
  ownerId: string | null;
  ownerName: string | null;
  lastMessageAt: Date | null;
  lastBody: string | null;
  lastHasImage: boolean | null;
  lastSenderId: string | null;
  hasLiveBooking: boolean;
  blocked: boolean;
  unread: number;
}

interface Access {
  id: string;
  kind: 'court' | 'support';
  participantId: string;
  ownerId: string | null;
  isParticipant: boolean;
  isOwner: boolean;
  isAdmin: boolean;
}

const MSG_SELECT = `
  m.id, m.seq::float8 AS seq, m.sender_id AS "senderId", u.name AS "senderName", (u.role = 'admin') AS "fromSupport",
  CASE WHEN m.hidden_at IS NOT NULL AND NOT $ADMIN THEN NULL ELSE m.body END AS body,
  (m.image_path IS NOT NULL AND (m.hidden_at IS NULL OR $ADMIN)) AS "hasImage",
  (m.hidden_at IS NOT NULL) AS hidden, m.created_at AS "createdAt"`;

@Injectable()
export class ChatService {
  private readonly log = new Logger(ChatService.name);

  constructor(
    private readonly db: Db,
    private readonly push: PushService,
    private readonly storage: StorageService,
  ) {}

  // ---------- Hilos ----------

  private toThread(r: ThreadRow) {
    const { hasLiveBooking, ...rest } = r;
    return {
      ...rest,
      lastBody: r.lastBody ? preview(r.lastBody, false) : null,
      open: isChatOpen({ kind: r.kind, hasLiveBooking, blocked: r.blocked }),
    };
  }

  /** Mis hilos: como jugador, como dueño de la cancha y mi hilo de soporte. */
  async listThreads(user: AuthUser) {
    const { rows } = await this.db.query<ThreadRow>(
      `SELECT ${THREAD_SELECT} ${THREAD_FROM}
       WHERE t.participant_id = $1 OR c.owner_id = $1
       ORDER BY t.last_message_at DESC NULLS LAST, t.created_at DESC LIMIT 100`,
      [user.id],
    );
    // Un hilo sin mensajes solo estorba si no se puede escribir en él.
    return rows.map((r) => this.toThread(r)).filter((t) => t.lastMessageAt != null || t.open);
  }

  async summary(user: AuthUser, threadId: string) {
    await this.access(user, threadId);
    const { rows } = await this.db.query<ThreadRow>(`SELECT ${THREAD_SELECT} ${THREAD_FROM} WHERE t.id = $2`, [
      user.id,
      threadId,
    ]);
    return this.toThread(rows[0]!);
  }

  /** Abre (o crea) el hilo de la cancha de una reserva. Lo pueden pedir el jugador o el dueño. */
  async openForBooking(user: AuthUser, bookingId: string) {
    const b = (
      await this.db.query<{ player_id: string; court_id: string; owner_id: string }>(
        `SELECT b.player_id, b.court_id, c.owner_id FROM bookings b JOIN courts c ON c.id = b.court_id
         WHERE b.id = $1 AND NOT b.owner_block`,
        [bookingId],
      )
    ).rows[0];
    if (!b || (b.player_id !== user.id && b.owner_id !== user.id)) {
      throw new NotFoundException({ code: 'BOOKING_NOT_FOUND', message: 'Reserva no encontrada' });
    }
    const id = await this.ensureCourtThread(b.court_id, b.player_id);
    return this.summary(user, id);
  }

  async ensureCourtThread(courtId: string, playerId: string): Promise<string> {
    const { rows } = await this.db.query<{ id: string }>(
      `INSERT INTO chat_threads (kind, court_id, participant_id) VALUES ('court', $1, $2)
       ON CONFLICT (court_id, participant_id) WHERE kind = 'court' DO UPDATE SET participant_id = EXCLUDED.participant_id
       RETURNING id`,
      [courtId, playerId],
    );
    return rows[0]!.id;
  }

  /** Mi hilo de soporte (jugadores y dueños; el administrador responde, no consulta). */
  async openSupport(user: AuthUser) {
    if (user.role === 'admin') {
      throw new ForbiddenException({ code: 'ADMIN_NO_SUPPORT', message: 'Los administradores atienden el soporte, no lo consultan' });
    }
    const { rows } = await this.db.query<{ id: string }>(
      `INSERT INTO chat_threads (kind, participant_id) VALUES ('support', $1)
       ON CONFLICT (participant_id) WHERE kind = 'support' DO UPDATE SET participant_id = EXCLUDED.participant_id
       RETURNING id`,
      [user.id],
    );
    return this.summary(user, rows[0]!.id);
  }

  /** Quién puede ver el hilo: el jugador, el dueño de la cancha y los administradores. Los demás ven "no existe". */
  private async access(user: AuthUser, threadId: string): Promise<Access> {
    const t = (
      await this.db.query<{ id: string; kind: 'court' | 'support'; participant_id: string; owner_id: string | null }>(
        `SELECT t.id, t.kind, t.participant_id, c.owner_id FROM chat_threads t LEFT JOIN courts c ON c.id = t.court_id WHERE t.id = $1`,
        [threadId],
      )
    ).rows[0];
    const a: Access | null = t
      ? {
          id: t.id,
          kind: t.kind,
          participantId: t.participant_id,
          ownerId: t.owner_id,
          isParticipant: t.participant_id === user.id,
          isOwner: t.owner_id === user.id,
          isAdmin: user.role === 'admin',
        }
      : null;
    if (!a || !(a.isParticipant || a.isOwner || a.isAdmin)) {
      throw new NotFoundException({ code: 'CHAT_NOT_FOUND', message: 'Chat no encontrado' });
    }
    return a;
  }

  private async isOpen(a: Access): Promise<boolean> {
    if (a.kind === 'support') return true;
    const { rows } = await this.db.query<{ live: boolean; blocked: boolean }>(
      `SELECT ${HAS_LIVE} AS live, ${IS_BLOCKED} AS blocked
       FROM chat_threads t JOIN courts c ON c.id = t.court_id WHERE t.id = $1`,
      [a.id],
    );
    return isChatOpen({ kind: 'court', hasLiveBooking: rows[0]!.live, blocked: rows[0]!.blocked });
  }

  // ---------- Mensajes ----------

  /**
   * Mensajes del hilo. Sin `after` devuelve los últimos; con `after=<seq>` solo los nuevos (así consulta la app).
   * Al leer, el participante marca el hilo como leído. Los administradores ven también los ocultos.
   */
  async messages(user: AuthUser, threadId: string, after?: number, limit = 50) {
    const a = await this.access(user, threadId);
    const admin = a.isAdmin;
    const select = MSG_SELECT.replaceAll('$ADMIN', admin ? 'true' : 'false');
    const { rows } =
      after === undefined
        ? await this.db.query(
            `SELECT * FROM (SELECT ${select} FROM chat_messages m JOIN users u ON u.id = m.sender_id
               WHERE m.thread_id = $1 ORDER BY m.seq DESC LIMIT $2) x ORDER BY x.seq`,
            [threadId, limit],
          )
        : await this.db.query(
            `SELECT ${select} FROM chat_messages m JOIN users u ON u.id = m.sender_id
             WHERE m.thread_id = $1 AND m.seq > $2 ORDER BY m.seq LIMIT $3`,
            [threadId, after, limit],
          );
    if (!admin) await this.markRead(user.id, threadId);
    const open = await this.isOpen(a);
    const blocked = a.kind === 'court' ? (await this.blockedBy(user.id, a)) : false;
    return { open, blocked, messages: rows };
  }

  private async markRead(userId: string, threadId: string): Promise<void> {
    await this.db.query(
      `INSERT INTO chat_reads (thread_id, user_id, last_seq)
       SELECT $1, $2, COALESCE(MAX(seq), 0) FROM chat_messages WHERE thread_id = $1
       ON CONFLICT (thread_id, user_id) DO UPDATE SET last_seq = GREATEST(chat_reads.last_seq, EXCLUDED.last_seq)`,
      [threadId, userId],
    );
  }

  /** ¿Yo bloqueé a la otra parte? (para mostrar «Desbloquear» en la app) */
  private async blockedBy(userId: string, a: Access): Promise<boolean> {
    const other = a.isParticipant ? a.ownerId : a.participantId;
    if (!other) return false;
    const { rows } = await this.db.query(`SELECT 1 FROM chat_blocks WHERE blocker_id = $1 AND blocked_id = $2`, [userId, other]);
    return rows.length > 0;
  }

  async send(user: AuthUser, threadId: string, rawBody: string | undefined, image: Buffer | undefined) {
    const a = await this.access(user, threadId);
    if (a.isAdmin && a.kind !== 'support') {
      throw new ForbiddenException({ code: 'ADMIN_READ_ONLY', message: 'Soporte solo puede leer los chats entre jugador y dueño' });
    }
    const body = cleanBody(rawBody);
    if (!body && !image) {
      throw new BadRequestException({ code: 'EMPTY_MESSAGE', message: 'Escribe un mensaje o adjunta una foto' });
    }
    if (!(await this.isOpen(a))) {
      throw new ConflictException({
        code: 'CHAT_CLOSED',
        message: 'Este chat está cerrado. Se abre de nuevo cuando haya una reserva vigente.',
      });
    }
    const file = image ? await this.storage.saveImage(image, 'chat') : null;
    const msg = await this.db.tx(async (c) => {
      const ins = await c.query<{ id: string; seq: number; created_at: Date }>(
        `INSERT INTO chat_messages (thread_id, sender_id, body, image_path) VALUES ($1, $2, $3, $4)
         RETURNING id, seq::float8 AS seq, created_at`,
        [threadId, user.id, body, file],
      );
      await c.query('UPDATE chat_threads SET last_message_at = now() WHERE id = $1', [threadId]);
      if (!a.isAdmin) {
        await c.query(
          `INSERT INTO chat_reads (thread_id, user_id, last_seq) VALUES ($1, $2, $3)
           ON CONFLICT (thread_id, user_id) DO UPDATE SET last_seq = GREATEST(chat_reads.last_seq, EXCLUDED.last_seq)`,
          [threadId, user.id, ins.rows[0]!.seq],
        );
      }
      return ins.rows[0]!;
    });
    void this.notify(user, a, body, file != null).catch((e: Error) => this.log.warn(`Push de chat falló: ${e.message}`));
    const name = (await this.db.query<{ name: string }>('SELECT name FROM users WHERE id = $1', [user.id])).rows[0]!.name;
    return {
      id: msg.id,
      seq: msg.seq,
      senderId: user.id,
      senderName: name,
      fromSupport: a.isAdmin,
      body,
      hasImage: file != null,
      hidden: false,
      createdAt: msg.created_at,
    };
  }

  /** Push a la otra parte. No se guarda en la bandeja de avisos para no llenarla. */
  private async notify(sender: AuthUser, a: Access, body: string | null, hasImage: boolean): Promise<void> {
    let to: string[];
    let title: string;
    if (a.kind === 'support') {
      title = a.isAdmin ? 'Soporte Golazo' : 'Mensaje para soporte';
      to = a.isAdmin
        ? [a.participantId]
        : (await this.db.query<{ id: string }>(`SELECT id FROM users WHERE role = 'admin' AND deleted_at IS NULL AND suspended_at IS NULL`)).rows.map((r) => r.id);
    } else {
      to = [a.isParticipant ? a.ownerId! : a.participantId];
      title = (await this.db.query<{ name: string }>('SELECT name FROM users WHERE id = $1', [sender.id])).rows[0]!.name;
    }
    for (const userId of to) {
      await this.push.send(userId, title, preview(body, hasImage), { type: 'chat_message', threadId: a.id });
    }
  }

  /** Ruta de la foto de un mensaje (solo participantes y administradores). */
  async imagePath(user: AuthUser, messageId: string): Promise<string> {
    const m = (
      await this.db.query<{ thread_id: string; image_path: string | null; hidden_at: Date | null }>(
        'SELECT thread_id, image_path, hidden_at FROM chat_messages WHERE id = $1',
        [messageId],
      )
    ).rows[0];
    if (!m) throw new NotFoundException({ code: 'MESSAGE_NOT_FOUND', message: 'Mensaje no encontrado' });
    const a = await this.access(user, m.thread_id);
    if (!m.image_path || (m.hidden_at && !a.isAdmin)) {
      throw new NotFoundException({ code: 'MESSAGE_NOT_FOUND', message: 'Foto no encontrada' });
    }
    const p = this.storage.pathOf('chat', m.image_path);
    if (!p) throw new NotFoundException({ code: 'MESSAGE_NOT_FOUND', message: 'Foto no encontrada' });
    return p;
  }

  // ---------- Moderación (jugador y dueño) ----------

  async report(user: AuthUser, messageId: string, reason?: string) {
    const m = (
      await this.db.query<{ thread_id: string; sender_id: string }>('SELECT thread_id, sender_id FROM chat_messages WHERE id = $1', [messageId])
    ).rows[0];
    if (!m) throw new NotFoundException({ code: 'MESSAGE_NOT_FOUND', message: 'Mensaje no encontrado' });
    await this.access(user, m.thread_id);
    if (m.sender_id === user.id) {
      throw new UnprocessableEntityException({ code: 'OWN_MESSAGE', message: 'No puedes reportar tu propio mensaje' });
    }
    await this.db.query(
      `INSERT INTO chat_reports (message_id, reporter_id, reason) VALUES ($1, $2, $3) ON CONFLICT (message_id, reporter_id) DO NOTHING`,
      [messageId, user.id, reason?.trim() || null],
    );
    return { reported: true };
  }

  async block(user: AuthUser, targetId: string) {
    if (targetId === user.id) {
      throw new UnprocessableEntityException({ code: 'SELF_BLOCK', message: 'No puedes bloquearte a ti mismo' });
    }
    const t = (await this.db.query<{ role: string }>('SELECT role FROM users WHERE id = $1 AND deleted_at IS NULL', [targetId])).rows[0];
    if (!t) throw new NotFoundException({ code: 'USER_NOT_FOUND', message: 'Usuario no encontrado' });
    if (t.role === 'admin') {
      throw new UnprocessableEntityException({ code: 'CANNOT_BLOCK_SUPPORT', message: 'No se puede bloquear a soporte' });
    }
    await this.db.query(
      'INSERT INTO chat_blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [user.id, targetId],
    );
    return { blocked: true };
  }

  async unblock(user: AuthUser, targetId: string) {
    await this.db.query('DELETE FROM chat_blocks WHERE blocker_id = $1 AND blocked_id = $2', [user.id, targetId]);
    return { blocked: false };
  }

  // ---------- Administración ----------

  /** Bandeja de soporte: primero los que esperan respuesta. */
  async supportInbox() {
    const { rows } = await this.db.query(
      `SELECT t.id, t.participant_id AS "participantId", u.name AS "participantName", u.email AS "participantEmail",
              u.role AS "participantRole", t.last_message_at AS "lastMessageAt",
              lm.body AS "lastBody", (lm.image_path IS NOT NULL) AS "lastHasImage",
              COALESCE(lm.sender_id = t.participant_id, false) AS "needsReply"
       FROM chat_threads t
       JOIN users u ON u.id = t.participant_id
       LEFT JOIN LATERAL (SELECT body, image_path, sender_id FROM chat_messages
                          WHERE thread_id = t.id AND hidden_at IS NULL ORDER BY seq DESC LIMIT 1) lm ON true
       WHERE t.kind = 'support' AND t.last_message_at IS NOT NULL
       ORDER BY COALESCE(lm.sender_id = t.participant_id, false) DESC, t.last_message_at DESC LIMIT 100`,
    );
    return rows;
  }

  /** Cualquier chat entre jugador y dueño (solo lectura), con búsqueda por cancha o por nombre. */
  async courtThreads(q: { search?: string; courtId?: string; limit?: number; offset?: number }) {
    const { rows } = await this.db.query(
      `SELECT t.id, c.id AS "courtId", c.name AS "courtName", pu.name AS "playerName", ou.name AS "ownerName",
              t.last_message_at AS "lastMessageAt", lm.body AS "lastBody", (lm.image_path IS NOT NULL) AS "lastHasImage",
              (SELECT COUNT(*)::int FROM chat_messages m WHERE m.thread_id = t.id) AS messages
       FROM chat_threads t
       JOIN courts c ON c.id = t.court_id
       JOIN users pu ON pu.id = t.participant_id
       JOIN users ou ON ou.id = c.owner_id
       LEFT JOIN LATERAL (SELECT body, image_path FROM chat_messages WHERE thread_id = t.id AND hidden_at IS NULL ORDER BY seq DESC LIMIT 1) lm ON true
       WHERE t.kind = 'court' AND t.last_message_at IS NOT NULL
         AND ($1::uuid IS NULL OR c.id = $1::uuid)
         AND ($2::text IS NULL OR c.name ILIKE '%' || $2 || '%' OR pu.name ILIKE '%' || $2 || '%' OR ou.name ILIKE '%' || $2 || '%')
       ORDER BY t.last_message_at DESC LIMIT $3 OFFSET $4`,
      [q.courtId ?? null, q.search ?? null, q.limit ?? 50, q.offset ?? 0],
    );
    return rows;
  }

  async reports(openOnly = true) {
    const { rows } = await this.db.query(
      `SELECT r.id, r.reason, r.created_at AS "createdAt", r.resolved_at AS "resolvedAt",
              m.id AS "messageId", m.thread_id AS "threadId", m.body, (m.image_path IS NOT NULL) AS "hasImage",
              (m.hidden_at IS NOT NULL) AS hidden,
              su.name AS "senderName", ru.name AS "reporterName", c.name AS "courtName"
       FROM chat_reports r
       JOIN chat_messages m ON m.id = r.message_id
       JOIN users su ON su.id = m.sender_id
       JOIN users ru ON ru.id = r.reporter_id
       JOIN chat_threads t ON t.id = m.thread_id
       LEFT JOIN courts c ON c.id = t.court_id
       WHERE ($1::boolean = false OR r.resolved_at IS NULL)
       ORDER BY r.created_at DESC LIMIT 100`,
      [openOnly],
    );
    return rows;
  }

  async resolveReport(adminId: string, reportId: string) {
    const r = await this.db.query(
      `UPDATE chat_reports SET resolved_at = now(), resolved_by = $2 WHERE id = $1 AND resolved_at IS NULL`,
      [reportId, adminId],
    );
    if (r.rowCount === 0) throw new NotFoundException({ code: 'REPORT_NOT_FOUND', message: 'Reporte no encontrado o ya resuelto' });
    return { id: reportId, resolved: true };
  }

  /** Oculta el mensaje para los usuarios (queda como evidencia para el administrador) y cierra sus reportes. */
  async hideMessage(adminId: string, messageId: string) {
    const upd = await this.db.query(`UPDATE chat_messages SET hidden_at = COALESCE(hidden_at, now()) WHERE id = $1`, [messageId]);
    if (upd.rowCount === 0) throw new NotFoundException({ code: 'MESSAGE_NOT_FOUND', message: 'Mensaje no encontrado' });
    await this.db.query(
      `UPDATE chat_reports SET resolved_at = now(), resolved_by = $2 WHERE message_id = $1 AND resolved_at IS NULL`,
      [messageId, adminId],
    );
    return { id: messageId, hidden: true };
  }
}

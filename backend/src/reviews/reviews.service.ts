import { ConflictException, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { Db, UNIQUE_VIOLATION, pgCode } from '../db/db.service.js';

@Injectable()
export class ReviewsService {
  constructor(private readonly db: Db) {}

  /** Lista pública de reseñas de una cancha (sin las ocultas por el admin). Solo el primer nombre del autor. */
  async listForCourt(courtId: string, limit: number, offset: number) {
    const { rows } = await this.db.query(
      `SELECT r.id, r.stars, r.body, r.created_at AS "createdAt", split_part(u.name, ' ', 1) AS "authorName"
       FROM reviews r JOIN users u ON u.id = r.author_id
       WHERE r.court_id = $1 AND r.hidden_at IS NULL
       ORDER BY r.created_at DESC LIMIT $2 OFFSET $3`,
      [courtId, limit, offset],
    );
    return rows;
  }

  /** Solo quien jugó (reserva confirmada ya terminada) puede reseñar, una vez por reserva. */
  async create(playerId: string, bookingId: string, stars: number, body?: string) {
    const { rows } = await this.db.query<{ court_id: string; status: string; end_at: Date }>(
      'SELECT court_id, status, end_at FROM bookings WHERE id = $1 AND player_id = $2',
      [bookingId, playerId],
    );
    const b = rows[0];
    if (!b) throw new NotFoundException({ code: 'BOOKING_NOT_FOUND', message: 'Reserva no encontrada' });
    if (b.status !== 'confirmed' || b.end_at.getTime() > Date.now()) {
      throw new UnprocessableEntityException({
        code: 'NOT_PLAYED',
        message: 'Solo puedes calificar una reserva confirmada que ya se jugó',
      });
    }
    try {
      const ins = await this.db.query<{ id: string }>(
        `INSERT INTO reviews (court_id, booking_id, author_id, stars, body) VALUES ($1,$2,$3,$4,$5) RETURNING id`,
        [b.court_id, bookingId, playerId, stars, body?.trim() || null],
      );
      return { id: ins.rows[0]!.id, courtId: b.court_id, stars, body: body?.trim() || null };
    } catch (e) {
      if (pgCode(e) === UNIQUE_VIOLATION) {
        throw new ConflictException({ code: 'ALREADY_REVIEWED', message: 'Ya calificaste esta reserva' });
      }
      throw e;
    }
  }

  /** Reportar una reseña ajena. Repetir el reporte es inofensivo (idempotente). */
  async report(reporterId: string, reviewId: string, reason?: string): Promise<void> {
    const r = await this.db.query<{ author_id: string }>(
      'SELECT author_id FROM reviews WHERE id = $1 AND hidden_at IS NULL',
      [reviewId],
    );
    if (!r.rows[0]) throw new NotFoundException({ code: 'REVIEW_NOT_FOUND', message: 'Reseña no encontrada' });
    if (r.rows[0].author_id === reporterId) {
      throw new UnprocessableEntityException({ code: 'OWN_REVIEW', message: 'No puedes reportar tu propia reseña' });
    }
    await this.db.query(
      `INSERT INTO review_reports (review_id, reporter_id, reason) VALUES ($1,$2,$3)
       ON CONFLICT (review_id, reporter_id) DO NOTHING`,
      [reviewId, reporterId, reason?.trim() || null],
    );
  }
}

import { Module } from '@nestjs/common';
import {
  AdminPaymentsController,
  BookingPaymentController,
  OwnerPaymentsController,
  ProofController,
} from './payments.controller.js';
import { PaymentsService } from './payments.service.js';

@Module({
  controllers: [BookingPaymentController, OwnerPaymentsController, AdminPaymentsController, ProofController],
  providers: [PaymentsService],
})
export class PaymentsModule {}

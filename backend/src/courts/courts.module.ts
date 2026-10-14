import { Module } from '@nestjs/common';
import { CitiesController, CourtsController, OwnerCourtsController } from './courts.controller.js';
import { CourtsService } from './courts.service.js';

@Module({
  controllers: [CitiesController, CourtsController, OwnerCourtsController],
  providers: [CourtsService],
  exports: [CourtsService],
})
export class CourtsModule {}

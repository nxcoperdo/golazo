import { Global, Module } from '@nestjs/common';
import { Db } from './db.service.js';

@Global()
@Module({ providers: [Db], exports: [Db] })
export class DbModule {}

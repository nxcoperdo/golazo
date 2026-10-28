import { Module } from '@nestjs/common';
import { AdminChatController, ChatController } from './chat.controller.js';
import { ChatService } from './chat.service.js';

@Module({ controllers: [ChatController, AdminChatController], providers: [ChatService] })
export class ChatModule {}

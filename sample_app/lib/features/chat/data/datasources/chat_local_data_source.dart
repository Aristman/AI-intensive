import 'dart:convert';

import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../domain/entities/message_entity.dart';

abstract class ChatLocalDataSource {
  Future<List<MessageEntity>> getMessages();
  Future<void> saveMessage(MessageEntity message);
  Future<void> clearMessages();
}

class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  final LocalStorageService localStorageService;
  final String messagesKey = 'chat_messages';

  ChatLocalDataSourceImpl({required this.localStorageService});

  @override
  Future<List<MessageEntity>> getMessages() async {
    try {
      final messagesJson = await localStorageService.getString(messagesKey);
      if (messagesJson == null) return [];
      
      final List<dynamic> jsonList = jsonDecode(messagesJson);
      return jsonList
          .map((json) => MessageEntity.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw CacheException('Failed to load messages: $e');
    }
  }

  @override
  Future<void> saveMessage(MessageEntity message) async {
    try {
      final messages = await getMessages();
      messages.add(message);
      await localStorageService.saveString(
        messagesKey,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );
    } catch (e) {
      throw CacheException('Failed to save message: $e');
    }
  }

  @override
  Future<void> clearMessages() async {
    try {
      await localStorageService.remove(messagesKey);
    } catch (e) {
      throw CacheException('Failed to clear messages: $e');
    }
  }
}

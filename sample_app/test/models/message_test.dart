import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/models/message.dart';

void main() {
  group('Message', () {
    test('should create a message with current timestamp when not provided', () {
      // Arrange
      final message = Message(
        text: 'Test message',
        isUser: true,
      );

      // Assert
      expect(message.text, 'Test message');
      expect(message.isUser, true);
      expect(message.timestamp, isA<DateTime>());
    });

    test('should create a message with provided timestamp', () {
      // Arrange
      final now = DateTime.now();
      final message = Message(
        text: 'Test message',
        isUser: true,
        timestamp: now,
      );

      // Assert
      expect(message.text, 'Test message');
      expect(message.isUser, true);
      expect(message.timestamp, now);
    });

    test('should have correct equality', () {
      // Arrange
      final now = DateTime.now();
      final message1 = Message(
        text: 'Test message',
        isUser: true,
        timestamp: now,
      );
      final message2 = Message(
        text: 'Test message',
        isUser: true,
        timestamp: now,
      );
      final message3 = Message(
        text: 'Different message',
        isUser: true,
        timestamp: now,
      );

      // Assert
      expect(message1, message2);
      expect(message1, isNot(equals(message3)));
    });
  });
}

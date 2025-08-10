import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/main.dart';

void main() {
  // Setup test environment
  setUpAll(() async {
    // Load test environment variables
    await dotenv.load(fileName: "assets/.env");
  });

  testWidgets('ChatScreen should display initial UI', (WidgetTester tester) async {
    // Build our app and trigger a frame
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(),
    ));

    // Verify that the input field is displayed
    expect(find.byType(TextField), findsOneWidget);
    
    // Verify that the send button is displayed
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('ChatScreen should show error when sending message without API key', 
      (WidgetTester tester) async {
    // Create a test case where the API key is empty
    await dotenv.env.remove('DEEPSEEK_API_KEY');
    
    // Build our app and trigger a frame
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(),
    ));

    // Find the text field and enter text
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'Test message');
    
    // Tap the send button
    await tester.tap(find.byIcon(Icons.send));
    
    // Rebuild the widget after the state has changed
    await tester.pump();
    
    // Verify that the error message is shown
    final errorFinder = find.textContaining('Ошибка: API ключ не найден', findRichText: true);
    expect(errorFinder, findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sample_app/main.dart';

void main() {
  testWidgets('App should display chat screen', (WidgetTester tester) async {
    // Load test environment variables
    await dotenv.load(fileName: "assets/.env");
    
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the chat screen is displayed
    expect(find.byType(ChatScreen), findsOneWidget);
    
    // Verify that the app bar title is displayed
    expect(find.byType(AppBar), findsOneWidget);
    
    // Verify that the text field is present
    expect(find.byType(TextField), findsOneWidget);
  });
}

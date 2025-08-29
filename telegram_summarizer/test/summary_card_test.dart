import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_summarizer/widgets/summary_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('SummaryCard renders JSON and copies to clipboard', (tester) async {
    final data = {
      'summary': 'ok',
      'items': [1, 2]
    };

    await tester.pumpWidget(_wrap(SummaryCard(content: data)));

    // Заголовок
    expect(find.text('Сводка'), findsOneWidget);

    // Читаемая сводка по ключу
    expect(find.byKey(const Key('summary_text')), findsOneWidget);
    expect(find.text('ok'), findsWidgets);

    // Форматированный JSON присутствует (фрагмент)
    expect(find.textContaining('"summary"'), findsWidgets);

    // Кнопка копирования
    final copyBtn = find.byKey(const Key('summary_copy'));
    expect(copyBtn, findsOneWidget);
    await tester.tap(copyBtn);
    await tester.pump();
  });

  testWidgets('SummaryCard shows warnings when content has issues', (tester) async {
    final data = {
      'summary': 123, // вызовет предупреждение в парсере
    };

    await tester.pumpWidget(_wrap(SummaryCard(content: data)));
    await tester.pump();

    // Предупреждение отображается
    expect(find.textContaining('Поле "summary" не является строкой.'), findsOneWidget);
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_summarizer/core/structured_content_parser.dart';

class SummaryCard extends StatelessWidget {
  final dynamic content;
  const SummaryCard({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final parse = const StructuredContentParser().parse(content);
    final data = parse.data ?? {'error': 'Невалидный structuredContent', 'raw': content?.toString()};
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Сводка', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: 'Копировать',
                  key: const Key('summary_copy'),
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pretty));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Скопировано')),
                      );
                    }
                  },
                )
              ],
            ),
            if (parse.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Text(
                  parse.warnings.join('\n'),
                  style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            // Читаемая сводка, если есть поле summary
            if (data['summary'] is String) ...[
              Text(
                data['summary'] as String,
                key: const Key('summary_text'),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(pretty, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }
}

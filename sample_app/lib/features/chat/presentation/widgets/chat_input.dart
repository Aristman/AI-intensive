import 'package:flutter/material.dart';

class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSendMessage;
  final bool isLoading;
  final String? Function(String?)? validator;
  final TextEditingController? controller;

  const ChatInput({
    Key? key,
    required this.onSendMessage,
    this.isLoading = false,
    this.validator,
    this.controller,
  }) : super(key: key);

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleSubmitted() {
    if (_formKey.currentState?.validate() ?? false) {
      final message = _controller.text.trim();
      if (message.isNotEmpty) {
        widget.onSendMessage(message);
        _controller.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.send,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: widget.isLoading ? null : _handleSubmitted,
                  ),
                ),
                onFieldSubmitted: (_) => _handleSubmitted(),
                validator: widget.validator,
                enabled: !widget.isLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

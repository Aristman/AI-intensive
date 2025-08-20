import 'dart:async';

import 'package:flutter/material.dart';

/// A reusable TextField that safely submits on Enter (TextInputAction.send)
/// avoiding re-entrancy issues with HardwareKeyboard on desktop.
///
/// Features:
/// - textInputAction: send
/// - defers onSend to a microtask to avoid key-event reentrancy
/// - optional unfocus on submit
class SafeSendTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final String hintText;
  final EdgeInsetsGeometry contentPadding;
  final InputBorder? border;
  final bool filled;
  final bool unfocusOnSubmit;
  final VoidCallback? onTap;
  final void Function(String text) onSend;

  const SafeSendTextField({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.enabled = true,
    this.hintText = '',
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    this.border,
    this.filled = true,
    this.unfocusOnSubmit = true,
    this.onTap,
  });

  void _safeSubmit(BuildContext context, String text) {
    if (!enabled) return;
    if (unfocusOnSubmit) {
      focusNode?.unfocus();
    }
    // Defer to next microtask to avoid processing during key event dispatch
    Future.microtask(() => onSend(text));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hintText,
        border: border ?? OutlineInputBorder(
          borderRadius: BorderRadius.circular(24.0),
          borderSide: BorderSide.none,
        ),
        filled: filled,
        contentPadding: contentPadding,
      ),
      onSubmitted: enabled ? (text) => _safeSubmit(context, text) : null,
      onEditingComplete: enabled ? () => _safeSubmit(context, controller.text) : null,
      onTap: onTap,
      textInputAction: TextInputAction.send,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:sample_app/models/user_profile.dart';
import 'package:sample_app/services/user_profile_controller.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfileController controller;
  const ProfileScreen({super.key, required this.controller});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _roleCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.controller.profile;
    _nameCtrl = TextEditingController(text: p.name);
    _roleCtrl = TextEditingController(text: p.role);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveBasics() async {
    await widget.controller.updateName(_nameCtrl.text.trim());
    await widget.controller.updateRole(_roleCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
    }
  }

  Future<ProfileEntry?> _openEntryDialog({ProfileEntry? initial}) async {
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    final descCtrl = TextEditingController(text: initial?.description ?? '');
    final result = await showDialog<ProfileEntry>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial == null ? 'Добавить запись' : 'Редактировать запись'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Описание'),
                  minLines: 1,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final t = titleCtrl.text.trim();
              if (t.isEmpty) return; // простая валидация
              Navigator.pop(context, ProfileEntry(title: t, description: descCtrl.text.trim()));
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    // Не освобождаем контроллеры вручную: диалог и поля закрыты, GC их соберёт.
    // Это защищает от состояния, когда Overlay ещё анимируется, а контроллеры уже disposed.
    return result;
  }

  Widget _section(
    String title,
    List<ProfileEntry> items, {
    Future<void> Function()? onAdd,
    Future<void> Function(int index)? onDelete,
    Future<void> Function(int index)? onEdit,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Tooltip(
                  message: onAdd == null ? 'Недоступно для гостевого профиля' : 'Добавить запись',
                  child: ElevatedButton(
                    onPressed: onAdd == null ? null : onAdd,
                    child: const Text('Добавить запись'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('Пока нет записей', style: TextStyle(color: Colors.grey))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = items[index];
                  return ListTile(
                    title: Text(e.title),
                    subtitle: e.description.isNotEmpty ? Text(e.description) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: onEdit == null ? 'Недоступно для гостевого профиля' : 'Редактировать',
                          onPressed: onEdit == null ? null : () => onEdit(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: onDelete == null ? 'Недоступно для гостевого профиля' : 'Удалить',
                          onPressed: onDelete == null ? null : () => onDelete(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.profile;
    final bool isGuest = p.role == 'guest';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль пользователя'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Имя'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _roleCtrl,
                  decoration: const InputDecoration(labelText: 'Роль'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton(
                    onPressed: _saveBasics,
                    child: const Text('Сохранить профиль'),
                  ),
                ),
                if (isGuest) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Гостевой профиль: редактирование предпочтений и исключений недоступно',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 16),
                _section(
                  'Предпочтения',
                  p.preferences,
                  onAdd: isGuest
                      ? null
                      : () async {
                          final entry = await _openEntryDialog();
                          if (entry != null) {
                            if (!mounted) return;
                            await WidgetsBinding.instance.endOfFrame;
                            await widget.controller.addPreference(entry);
                          }
                        },
                  onDelete: isGuest
                      ? null
                      : (i) async {
                          if (!mounted) return;
                          await WidgetsBinding.instance.endOfFrame;
                          await widget.controller.removePreference(i);
                        },
                  onEdit: isGuest
                      ? null
                      : (i) async {
                          final current = p.preferences[i];
                          final edited = await _openEntryDialog(initial: current);
                          if (edited != null) {
                            if (!mounted) return;
                            await WidgetsBinding.instance.endOfFrame;
                            await widget.controller.editPreference(i, edited);
                          }
                        },
                ),
                const SizedBox(height: 16),
                _section(
                  'Исключения',
                  p.exclusions,
                  onAdd: isGuest
                      ? null
                      : () async {
                          final entry = await _openEntryDialog();
                          if (entry != null) {
                            if (!mounted) return;
                            await WidgetsBinding.instance.endOfFrame;
                            await widget.controller.addExclusion(entry);
                          }
                        },
                  onDelete: isGuest
                      ? null
                      : (i) async {
                          if (!mounted) return;
                          await WidgetsBinding.instance.endOfFrame;
                          await widget.controller.removeExclusion(i);
                        },
                  onEdit: isGuest
                      ? null
                      : (i) async {
                          final current = p.exclusions[i];
                          final edited = await _openEntryDialog(initial: current);
                          if (edited != null) {
                            if (!mounted) return;
                            await WidgetsBinding.instance.endOfFrame;
                            await widget.controller.editExclusion(i, edited);
                          }
                        },
                ),
          ],
        ),
      ),
    );
  }
}

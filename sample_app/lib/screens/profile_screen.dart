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
    if (!widget.controller.isLoading) {
      // ensure loaded
      widget.controller.load();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
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
        content: Column(
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
    titleCtrl.dispose();
    descCtrl.dispose();
    return result;
  }

  Widget _section(
    String title,
    List<ProfileEntry> items, {
    required VoidCallback onAdd,
    required void Function(int) onDelete,
    required void Function(int) onEdit,
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
                ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить запись'),
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
                          tooltip: 'Редактировать',
                          onPressed: () => onEdit(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Удалить',
                          onPressed: () => onDelete(index),
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
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = widget.controller.profile;
        _nameCtrl.value = _nameCtrl.value.copyWith(text: p.name, selection: TextSelection.collapsed(offset: p.name.length));
        _roleCtrl.value = _roleCtrl.value.copyWith(text: p.role, selection: TextSelection.collapsed(offset: p.role.length));
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
                  child: ElevatedButton.icon(
                    onPressed: _saveBasics,
                    icon: const Icon(Icons.save),
                    label: const Text('Сохранить профиль'),
                  ),
                ),
                const SizedBox(height: 16),
                _section(
                  'Предпочтения',
                  p.preferences,
                  onAdd: () async {
                    final entry = await _openEntryDialog();
                    if (entry != null) {
                      await widget.controller.addPreference(entry);
                    }
                  },
                  onDelete: (i) async {
                    await widget.controller.removePreference(i);
                  },
                  onEdit: (i) async {
                    final current = p.preferences[i];
                    final edited = await _openEntryDialog(initial: current);
                    if (edited != null) {
                      await widget.controller.editPreference(i, edited);
                    }
                  },
                ),
                const SizedBox(height: 16),
                _section(
                  'Исключения',
                  p.exclusions,
                  onAdd: () async {
                    final entry = await _openEntryDialog();
                    if (entry != null) {
                      await widget.controller.addExclusion(entry);
                    }
                  },
                  onDelete: (i) async {
                    await widget.controller.removeExclusion(i);
                  },
                  onEdit: (i) async {
                    final current = p.exclusions[i];
                    final edited = await _openEntryDialog(initial: current);
                    if (edited != null) {
                      await widget.controller.editExclusion(i, edited);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

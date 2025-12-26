import 'package:flutter/material.dart';

class TaskColors {
  static const List<String> morandiHex = <String>[
    'D8C3A5', // beige
    'A8B5A2', // sage
    'B7A6A1', // dusty rose
    'A3B7C6', // dusty blue
    'C5B9C6', // lavender gray
  ];

  static Color? resolveBackground(String taskId, String? colorHex) {
    final normalized = _normalizeHex(colorHex);
    if (normalized == null) return null;
    return _fromHex(normalized);
  }

  static String? _normalizeHex(String? hex) {
    final value = (hex ?? '').trim();
    if (value.isEmpty) return null;
    final cleaned = value.startsWith('#') ? value.substring(1) : value;
    if (cleaned.length != 6) return null;
    return cleaned.toUpperCase();
  }

  static Color _fromHex(String hex) {
    final buffer = StringBuffer('FF')..write(hex);
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

Future<String?> showTaskColorPicker(
  BuildContext context, {
  String? initialHex,
  String? selectedHex,
}) async {
  final initial = (initialHex ?? selectedHex ?? '').trim().toUpperCase().replaceAll('#', '');
  return showDialog<String?>(
    context: context,
    builder: (context) {
      String selected = initial;

      Widget colorDot(String hex) {
        final color = TaskColors.resolveBackground('', hex) ?? Colors.transparent;
        final isSelected = selected == hex;
        return InkWell(
          onTap: () => Navigator.of(context).pop(hex),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.black54 : Colors.black12,
                width: isSelected ? 2 : 1,
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        title: const Text('选择颜色'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pop(''),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected.isEmpty ? Colors.black54 : Colors.black12,
                        width: selected.isEmpty ? 2 : 1,
                      ),
                    ),
                    child: const Center(child: Text('无', style: TextStyle(fontSize: 12))),
                  ),
                ),
                for (final hex in TaskColors.morandiHex)
                  GestureDetector(
                    onTap: () {
                      setState(() => selected = hex);
                      Navigator.of(context).pop(hex);
                    },
                    child: colorDot(hex),
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
}

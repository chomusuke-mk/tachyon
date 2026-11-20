import 'package:flutter/material.dart';

/// Searchable modal dialog for picking a radio genre/tag or country filter
/// without causing UI lag across large collections of items.
class RadioFilterPickerDialog extends StatefulWidget {
  final String title;
  final String currentSelectedValue;
  final String allLabel;
  final List<String> items;
  final ValueChanged<String> onSelected;

  const RadioFilterPickerDialog({
    super.key,
    required this.title,
    required this.currentSelectedValue,
    required this.allLabel,
    required this.items,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String currentSelectedValue,
    required String allLabel,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => RadioFilterPickerDialog(
        title: title,
        currentSelectedValue: currentSelectedValue,
        allLabel: allLabel,
        items: items,
        onSelected: (val) {
          onSelected(val);
          Navigator.of(dialogCtx).pop();
        },
      ),
    );
  }

  @override
  State<RadioFilterPickerDialog> createState() =>
      _RadioFilterPickerDialogState();
}

class _RadioFilterPickerDialogState extends State<RadioFilterPickerDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase().trim();
    final filtered = widget.items.where((item) {
      if (item == 'All') return false; // Handled separately as allLabel
      if (query.isEmpty) return true;
      return item.toLowerCase().contains(query);
    }).toList(growable: false);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        height: 450,
        child: Column(
          children: [
            TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                hintText: widget.title,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _searchQuery.isEmpty
                    ? filtered.length + 1
                    : filtered.length,
                itemBuilder: (context, index) {
                  if (_searchQuery.isEmpty && index == 0) {
                    final isSelected =
                        widget.currentSelectedValue == 'All' ||
                        widget.currentSelectedValue.isEmpty;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected ? colorScheme.primary : null,
                      ),
                      title: Text(
                        widget.allLabel,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colorScheme.primary : null,
                        ),
                      ),
                      onTap: () => widget.onSelected('All'),
                    );
                  }

                  final item = _searchQuery.isEmpty
                      ? filtered[index - 1]
                      : filtered[index];
                  final isSelected = widget.currentSelectedValue == item;

                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected ? colorScheme.primary : null,
                    ),
                    title: Text(
                      item,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colorScheme.primary : null,
                      ),
                    ),
                    onTap: () => widget.onSelected(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

/// Reusable searchable language selection dialog.
///
/// Used for both App UI Language and Lyrics Translation Target Language.
class LanguagePickerDialog extends StatefulWidget {
  final String title;
  final String currentSelectedValue;
  final AppStringKey strings;
  final ValueChanged<String> onSelected;

  const LanguagePickerDialog({
    super.key,
    required this.title,
    required this.currentSelectedValue,
    required this.strings,
    required this.onSelected,
  });

  /// Static helper to display the dialog.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String currentSelectedValue,
    required AppStringKey strings,
    required ValueChanged<String> onSelected,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => LanguagePickerDialog(
        title: title,
        currentSelectedValue: currentSelectedValue,
        strings: strings,
        onSelected: (val) {
          onSelected(val);
          Navigator.of(dialogCtx).pop();
        },
      ),
    );
  }

  @override
  State<LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<LanguagePickerDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.toLowerCase().trim();
    final filteredEntries = languagesEndonyms.entries.where((e) {
      if (query.isEmpty) return true;
      return e.key.toLowerCase().contains(query) ||
          e.value.toLowerCase().contains(query);
    }).toList();

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
                hintText: widget.strings.sLanguageSearchHint,
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
                    ? filteredEntries.length + 1
                    : filteredEntries.length,
                itemBuilder: (context, index) {
                  if (_searchQuery.isEmpty && index == 0) {
                    final isSelected =
                        widget.currentSelectedValue == 'defaultOption';
                    final effectiveLocale =
                        context.read<LocaleController>().currentLocaleCode;
                    final resolvedName =
                        languagesEndonyms[effectiveLocale] ?? effectiveLocale;

                    return ListTile(
                      leading: Icon(
                        Icons.auto_awesome_rounded,
                        color: isSelected ? colorScheme.primary : null,
                      ),
                      title: Text(
                        widget.strings.sTranslationLangDefault,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(resolvedName),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              color: colorScheme.primary,
                            )
                          : null,
                      onTap: () => widget.onSelected('defaultOption'),
                    );
                  }

                  final item = filteredEntries[
                      _searchQuery.isEmpty ? index - 1 : index];
                  final isSelected = widget.currentSelectedValue == item.key;

                  return ListTile(
                    title: Text(
                      item.value,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(item.key),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: colorScheme.primary,
                          )
                        : null,
                    onTap: () => widget.onSelected(item.key),
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
          child: Text(widget.strings.sCancel),
        ),
      ],
    );
  }
}

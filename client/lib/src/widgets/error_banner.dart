import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.title,
    required this.message,
    this.copyText,
    this.copyJsonText,
  });

  final String title;
  final String message;
  final String? copyText;
  final String? copyJsonText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _copy(
                  context,
                  copyText == null || copyText!.trim().isEmpty
                      ? '$title\n$message'
                      : copyText!,
                ),
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
              if (copyJsonText != null && copyJsonText!.trim().isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () => _copy(context, copyJsonText!),
                  icon: const Icon(Icons.data_object),
                  label: const Text('Copy as JSON'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }
}

import 'package:flutter/material.dart';

/// The one shared voice for a manual write's outcome: a snackbar carrying the
/// result message, with an UNDO action when the write is reversible.
///
/// This replaces ~7 hand-rolled copies across Today/Plan/Library that were
/// inconsistent about mounted-guarding and — worse — fired their undo callbacks
/// without awaiting them, so a failed undo was a silent failure. Here the undo
/// is awaited; whatever it reports (or throws) is surfaced as a follow-up
/// snackbar through the same messenger, which is captured synchronously so the
/// tail of the async work never needs the (possibly disposed) BuildContext.
///
/// [onUndo] performs the undo and returns the outcome line to show (null/empty
/// for silence). Callers put their own refresh + mounted guards inside it.
void showUndoableResult(
  BuildContext context, {
  required String message,
  Future<String?> Function()? onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: onUndo == null
          ? null
          : SnackBarAction(
              label: 'UNDO',
              onPressed: () async {
                String? outcome;
                try {
                  outcome = await onUndo();
                } catch (error) {
                  // No silent failure: an undo that broke must say so.
                  outcome = 'Undo failed: $error';
                }
                if (outcome != null && outcome.isNotEmpty) {
                  messenger.showSnackBar(SnackBar(content: Text(outcome)));
                }
              },
            ),
    ),
  );
}

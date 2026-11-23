import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

enum ToastKind { info, success, error }

/// In-app notification (replaces the Material SnackBar).
///
/// Why not SnackBar: in this Flutter version a SnackBar with an action
/// (our "Undo") is `persist: true` by default and never auto-dismisses.
/// A toast always closes itself after [autoClose]; the progress bar shows how
/// long is left, and it can be swiped away.
///
/// Bind it with [AppToast.of] *before* any `await` if the calling screen may
/// be popped meanwhile (the overlay it captures is the root one, so the toast
/// outlives the screen).
class AppToast {
  AppToast._(this._overlay, this._theme);

  final OverlayState _overlay;
  final ThemeData _theme;

  static AppToast of(BuildContext context) =>
      AppToast._(Overlay.of(context, rootOverlay: true), Theme.of(context));

  static const autoClose = Duration(seconds: 4);

  void show(
    String message, {
    ToastKind kind = ToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final scheme = _theme.colorScheme;
    final (type, color, icon) = switch (kind) {
      ToastKind.success => (
        ToastificationType.success,
        const Color(0xFF1E8E5A),
        Icons.check_circle_rounded,
      ),
      ToastKind.error => (
        ToastificationType.error,
        scheme.error,
        Icons.error_rounded,
      ),
      ToastKind.info => (
        ToastificationType.info,
        scheme.primary,
        Icons.info_rounded,
      ),
    };
    toastification.dismissAll(delayForAnimation: false);
    toastification.show(
      overlayState: _overlay,
      type: type,
      style: ToastificationStyle.flat,
      alignment: Alignment.topCenter,
      autoCloseDuration: autoClose,
      animationDuration: const Duration(milliseconds: 300),
      title: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      icon: Icon(icon, color: color),
      primaryColor: color,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color.withValues(alpha: 0.35)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      showProgressBar: true,
      progressBarTheme: ProgressIndicatorThemeData(
        color: color,
        linearTrackColor: color.withValues(alpha: 0.12),
      ),
      dragToClose: true,
      closeOnClick: false,
      closeButton: ToastCloseButton(
        showType: CloseButtonShowType.always,
        buttonBuilder: actionLabel == null
            ? null
            : (context, onClose) => TextButton(
                style: TextButton.styleFrom(foregroundColor: color),
                onPressed: () {
                  onClose();
                  onAction?.call();
                },
                child: Text(
                  actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
      ),
    );
  }
}

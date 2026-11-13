import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../l10n/app_localizations.dart';
import '../models/app_theme.dart';

class DeleteSongDialog extends StatelessWidget {
  final String songTitle;
  final AppThemeData appTheme;
  const DeleteSongDialog({
    super.key,
    required this.songTitle,
    required this.appTheme,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      backgroundColor: appTheme.dialogBg,
      title: Text(
        l10n.deleteSongTitle,
        style: TextStyle(color: appTheme.textPrimary),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deleteSongMessage(songTitle),
              style: TextStyle(color: appTheme.textPrimary),
            ),
            const SizedBox(height: 24),
            SlideToDelete(
              label: l10n.slideToDelete,
              appTheme: appTheme,
              onConfirmed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// Only a drag starting on the left thumb can confirm. Track taps, partial
/// drags and cancelled pointers never trigger deletion.
class SlideToDelete extends StatefulWidget {
  final String label;
  final AppThemeData appTheme;
  final VoidCallback onConfirmed;
  const SlideToDelete({
    super.key,
    required this.label,
    required this.appTheme,
    required this.onConfirmed,
  });

  @override
  State<SlideToDelete> createState() => _SlideToDeleteState();
}

class _SlideToDeleteState extends State<SlideToDelete> {
  double _progress = 0;
  double _startX = 0;
  bool _dragging = false;
  bool _confirmed = false;
  int? _pointer;

  void _onPointerUp(PointerUpEvent event) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        event.pointer != _pointer ||
        _confirmed) {
      return;
    }
    _pointer = null;
    if (_dragging && _progress >= 0.98) {
      _confirmed = true;
      widget.onConfirmed();
    } else {
      _reset();
    }
  }

  void _reset() {
    if (!mounted) return;
    setState(() {
      _progress = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Semantics(
      label: widget.label,
      child: SizedBox(
        height: 58,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final travel = (constraints.maxWidth - 58).clamp(
              1.0,
              double.infinity,
            );
            final duration = _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180);
            return ClipRRect(
              borderRadius: BorderRadius.circular(29),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.appTheme.surface,
                  border: Border.all(color: widget.appTheme.border),
                  borderRadius: BorderRadius.circular(29),
                ),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      width: 54 + _progress * travel,
                      height: 58,
                      color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: Opacity(
                          opacity: (1 - _progress * 1.5).clamp(0.0, 1.0),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 48, right: 14),
                            child: Text(
                              widget.label,
                              style: TextStyle(
                                color: widget.appTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: duration,
                      left: 4 + _progress * travel,
                      top: 4,
                      width: 50,
                      height: 50,
                      child: Listener(
                        onPointerDown: (event) => _pointer ??= event.pointer,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: (event) {
                          if (event.pointer == _pointer) {
                            _pointer = null;
                            _reset();
                          }
                        },
                        child: GestureDetector(
                          key: const ValueKey('delete-slider-thumb'),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onHorizontalDragStart: _confirmed
                              ? null
                              : (details) {
                                  _startX = details.globalPosition.dx;
                                  setState(() {
                                    _dragging = true;
                                    _progress = 0;
                                  });
                                },
                          onHorizontalDragUpdate: _confirmed
                              ? null
                              : (details) => setState(() {
                                  _progress =
                                      ((details.globalPosition.dx - _startX) /
                                              travel)
                                          .clamp(0.0, 1.0);
                                }),
                          onHorizontalDragCancel: _reset,
                          onHorizontalDragEnd: (_) {
                            if (!_confirmed) _reset();
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

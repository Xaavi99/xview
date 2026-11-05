import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'layout.dart';
import 'theme.dart';

/// One key. Fires on finger down, like a real keyboard, and repeats while
/// held when [repeat] is set.
class XKey extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onPress;
  final bool repeat;
  final bool active;
  final Color? color;
  final Color? textColor;
  final double fontSize;

  const XKey({
    Key? key,
    this.label,
    this.icon,
    required this.onPress,
    this.repeat = false,
    this.active = false,
    this.color,
    this.textColor,
    this.fontSize = 12,
  }) : super(key: key);

  @override
  State<XKey> createState() => _XKeyState();
}

class _XKeyState extends State<XKey> {
  bool _down = false;
  Timer? _delay;
  Timer? _repeat;

  void _start() {
    HapticFeedback.selectionClick();
    widget.onPress();
    setState(() => _down = true);
    if (widget.repeat) {
      _delay = Timer(const Duration(milliseconds: 380), () {
        _repeat = Timer.periodic(
            const Duration(milliseconds: 70), (_) => widget.onPress());
      });
    }
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.active ? kXviewTeal : (widget.color ?? kXviewKey);
    final bg = _down ? Color.lerp(base, Colors.white, 0.25)! : base;
    final fg = widget.textColor ?? kXviewText;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: Semantics(
        button: true,
        label: widget.label,
        child: Container(
          margin: const EdgeInsets.all(2.5),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: widget.icon != null
              ? Icon(widget.icon, color: fg, size: 18)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(widget.label ?? '',
                        style: TextStyle(
                            color: fg,
                            fontSize: widget.fontSize,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Draws one half of the keyboard from a layout in layout.dart.
/// [slots] fills the @name keys (map, title, buttons owned by the app).
class XKeyboardHalf extends StatelessWidget {
  final List<Object> rows;
  final XKeyboardController controller;
  final Map<String, Widget> slots;

  const XKeyboardHalf({
    Key? key,
    required this.rows,
    required this.controller,
    this.slots = const {},
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(children: [
          for (final r in rows)
            if (r is XBlock)
              Expanded(
                flex: r.rows.length,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6 - r.slotCols,
                      child: Column(children: [
                        for (final line in r.rows) _row(line),
                      ]),
                    ),
                    Expanded(flex: r.slotCols, child: _slot(r.slot)),
                  ],
                ),
              )
            else
              _row(r as String),
        ]),
      );

  Widget _row(String line) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (token, span) in _tokens(line))
              Expanded(flex: span, child: _key(token)),
          ],
        ),
      );

  /// Splits a row into (token, width) pairs, expanding $0..$5.
  List<(String, int)> _tokens(String line) {
    final out = <(String, int)>[];
    for (final part in line.split(RegExp(r'\s+'))) {
      if (part.isEmpty) continue;
      final m = RegExp(r'^\$(\d)$').firstMatch(part);
      if (m != null) {
        final i = int.parse(m.group(1)!);
        final fnRow = controller.fn ? xFnRows[i] : null;
        if (fnRow != null) {
          out.addAll(_tokens(fnRow));
        } else {
          out.addAll(controller.layerRow(i).map((c) => (c, 1)));
        }
        continue;
      }
      final colon = part.lastIndexOf(':');
      if (part.length > 2 && colon > 0) {
        final span = int.tryParse(part.substring(colon + 1));
        if (span != null) {
          out.add((part.substring(0, colon), span));
          continue;
        }
      }
      out.add((part, 1));
    }
    return out;
  }

  Widget _slot(String name) =>
      slots[name.startsWith('@') ? name.substring(1) : name] ??
      const SizedBox.shrink();

  Widget _key(String t) {
    if (t.startsWith('@')) return _slot(t);
    final c = controller;
    if (t.length == 1) {
      final shown = c.layer == 0 && c.shift ? t.toUpperCase() : t;
      return XKey(label: shown, onPress: () => c.tap(t), fontSize: 19);
    }
    final named = xNamedKeys[t];
    final color = xKeyColors[t];
    final isChar = t == 'Space';
    return XKey(
      label: t == 'Layer' ? c.layerLabel : (named?.label ?? t),
      icon: t == 'Shift' ? Icons.arrow_upward : named?.icon,
      repeat: named?.repeat ?? false,
      active: c.isOn(t),
      color: color ?? (isChar ? kXviewKey : kXviewKeyDark),
      textColor: isChar ? kXviewMuted : (color != null ? Colors.white : null),
      onPress: () => c.tap(t),
    );
  }
}

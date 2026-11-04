// xview built-in keyboard (layout C): two thumb halves, plus the logic that
// turns key taps into key presses on the laptop and a log of what was typed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../models/input_model.dart';
import '../models/platform_model.dart';
import 'xview.dart';

/// Which set of characters the letter keys show.
enum XLayer { letters, symbols, more }

const _letters = ['qwert', 'asdfg', 'zxcvb', 'yuiop', 'hjkl', 'nm,.'];
const _symbols = ['12345', '!@#\$%', ')-_=+', '67890', '^&*(', ';:\'"'];
const _more = ['[]{}\\', '?,.!@', '*()-+', '|`~<>', '#\$%&', '_=;:'];

/// Keyboard state: modifiers, layer and the typed-text log.
class XviewKeys extends ChangeNotifier {
  bool shift = false;
  bool ctrl = false;
  bool alt = false;
  bool win = false;
  bool fn = false;
  XLayer layer = XLayer.letters;

  /// Lines sent with Enter, oldest first, and the line being typed now.
  final List<String> history = [];
  String line = '';

  InputModel get _input => gFFI.inputModel;
  bool get _anyMod => ctrl || alt || win;

  List<String> row(int i) {
    switch (layer) {
      case XLayer.letters:
        return _letters[i].split('');
      case XLayer.symbols:
        return _symbols[i].split('');
      case XLayer.more:
        return _more[i].split('');
    }
  }

  String get layerLabel => const {
        XLayer.letters: '123',
        XLayer.symbols: '#+=',
        XLayer.more: 'abc',
      }[layer]!;

  void nextLayer() {
    layer = XLayer.values[(layer.index + 1) % XLayer.values.length];
    notifyListeners();
  }

  void toggle(String which) {
    switch (which) {
      case 'shift':
        shift = !shift;
        break;
      case 'ctrl':
        ctrl = !ctrl;
        break;
      case 'alt':
        alt = !alt;
        break;
      case 'win':
        win = !win;
        break;
      case 'fn':
        fn = !fn;
        break;
    }
    notifyListeners();
  }

  void _clearMods() {
    shift = ctrl = alt = win = false;
    _input.resetModifiers();
    notifyListeners();
  }

  void _log(String s) {
    line += s;
    notifyListeners();
  }

  /// A printable character. With Ctrl/Alt/Win held it becomes a shortcut.
  void char(String c) {
    if (_anyMod) {
      final isLetter = RegExp(r'^[a-zA-Z]$').hasMatch(c);
      _withMods(() => _input.inputKey(isLetter ? 'VK_${c.toUpperCase()}' : c));
      _log('[${_modPrefix()}${c.toUpperCase()}]');
      _clearMods();
      return;
    }
    final out = shift ? c.toUpperCase() : c;
    _input.inputKey(out);
    _log(out);
    if (shift) {
      shift = false;
      notifyListeners();
    }
  }

  /// A named key (Enter, Tab, arrows...). Every held modifier applies,
  /// including Shift, so Shift+Tab and Shift+arrows work.
  void vk(String name, {String? logAs}) {
    _withMods(() => _input.inputKey(name), useShift: true);
    switch (name) {
      case 'VK_RETURN':
        history.add(line);
        if (history.length > 50) history.removeAt(0);
        line = '';
        break;
      case 'VK_BACK':
        if (line.isNotEmpty) line = line.substring(0, line.length - 1);
        break;
      default:
        if (logAs != null) line += logAs;
    }
    _clearMods();
  }

  /// Ctrl plus a letter, for the ^C/^V style shortcut keys.
  void ctrlLetter(String letter) {
    _input.ctrl = true;
    _input.inputKey('VK_$letter');
    _input.ctrl = false;
    _log('[Ctrl+$letter]');
  }

  void _withMods(void Function() send, {bool useShift = false}) {
    _input.ctrl = ctrl;
    _input.alt = alt;
    _input.command = win;
    _input.shift = useShift && shift;
    send();
  }

  String _modPrefix() =>
      '${ctrl ? 'Ctrl+' : ''}${alt ? 'Alt+' : ''}${win ? 'Win+' : ''}';

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    bind.sessionInputString(sessionId: gFFI.sessionId, value: text);
    _log(text);
  }

  void clearLog() {
    history.clear();
    line = '';
    notifyListeners();
  }
}

/// One key. Fires on finger down, like a real keyboard, and can repeat
/// while held (Backspace, arrows, scroll).
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
    this.fontSize = 13,
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
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(8)),
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

/// A row of keys; [flex] gives each key its width in grid columns.
Widget xRow(List<(Widget, int)> keys) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final k in keys) Expanded(flex: k.$2, child: k.$1)],
      ),
    );

XKey _special(String label, VoidCallback onPress,
        {bool repeat = false, bool active = false, Color? color}) =>
    XKey(
        label: label,
        onPress: onPress,
        repeat: repeat,
        active: active,
        color: color ?? kXviewKeyDark,
        fontSize: 12);

XKey _iconKey(IconData icon, String label, VoidCallback onPress,
        {bool repeat = false}) =>
    XKey(
        icon: icon,
        label: label,
        onPress: onPress,
        repeat: repeat,
        color: kXviewKeyDark);

List<(Widget, int)> _chars(XviewKeys k, int row) => [
      for (final c in k.row(row))
        (
          XKey(
              label: k.layer == XLayer.letters && k.shift ? c.toUpperCase() : c,
              onPress: () => k.char(c),
              fontSize: 19),
          1
        )
    ];

List<(Widget, int)> _fnRow(XviewKeys k, List<String> names) => [
      for (final n in names)
        (_special(n.replaceFirst('VK_', ''), () => k.vk(n)), 1)
    ];

/// Left half, below its header row: 5 rows of 6 columns.
Widget xviewLeftKeys(XviewKeys k) => Column(children: [
      xRow([
        (_special('Fn', () => k.toggle('fn'), active: k.fn), 1),
        (_special('Win', () => k.toggle('win'), active: k.win), 1),
        (_special('PgUp', () => k.vk('VK_PRIOR'), repeat: true), 1),
        (_special('PgDn', () => k.vk('VK_NEXT'), repeat: true), 1),
        (_special('^S', () => k.ctrlLetter('S')), 1),
        (_special('^A', () => k.ctrlLetter('A')), 1),
      ]),
      xRow([
        (_special('Esc', () => k.vk('VK_ESCAPE')), 1),
        ...(k.fn
            ? _fnRow(k, ['VK_F1', 'VK_F2', 'VK_F3', 'VK_F4', 'VK_F5'])
            : _chars(k, 0)),
      ]),
      xRow([
        (_special('Tab', () => k.vk('VK_TAB', logAs: '⇥'), color: const Color(0xFF134E4A)), 1),
        ..._chars(k, 1),
      ]),
      xRow([
        (
          XKey(
              icon: Icons.arrow_upward,
              label: 'Shift',
              onPress: () => k.toggle('shift'),
              active: k.shift,
              color: kXviewKeyDark),
          1
        ),
        ..._chars(k, 2),
      ]),
      xRow([
        (_special('Ctrl', () => k.toggle('ctrl'), active: k.ctrl), 1),
        (_special('Alt', () => k.toggle('alt'), active: k.alt), 1),
        (_special(k.layerLabel, k.nextLayer), 1),
        (XKey(label: 'space', onPress: () => k.vk('VK_SPACE', logAs: ' '), fontSize: 12, textColor: kXviewMuted), 3),
      ]),
    ]);

/// Right half: [top] is the 2-row block left of the map (built by the caller,
/// who owns the map), then 4 rows of letters, Enter and arrows.
Widget xviewRightTopKeys(XviewKeys k) => Column(children: [
      xRow([
        (_special('^Z', () => k.ctrlLetter('Z')), 1),
        (_special('^C', () => k.ctrlLetter('C')), 1),
        (_special('^V', () => k.ctrlLetter('V')), 1),
      ]),
      xRow([
        (_special('Del', () => k.vk('VK_DELETE'), repeat: true), 1),
        (_special('Home', () => k.vk('VK_HOME')), 1),
        (_special('End', () => k.vk('VK_END')), 1),
      ]),
    ]);

Widget xviewRightKeys(XviewKeys k) => Column(children: [
      xRow([
        ...(k.fn
            ? _fnRow(k, ['VK_F6', 'VK_F7', 'VK_F8', 'VK_F9', 'VK_F10'])
            : _chars(k, 3)),
        (_iconKey(Icons.backspace_outlined, 'Backspace', () => k.vk('VK_BACK'), repeat: true), 1),
      ]),
      xRow([
        ...(k.fn
            ? _fnRow(k, ['VK_F11', 'VK_F12', 'VK_INSERT', 'VK_SNAPSHOT'])
            : _chars(k, 4)),
        (
          XKey(
              icon: Icons.keyboard_return,
              label: 'Enter',
              onPress: () => k.vk('VK_RETURN'),
              color: kXviewTeal,
              textColor: Colors.white),
          2
        ),
      ]),
      xRow([
        ..._chars(k, 5),
        (_iconKey(Icons.keyboard_arrow_up, 'Up', () => k.vk('VK_UP'), repeat: true), 1),
        (XKey(label: '/', onPress: () => k.char('/'), fontSize: 19), 1),
      ]),
      xRow([
        (XKey(label: 'space', onPress: () => k.vk('VK_SPACE', logAs: ' '), fontSize: 12, textColor: kXviewMuted), 3),
        (_iconKey(Icons.keyboard_arrow_left, 'Left', () => k.vk('VK_LEFT'), repeat: true), 1),
        (_iconKey(Icons.keyboard_arrow_down, 'Down', () => k.vk('VK_DOWN'), repeat: true), 1),
        (_iconKey(Icons.keyboard_arrow_right, 'Right', () => k.vk('VK_RIGHT'), repeat: true), 1),
      ]),
    ]);

/// Mouse buttons and wheel, for the trackpad.
Future<void> xviewClick(MouseButtons b) => gFFI.inputModel.tap(b);
Future<void> xviewWheel(int y) => gFFI.inputModel.scroll(y);

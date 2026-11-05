import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;

import 'layout.dart';

/// Modifiers to hold while a key is sent.
class XMods {
  final bool ctrl, alt, shift, win;
  const XMods({this.ctrl = false, this.alt = false, this.shift = false, this.win = false});
}

/// Sends one key to the laptop. [name] is either a character ("a", "!")
/// or a RustDesk key name ("VK_RETURN", "VK_C").
typedef XKeySender = void Function(String name, XMods mods);

/// A named key: what it sends, how it looks, whether holding it repeats.
class XNamedKey {
  final String vk;
  final String? label;
  final IconData? icon;
  final bool repeat;
  final String? logAs;
  const XNamedKey(this.vk, {this.label, this.icon, this.repeat = false, this.logAs});
}

const xNamedKeys = <String, XNamedKey>{
  'Esc': XNamedKey('VK_ESCAPE'),
  'Tab': XNamedKey('VK_TAB', logAs: '⇥'),
  'Enter': XNamedKey('VK_RETURN', icon: Icons.keyboard_return),
  'Bksp': XNamedKey('VK_BACK', icon: Icons.backspace_outlined, repeat: true),
  'Del': XNamedKey('VK_DELETE', repeat: true),
  'Home': XNamedKey('VK_HOME'),
  'End': XNamedKey('VK_END'),
  'PgUp': XNamedKey('VK_PRIOR', repeat: true),
  'PgDn': XNamedKey('VK_NEXT', repeat: true),
  'Ins': XNamedKey('VK_INSERT'),
  'PrtSc': XNamedKey('VK_SNAPSHOT'),
  'Space': XNamedKey('VK_SPACE', label: 'space', logAs: ' '),
  'Up': XNamedKey('VK_UP', icon: Icons.keyboard_arrow_up, repeat: true),
  'Down': XNamedKey('VK_DOWN', icon: Icons.keyboard_arrow_down, repeat: true),
  'Left': XNamedKey('VK_LEFT', icon: Icons.keyboard_arrow_left, repeat: true),
  'Right': XNamedKey('VK_RIGHT', icon: Icons.keyboard_arrow_right, repeat: true),
  'F1': XNamedKey('VK_F1'),
  'F2': XNamedKey('VK_F2'),
  'F3': XNamedKey('VK_F3'),
  'F4': XNamedKey('VK_F4'),
  'F5': XNamedKey('VK_F5'),
  'F6': XNamedKey('VK_F6'),
  'F7': XNamedKey('VK_F7'),
  'F8': XNamedKey('VK_F8'),
  'F9': XNamedKey('VK_F9'),
  'F10': XNamedKey('VK_F10'),
  'F11': XNamedKey('VK_F11'),
  'F12': XNamedKey('VK_F12'),
};

const xModifierKeys = {'Shift', 'Ctrl', 'Alt', 'Win', 'Fn'};

/// Keyboard state (modifiers, layer, Fn) and the log of what was typed.
class XKeyboardController extends ChangeNotifier {
  final XKeySender send;
  XKeyboardController({required this.send});

  bool shift = false, ctrl = false, alt = false, win = false, fn = false;
  int layer = 0;

  /// Lines sent with Enter, oldest first, and the line being typed now.
  final List<String> history = [];
  String line = '';

  bool isOn(String modifier) => switch (modifier) {
        'Shift' => shift,
        'Ctrl' => ctrl,
        'Alt' => alt,
        'Win' => win,
        'Fn' => fn,
        _ => false,
      };

  String get layerLabel => xLayerLabels[layer];

  /// The characters of row [i] in the current layer.
  List<String> layerRow(int i) => xLayers[layer][i].split('');

  /// Handles a tap on any key token from the layout.
  void tap(String token) {
    if (token.length == 1) return char(token);
    if (xModifierKeys.contains(token)) return _toggle(token);
    if (token == 'Layer') {
      layer = (layer + 1) % xLayers.length;
      return notifyListeners();
    }
    if (token.length == 2 && token.startsWith('^')) return ctrlLetter(token[1]);
    final k = xNamedKeys[token];
    if (k != null) named(k);
  }

  void _toggle(String m) {
    switch (m) {
      case 'Shift':
        shift = !shift;
      case 'Ctrl':
        ctrl = !ctrl;
      case 'Alt':
        alt = !alt;
      case 'Win':
        win = !win;
      case 'Fn':
        fn = !fn;
    }
    notifyListeners();
  }

  void _clearMods() {
    shift = ctrl = alt = win = false;
    notifyListeners();
  }

  /// A printable character. With Ctrl, Alt or Win on it becomes a shortcut.
  void char(String c) {
    if (ctrl || alt || win) {
      final letter = RegExp(r'^[a-zA-Z]$').hasMatch(c);
      send(letter ? 'VK_${c.toUpperCase()}' : c,
          XMods(ctrl: ctrl, alt: alt, win: win));
      log('[${ctrl ? 'Ctrl+' : ''}${alt ? 'Alt+' : ''}${win ? 'Win+' : ''}${c.toUpperCase()}]');
      return _clearMods();
    }
    final out = shift ? c.toUpperCase() : c;
    send(out, const XMods());
    log(out);
    if (shift) _clearMods();
  }

  /// A named key. Every modifier that is on applies, Shift included, so
  /// Shift+Tab and Shift+arrows work.
  void named(XNamedKey k) {
    send(k.vk, XMods(ctrl: ctrl, alt: alt, shift: shift, win: win));
    if (k.vk == 'VK_RETURN') {
      history.add(line);
      if (history.length > 50) history.removeAt(0);
      line = '';
    } else if (k.vk == 'VK_BACK') {
      if (line.isNotEmpty) line = line.substring(0, line.length - 1);
    } else if (k.logAs != null) {
      line += k.logAs!;
    }
    _clearMods();
  }

  void ctrlLetter(String letter) {
    send('VK_${letter.toUpperCase()}', const XMods(ctrl: true));
    log('[Ctrl+${letter.toUpperCase()}]');
  }

  /// Adds text to the typed log (for paste, which the app sends itself).
  void log(String s) {
    line += s;
    notifyListeners();
  }

  void clearLog() {
    history.clear();
    line = '';
    notifyListeners();
  }
}

// THE KEYBOARD LAYOUT. To move, add or remove keys, edit this file only.
//
// Each half is a list of rows, top to bottom; every row gets the same height.
// A row is keys separated by spaces. Add :N to a key to make it N columns
// wide (each half is 6 columns).
//
// Keys:
//   a single character     types it:  q  /  ,
//   $0 .. $5               that row of the current layer (see xLayers)
//   Esc Tab Enter Bksp Del Home End PgUp PgDn Ins PrtSc
//   Space Up Down Left Right F1 .. F12
//   Shift Ctrl Alt Win     one-shot: applies to the next key, then turns off
//   Fn                     swaps rows $0, $3 and $4 for xFnRows
//   Layer                  letters -> symbols -> more symbols -> letters
//   ^A .. ^Z               Ctrl + that letter
//   @name                  a slot the app fills in: @back @title @phonekb
//                          @rotate @map @zoomout @zoomin @fit @pan @hold
//                          @full
//
// Key rows are square (see xKeyHeight). A row made only of @slots stretches
// to share whatever height is left over, so the map and the header grow
// instead of the keys.
//
// XBlock(rows, slot) puts a slot beside some rows and makes it as tall as
// all of them.

import 'package:flutter/painting.dart';

import 'theme.dart';

class XBlock {
  final List<String> rows;
  final String slot;
  final int slotCols;
  const XBlock(this.rows, {required this.slot, this.slotCols = 3});
}

/// How much of the screen width each keyboard half takes (0.30 = 30%).
/// The laptop view in the middle gets the rest.
const xSideWidth = 0.30;

/// Key height divided by key width. 1.0 makes square keys.
const xKeyHeight = 1.0;

const xLeft = <Object>[
  '@back @title:3 @phonekb @rotate',
  '@zoomout @zoomin @fit @pan @hold @full',
  'Fn Win PgUp PgDn ^S ^A',
  r'Esc $0',
  r'Tab $1',
  r'Shift $2',
  'Ctrl Alt Layer Space:3',
];

const xRight = <Object>[
  '@map:6',
  '^Z ^C ^V Del Home End',
  r'$3 Bksp',
  r'$4 Enter:2',
  r'$5 Up /',
  'Space:3 Left Down Right',
];

/// Characters for $0..$5, one list per layer: letters, symbols, more.
const xLayers = <List<String>>[
  ['qwert', 'asdfg', 'zxcvb', 'yuiop', 'hjkl', 'nm,.'],
  ['12345', r'!@#$%', ')-_=+', '67890', '^&*(', ';:\'"'],
  [r'[]{}\', '?,.!@', '*()-+', '|`~<>', r'#$%&', '_=;:'],
];

/// What the Layer key says in each layer (it names the next one).
const xLayerLabels = ['123', '#+=', 'abc'];

/// Rows used instead of $0, $3 and $4 while Fn is on.
const xFnRows = <int, String>{
  0: 'F1 F2 F3 F4 F5',
  3: 'F6 F7 F8 F9 F10',
  4: 'F11 F12 Ins PrtSc',
};

/// Tablet keyboard (OnePlus Pad 2 and other screens 600+ wide on their
/// short side): one full laptop-style keyboard, 15 columns, 6 rows.
const xTabletColumns = 15;
const xTablet = <Object>[
  'Esc F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 Ins Del',
  '` 1 2 3 4 5 6 7 8 9 0 - = Bksp:2',
  r'Tab:2 q w e r t y u i o p [ ] ',
  "Ctrl:2 a s d f g h j k l ; ' Enter:2",
  'Shift:2 z x c v b n m , . / Home Up End',
  'Win Alt ^Z Space:7 ^C ^V Left Down Right',
];

/// What Shift turns a key into (US layout). Letters just become capitals.
const xShiftMap = <String, String>{
  '`': '~', '1': '!', '2': '@', '3': '#', '4': r'$', '5': '%', '6': '^',
  '7': '&', '8': '*', '9': '(', '0': ')', '-': '_', '=': '+', '[': '{',
  ']': '}', r'': '|', ';': ':', "'": '"', ',': '<', '.': '>', '/': '?',
};

/// Key colours that differ from the defaults.
const xKeyColors = <String, Color>{
  'Enter': kXviewTeal,
  'Tab': kXviewTealDark,
};

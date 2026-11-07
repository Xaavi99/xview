# xview_keyboard

The xview phone keyboard (layout C), kept apart from RustDesk's code so it can
be changed on its own.

## Changing the layout

Edit **`lib/src/layout.dart`** only. Each half of the keyboard is a list of
rows, and each row is key names separated by spaces:

```dart
const xLeft = <Object>[
  '@back @title:3 @phonekb @rotate',
  'Fn Win PgUp PgDn ^S ^A',
  r'Esc $0',          // Esc, then the 5 characters of layer row 0 (q w e r t)
  ...
];
```

- `:N` makes a key N columns wide (each half has 6).
- `$0`..`$5` are the character rows in `xLayers` (letters, symbols, more).
- `@name` is a slot the app fills: `@back`, `@title`, `@phonekb`, `@rotate`,
  `@map`, `@zoomout`, `@zoomin`, `@fit`, `@pan`, `@hold`, `@full`. A row made only of
  slots stretches to use the spare height; key rows stay square.
- `xSideWidth` sets how wide each half is; `xKeyHeight` sets the key shape
  (1.0 = square).
- The comment at the top of `layout.dart` lists every key name.

Moving a key is a one-line change there, and nothing else in the app needs to
change. Push it to the `xview` branch and the Android build picks it up.

## Tablet keyboard

`xTablet` in the same file is the full keyboard used on tablets (15 columns,
`xTabletColumns`). It is edited the same way. `xShiftMap` says what Shift
turns each symbol key into (1 to !, and so on).

## What else is here

- `lib/src/controller.dart`: modifiers, layers, Fn, the typed-text log, and
  the table of named keys (what `Esc`, `Enter`, `F5`... send).
- `lib/src/widgets.dart`: the key widget and the half-keyboard that draws a
  layout.
- `lib/src/theme.dart`: colours.

The package has no RustDesk code. The app gives it one function that sends a
key to the laptop (`flutter/lib/xview/remote_body.dart`, `_sendKey`).

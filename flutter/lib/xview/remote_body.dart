// xview remote screen (layout C, landscape):
//
//   +------------+---------------------+------------+
//   | left keys  |  laptop view (16:9) | map | keys |
//   |            +---------------------+ right keys |
//   |            | typed text / pad    |            |
//   +------------+---------------------+------------+
//
// RustDesk still draws the laptop picture and handles touches on it across
// the whole screen, exactly as before. The panels sit on top of it and
// swallow touches, so the "view" is the hole they leave in the middle.
// Keeping RustDesk's coordinates untouched is what keeps tap-to-click,
// pinch-zoom and the cursor maths correct.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xview_keyboard/xview_keyboard.dart';

import '../common.dart';
import '../common/widgets/dialog.dart';
import '../common/widgets/remote_input.dart';
import '../models/input_model.dart';
import '../models/platform_model.dart';
import 'xview.dart';

class XviewRemoteBody extends StatefulWidget {
  final String id;

  /// RustDesk's picture of the laptop (image and cursor), full screen.
  final Widget canvas;

  /// Opens the phone's own keyboard (Honor, Gboard...), RustDesk's way.
  final VoidCallback openPhoneKeyboard;

  /// RustDesk's hidden text field that the phone keyboard types into.
  final Widget phoneKeyboardField;

  const XviewRemoteBody({
    Key? key,
    required this.id,
    required this.canvas,
    required this.openPhoneKeyboard,
    required this.phoneKeyboardField,
  }) : super(key: key);

  @override
  State<XviewRemoteBody> createState() => _XviewRemoteBodyState();
}

/// Sends a key from the xview keyboard to the laptop.
void _sendKey(String name, XMods m) {
  final input = gFFI.inputModel;
  input.ctrl = m.ctrl;
  input.alt = m.alt;
  input.shift = m.shift;
  input.command = m.win;
  input.inputKey(name);
  input.resetModifiers();
}

Future<void> _click(MouseButtons b) => gFFI.inputModel.tap(b);
Future<void> _wheel(int y) => gFFI.inputModel.scroll(y);

Future<void> _paste() async {
  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  if (text.isEmpty) return;
  bind.sessionInputString(sessionId: gFFI.sessionId, value: text);
  _keys.log(text);
}

// Shared, so the typed text and Shift/Ctrl state survive turning the phone
// (RustDesk rebuilds this part of the screen on rotation and on connect).
final _keys = XKeyboardController(send: _sendKey);

class _XviewRemoteBodyState extends State<XviewRemoteBody> {
  bool _full = false;
  bool _pad = false;
  bool _panMode = false;
  Rect? _hole;
  Timer? _fitTimer;

  @override
  void initState() {
    super.initState();
    _keys.addListener(_rebuild);
    gFFI.imageModel.addCallbackOnFirstImage((_) => _scheduleFit());
  }

  @override
  void dispose() {
    _fitTimer?.cancel();
    _keys.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// RustDesk re-fits the picture to the whole screen after rotating or
  /// connecting, so fit it to the view a moment after that settles.
  void _scheduleFit() {
    _fitTimer?.cancel();
    _fitTimer = Timer(const Duration(milliseconds: 500), _fitToHole);
  }

  void _fitToHole() {
    final img = gFFI.imageModel.image;
    final hole = _hole;
    if (img == null || hole == null || _full) return;
    final cm = gFFI.canvasModel;
    if (cm.scale <= 0) return;
    final target = min(hole.width / img.width, hole.height / img.height);
    cm.updateScale(target / cm.scale, Offset.zero);
    final w = img.width * cm.scale;
    final h = img.height * cm.scale;
    cm.panX(hole.left + (hole.width - w) / 2 - cm.x);
    cm.panY(hole.top + max(0.0, (hole.height - h) / 2) - cm.y);
  }

  void _zoom(double factor) {
    final hole = _hole;
    if (hole == null) return;
    gFFI.canvasModel.updateScale(factor, hole.center);
  }

  void _setFull(bool full) {
    setState(() => _full = full);
    if (full) {
      gFFI.canvasModel.reset();
    } else {
      _scheduleFit();
    }
  }

  /// Opaque, so touches on a panel never reach the laptop picture below.
  Widget _panel(Widget child) => Listener(
        behavior: HitTestBehavior.opaque,
        child: Container(color: kXviewBg, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final remote = Positioned.fill(
      child: RawTouchGestureDetectorRegion(child: widget.canvas, ffi: gFFI),
    );
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      if (_full) {
        return Stack(children: [
          remote,
          Positioned(
            left: 8,
            top: h / 2 - 30,
            child: _RoundButton(
              icon: Icons.keyboard,
              label: 'Keys',
              onTap: () => _setFull(false),
            ),
          ),
        ]);
      }
      final side = (w * xSideWidth).floorToDouble();
      final mid = w - 2 * side;
      final viewH = min(mid * 9 / 16, h * 0.72).floorToDouble();
      final hole = Rect.fromLTWH(side, 0, mid, viewH);
      if (hole != _hole) {
        _hole = hole;
        _scheduleFit();
      }
      return Stack(children: [
        remote,
        if (_panMode)
          Positioned.fromRect(rect: hole, child: _PanZoomLayer(origin: hole.topLeft)),
        Positioned(
          left: 0,
          top: 0,
          width: side,
          height: h,
          child: _panel(_leftHalf()),
        ),
        Positioned(
          left: side + mid,
          top: 0,
          width: side,
          height: h,
          child: _panel(_rightHalf(hole)),
        ),
        Positioned(
          left: side,
          top: viewH,
          width: mid,
          height: h - viewH,
          child: _panel(_bottom()),
        ),
        widget.phoneKeyboardField,
      ]);
    });
  }

  Widget _leftHalf() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 2, 6),
        child: XKeyboardHalf(rows: xLeft, controller: _keys, slots: {
          'back': _IconOnly(
              icon: Icons.arrow_back,
              label: 'Disconnect',
              onTap: () => clientClose(gFFI.sessionId, gFFI)),
          'title': Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Laptop',
                    style: TextStyle(
                        color: kXviewText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(widget.id,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kXviewMuted,
                        fontSize: 10,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          'phonekb': _IconOnly(
              icon: Icons.keyboard_alt_outlined,
              label: 'Phone keyboard',
              onTap: widget.openPhoneKeyboard),
          'rotate': _IconOnly(
              icon: Icons.screen_rotation,
              label: 'Portrait',
              onTap: () => xviewToggleOrientation(context)),
          'zoomout': XKey(
              icon: Icons.zoom_out,
              label: 'Zoom out',
              repeat: true,
              color: kXviewKeyDark,
              onPress: () => _zoom(0.9)),
          'zoomin': XKey(
              icon: Icons.zoom_in,
              label: 'Zoom in',
              repeat: true,
              color: kXviewKeyDark,
              onPress: () => _zoom(1.1)),
          'fit': XKey(
              label: 'Fit', color: kXviewKeyDark, onPress: _fitToHole),
          'pan': XKey(
              icon: Icons.open_with,
              label: 'Pan',
              active: _panMode,
              color: kXviewKeyDark,
              onPress: () => setState(() => _panMode = !_panMode)),
          'full': XKey(
              icon: Icons.fullscreen,
              label: 'Full screen',
              color: kXviewKeyDark,
              onPress: () => _setFull(true)),
        }),
      );

  Widget _rightHalf(Rect hole) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 4, 6),
        child: XKeyboardHalf(rows: xRight, controller: _keys, slots: {
          'map': _MapKey(
            hole: hole,
            onTap: () => _setFull(true),
            onLongPress: _fitToHole,
          ),
        }),
      );

  Widget _bottom() => Container(
        color: kXviewPanel,
        padding: const EdgeInsets.all(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pad
                ? SizedBox(width: 150, child: _typedViewer(compact: true))
                : Expanded(child: _typedViewer(compact: false)),
            if (_pad) const SizedBox(width: 6),
            if (_pad) const Expanded(child: _Trackpad()),
          ],
        ),
      );

  Widget _typedViewer({required bool compact}) {
    final lines = _keys.history.reversed.take(compact ? 2 : 4).toList().reversed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TYPED',
            style: TextStyle(
                color: kXviewMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
        const SizedBox(height: 2),
        for (final l in lines)
          Text('↵ $l',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: kXviewMuted, fontSize: 11, fontFamily: 'monospace')),
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            child: Text('${_keys.line}▏',
                style: const TextStyle(
                    color: kXviewText, fontSize: 14, fontFamily: 'monospace')),
          ),
        ),
        SizedBox(
          height: 36,
          child: Row(children: [
            _SmallButton(
                label: 'T',
                tooltip: 'Trackpad',
                active: _pad,
                onTap: () => setState(() => _pad = !_pad)),
            _SmallButton(
                icon: Icons.content_paste, tooltip: 'Paste', onTap: _paste),
            _SmallButton(
                icon: Icons.close, tooltip: 'Clear', onTap: _keys.clearLog),
          ]),
        ),
      ],
    );
  }
}

/// Miniature of the whole laptop screen. The teal box is what the middle
/// view shows: drag it to move the view, tap for full screen, long-press to
/// fit the whole screen back into the view.
class _MapKey extends StatelessWidget {
  final Rect hole;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MapKey(
      {required this.hole, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: kXviewKey,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kXviewTealLight),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onLongPress,
              onPanUpdate: (d) {
                final img = gFFI.imageModel.image;
                if (img == null) return;
                final k = _MapPainter.fit(size, img.width, img.height).width /
                    img.width;
                final cm = gFFI.canvasModel;
                cm.panX(-d.delta.dx / k * cm.scale);
                cm.panY(-d.delta.dy / k * cm.scale);
              },
              child: AnimatedBuilder(
                animation:
                    Listenable.merge([gFFI.imageModel, gFFI.canvasModel]),
                builder: (_, __) => CustomPaint(
                    size: size, painter: _MapPainter(hole: hole)),
              ),
            );
          }),
        ),
        const SizedBox(height: 3),
        const Text('Tap: full screen',
            style: TextStyle(color: kXviewMuted, fontSize: 9)),
      ]),
    );
  }
}

class _MapPainter extends CustomPainter {
  final Rect hole;
  _MapPainter({required this.hole});

  /// Where an image of [iw] x [ih] lands when fitted inside [size].
  static Rect fit(Size size, int iw, int ih) {
    final k = min(size.width / iw, size.height / ih);
    final w = iw * k, h = ih * k;
    return Rect.fromLTWH(
        (size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final img = gFFI.imageModel.image;
    if (img == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF24485A));
      return;
    }
    final dst = fit(size, img.width, img.height);
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.low);
    final cm = gFFI.canvasModel;
    if (cm.scale <= 0) return;
    final k = dst.width / img.width;
    final box = Rect.fromLTWH(
      dst.left + (hole.left - cm.x) / cm.scale * k,
      dst.top + (hole.top - cm.y) / cm.scale * k,
      hole.width / cm.scale * k,
      hole.height / cm.scale * k,
    ).intersect(dst);
    if (box.width <= 0 || box.height <= 0) return;
    canvas.drawRect(box, Paint()..color = const Color(0x2E2DD4BF));
    canvas.drawRect(
        box,
        Paint()
          ..color = kXviewTealLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Pan mode: covers the view so one finger moves the picture and a pinch
/// zooms it, instead of clicking on the laptop.
class _PanZoomLayer extends StatefulWidget {
  final Offset origin;
  const _PanZoomLayer({required this.origin});

  @override
  State<_PanZoomLayer> createState() => _PanZoomLayerState();
}

class _PanZoomLayerState extends State<_PanZoomLayer> {
  double _last = 1;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _last = 1,
        onScaleUpdate: (d) {
          final cm = gFFI.canvasModel;
          if (d.scale != _last && _last > 0) {
            cm.updateScale(d.scale / _last, widget.origin + d.localFocalPoint);
            _last = d.scale;
          }
          cm.panX(d.focalPointDelta.dx);
          cm.panY(d.focalPointDelta.dy);
        },
        child: Container(
          decoration: BoxDecoration(
              border: Border.all(color: kXviewTealLight, width: 2)),
        ),
      );
}

/// Trackpad: drag to move the pointer, tap to click, two fingers or the
/// arrows to scroll.
class _Trackpad extends StatefulWidget {
  const _Trackpad();

  @override
  State<_Trackpad> createState() => _TrackpadState();
}

class _TrackpadState extends State<_Trackpad> {
  double _scroll = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _click(MouseButtons.left),
                onScaleStart: (_) => _scroll = 0,
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) {
                    _scroll += d.focalPointDelta.dy;
                    while (_scroll > 14) {
                      _wheel(1);
                      _scroll -= 14;
                    }
                    while (_scroll < -14) {
                      _wheel(-1);
                      _scroll += 14;
                    }
                  } else {
                    gFFI.cursorModel.updatePan(
                        d.focalPointDelta * 1.6, d.localFocalPoint, false);
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16272A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kXviewKeyDark),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Trackpad\ndrag to move · tap to click\ntwo fingers to scroll',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: kXviewMuted, fontSize: 10, height: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 48,
              child: Column(children: [
                Expanded(
                    child: XKey(
                        icon: Icons.keyboard_arrow_up,
                        label: 'Scroll up',
                        repeat: true,
                        color: kXviewKeyDark,
                        onPress: () => _wheel(1))),
                Expanded(
                    child: XKey(
                        icon: Icons.keyboard_arrow_down,
                        label: 'Scroll down',
                        repeat: true,
                        color: kXviewKeyDark,
                        onPress: () => _wheel(-1))),
              ]),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 34,
        child: Row(children: [
          Expanded(
              child: XKey(
                  label: 'Left click',
                  color: kXviewKeyDark,
                  fontSize: 11,
                  onPress: () => _click(MouseButtons.left))),
          Expanded(
              child: XKey(
                  label: 'Right click',
                  color: kXviewKeyDark,
                  fontSize: 11,
                  onPress: () => _click(MouseButtons.right))),
          const SizedBox(width: 52),
        ]),
      ),
    ]);
  }
}

class _IconOnly extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _IconOnly(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: kXviewText, size: 20),
        onPressed: onTap,
      );
}

class _SmallButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  const _SmallButton(
      {this.label,
      this.icon,
      required this.tooltip,
      this.active = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: active ? kXviewTeal : kXviewKey,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 36,
                child: Center(
                  child: icon != null
                      ? Icon(icon, size: 18, color: kXviewText)
                      : Text(label ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: kXviewKey,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kXviewTealLight)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: kXviewText, size: 22),
                Text(label,
                    style: const TextStyle(color: kXviewText, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
}

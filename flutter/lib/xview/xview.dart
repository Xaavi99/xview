// xview phone app: a controller-only front end for the Android build.
//
// The phone only ever controls the laptop over Tailscale, so Android opens
// this screen instead of RustDesk's home page (which also shares the phone's
// own screen, chats, transfers files and so on). Everything else is reused
// from RustDesk: connect(), the password dialog, the remote session.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xview_keyboard/xview_keyboard.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';

/// The xview phone layout replaces RustDesk's mobile UI on Android.
bool get isXviewPhone => isAndroid;

const _kSavedLaptops = 'xview-laptops';
const _kMaxSaved = 5;


/// Sessions start sideways (layout C). Called when the remote page opens.
void xviewSessionStart() => SystemChrome.setPreferredOrientations(
    [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

/// Back to the phone's normal rotation when the session closes.
void xviewSessionEnd() => SystemChrome.setPreferredOrientations([]);

/// The rotate button: sideways (layout C) <-> upright (RustDesk's screen).
void xviewToggleOrientation(BuildContext context) {
  final sideways =
      MediaQuery.of(context).orientation == Orientation.landscape;
  SystemChrome.setPreferredOrientations(sideways
      ? [DeviceOrientation.portraitUp]
      : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
}

/// Upright, RustDesk's own screen gets a small button to go back sideways.
Widget xviewPortraitWrap(Widget child) {
  if (!isXviewPhone) return child;
  return Stack(fit: StackFit.expand, children: [
    child,
    Positioned(
      top: 8,
      left: 8,
      child: Builder(
        builder: (context) => Material(
          color: const Color(0xCC1F2A2D),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Landscape keyboard',
            icon: const Icon(Icons.screen_rotation, color: kXviewTealLight),
            onPressed: () => xviewToggleOrientation(context),
          ),
        ),
      ),
    ),
  ]);
}

/// Defaults for every session from this phone.
Future<void> _applyXviewDefaults() async {
  // The middle view behaves like a touch screen: tap to click where you tap.
  // Moving the pointer is the trackpad's job.
  await bind.mainSetLocalOption(key: kOptionTouchMode, value: 'Y');
  // No laptop sound on the phone: saves data and battery.
  await bind.mainSetUserDefaultOption(key: kOptionDisableAudio, value: 'Y');
}

class XviewHomePage extends StatefulWidget {
  const XviewHomePage({Key? key}) : super(key: key);

  @override
  State<XviewHomePage> createState() => _XviewHomePageState();
}

class _XviewHomePageState extends State<XviewHomePage> {
  final _controller = TextEditingController();
  List<String> _saved = [];

  @override
  void initState() {
    super.initState();
    _applyXviewDefaults();
    _saved = _loadSaved();
    if (_saved.isNotEmpty) _controller.text = _saved.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _loadSaved() => bind
      .mainGetLocalOption(key: _kSavedLaptops)
      .split(',')
      .where((e) => e.trim().isNotEmpty)
      .toList();

  Future<void> _save(List<String> list) async {
    await bind.mainSetLocalOption(key: _kSavedLaptops, value: list.join(','));
    setState(() => _saved = list);
  }

  Future<void> _connect(String ip) async {
    ip = ip.trim();
    if (ip.isEmpty) return;
    final list = [ip, ..._saved.where((e) => e != ip)].take(_kMaxSaved).toList();
    await _save(list);
    if (!mounted) return;
    connect(context, ip);
  }

  bool _looksLikeTailscale(String ip) =>
      ip.startsWith('100.') || ip.toLowerCase().startsWith('fd7a:');

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim();
    return Scaffold(
      backgroundColor: kXviewBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: kXviewTeal, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.desktop_windows_outlined,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text('xview',
                  style: TextStyle(
                      color: kXviewText,
                      fontSize: 26,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 28),
            const Text('Laptop Tailscale IP',
                style: TextStyle(color: kXviewMuted, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              style: const TextStyle(
                  color: kXviewText, fontSize: 20, fontFamily: 'monospace'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onSubmitted: _connect,
              decoration: InputDecoration(
                hintText: '100.x.y.z',
                hintStyle: const TextStyle(color: kXviewMuted),
                filled: true,
                fillColor: kXviewKey,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                helperText: typed.isEmpty || _looksLikeTailscale(typed)
                    ? null
                    : 'The laptop only accepts Tailscale addresses (100.x.y.z)',
                helperStyle: const TextStyle(color: Color(0xFFF59E0B)),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kXviewTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: typed.isEmpty ? null : () => _connect(typed),
                child: const Text('Connect',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ),
            if (_saved.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text('Saved laptops',
                  style: TextStyle(color: kXviewMuted, fontSize: 13)),
              const SizedBox(height: 6),
              ..._saved.map((ip) => Card(
                    color: kXviewPanel,
                    child: ListTile(
                      leading: const Icon(Icons.laptop, color: kXviewTealLight),
                      title: Text(ip,
                          style: const TextStyle(
                              color: kXviewText, fontFamily: 'monospace')),
                      trailing: IconButton(
                        tooltip: 'Forget',
                        icon: const Icon(Icons.close, color: kXviewMuted),
                        onPressed: () =>
                            _save(_saved.where((e) => e != ip).toList()),
                      ),
                      onTap: () => _connect(ip),
                    ),
                  )),
            ],
            const SizedBox(height: 28),
            const Text(
              'Tailscale must be on, on this phone and the laptop. '
              'The password is asked once; tick "Remember password" to skip it next time.',
              style: TextStyle(color: kXviewMuted, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

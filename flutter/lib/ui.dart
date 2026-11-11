import 'package:flutter/material.dart';

import 'logic.dart';
import 'native.dart';
import 't.dart';

const gap = 4.0;
const green = Color(0xFFA5D6A7);

/// Puts a 4 dp gap between children, like Arrangement.spacedBy(4.dp).
List<Widget> spaced(List<Widget> c, {bool vertical = false}) => [
      for (var i = 0; i < c.length; i++) ...[
        if (i > 0) SizedBox(width: vertical ? 0 : gap, height: vertical ? gap : 0),
        c[i],
      ],
    ];

/// Column whose children are spaced and full width.
Widget vcol(List<Widget> c, {Key? key}) =>
    Column(key: key, crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(c, vertical: true));

/// Row whose children are spaced and full height.
Widget hrow(List<Widget> c, {Key? key}) => Row(key: key, crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(c));

/// Compose weight(w): Expanded with flex = w * 10.
Widget w(double weight, Widget child) => Expanded(flex: (weight * 10).round(), child: child);

/// The back button handler of the screen on top. Returns true when the screen used the press.
class BackSlot {
  bool Function()? handler;
}

/// Plain box button: fills whatever space its parent gives it.
class Plain extends StatelessWidget {
  const Plain(this.text,
      {super.key, this.on = false, this.enabled = true, this.dim = false, this.fill = const Color(0xFFDDDDDD), this.size = 28, required this.onTap});
  final String text;
  final bool on, enabled, dim;
  final Color fill;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = !enabled ? const Color(0xFFEEEEEE) : on ? Colors.black : dim ? const Color(0xFFEEEEEE) : fill;
    final fg = !enabled ? Colors.grey : on ? Colors.white : dim ? Colors.grey : Colors.black;
    return Material(
      color: bg,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1)),
          padding: const EdgeInsets.all(2),
          alignment: Alignment.center,
          child: Text(text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.clip,
              style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

/// Thin strip at the top of a screen, for small buttons and the title.
class Bar extends StatelessWidget {
  const Bar(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SizedBox(height: 48, child: hrow(children));
}

class Small extends StatelessWidget {
  const Small(this.text, {super.key, this.enabled = true, this.on = false, this.width = 110, required this.onTap});
  final String text;
  final bool enabled, on;
  final double width;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, child: Plain(text, on: on, enabled: enabled, size: 18, onTap: onTap));
}

class BigTitle extends StatelessWidget {
  const BigTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black));
}

/// Title inside a Bar: takes the free width, centred vertically.
Widget barTitle(String text) => Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: BigTitle(text)));

/// Fixed grid, never scrolls. Extra items go to the next page.
class PagedGrid<E> extends StatefulWidget {
  const PagedGrid(this.items, this.rows, this.cols, this.cell, {super.key});
  final List<E> items;
  final int rows, cols;
  final Widget Function(E) cell;
  @override
  State<PagedGrid<E>> createState() => _PagedGridState<E>();
}

class _PagedGridState<E> extends State<PagedGrid<E>> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final slots = widget.rows * widget.cols;
    final needMore = items.length > slots;
    final pageSize = needMore ? slots - 1 : slots;
    final pages = (items.length / pageSize).ceil().clamp(1, 1 << 30);
    final start = (page < pages - 1 ? page : pages - 1) * pageSize;
    final shown = items.skip(start).take(pageSize).toList();
    return vcol([
      for (var r = 0; r < widget.rows; r++)
        Expanded(
          child: hrow([
            for (var c = 0; c < widget.cols; c++)
              Expanded(child: () {
                final i = r * widget.cols + c;
                if (i < shown.length) return widget.cell(shown[i]);
                if (needMore && i == slots - 1) {
                  return Plain(T.more, size: 20, onTap: () => setState(() => page = (page + 1) % pages));
                }
                return const SizedBox();
              }()),
          ]),
        ),
    ]);
  }
}

/// Opens the phone's own voice typing in Tunisian Arabic. No internet or no voice app: the phone shows a message.
class MicButton extends StatelessWidget {
  const MicButton(this.native, this.onText, {super.key});
  final Native native;
  final void Function(String) onText;
  @override
  Widget build(BuildContext context) => Small(T.mic, width: 100, onTap: () async {
        final s = await native.speech();
        if (s != null) onText(s);
      });
}

/// Text box that follows [value] when it changes from outside (voice, a tapped name).
class NameField extends StatefulWidget {
  const NameField(this.value, this.onChanged, {super.key, this.label});
  final String value;
  final void Function(String) onChanged;
  final String? label;
  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  late final c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(NameField old) {
    super.didUpdateWidget(old);
    if (widget.value != c.text) {
      c.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        onChanged: widget.onChanged,
        maxLines: 1,
        style: const TextStyle(fontSize: 24),
        decoration: InputDecoration(border: const OutlineInputBorder(), labelText: widget.label),
      );
}

/// One text box, voice, and old names as buttons. Tapping an old name is enough; no typing.
class NamePicker extends StatelessWidget {
  const NamePicker({
    super.key,
    required this.native,
    required this.title,
    required this.value,
    required this.onChange,
    required this.suggestions,
    required this.back,
    required this.action,
    required this.actionEnabled,
    required this.onAction,
    this.onPick,
    this.appendVoice = false,
    this.extra = const [],
  });
  final Native native;
  final String title, value, action;
  final void Function(String) onChange;
  final List<String> suggestions;
  final VoidCallback back, onAction;
  final bool actionEnabled, appendVoice;
  final void Function(String)? onPick;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final q = cleanName(value);
    final shown = suggestions.where((s) => q.isEmpty || s.toLowerCase().contains(q.toLowerCase())).toList();
    final pick = onPick ?? onChange;
    return vcol([
      Bar([
        Small(T.back, onTap: back),
        barTitle(title),
        ...extra,
        MicButton(native, (said) => onChange(appendVoice ? cleanName('$value $said') : cleanName(said))),
        Small(action, enabled: actionEnabled, onTap: onAction),
      ]),
      NameField(value, onChange),
      Expanded(child: PagedGrid<String>(shown, 2, 4, (s) => Plain(s, on: s == q, size: 20, onTap: () => pick(s)))),
    ]);
  }
}

/// On-screen digits, so the phone keyboard never covers the screen.
class NumPad extends StatelessWidget {
  const NumPad(this.value, this.onChange, {super.key});
  final String value;
  final void Function(String) onChange;
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: vcol([
          for (final keys in const ['123', '456', '789', '.0<'])
            Expanded(
              child: hrow([
                for (final k in keys.split(''))
                  Expanded(
                    child: Plain(k == '<' ? '⌫' : k, size: 32, onTap: () {
                      if (k == '<') {
                        if (value.isNotEmpty) onChange(value.substring(0, value.length - 1));
                      } else if (k == '.' && value.contains('.')) {
                      } else {
                        onChange(value + k);
                      }
                    }),
                  ),
              ]),
            ),
        ]),
      );
}

class Readout extends StatelessWidget {
  const Readout(this.label, this.value, this.active, {super.key, required this.onTap});
  final String label, value;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: active ? 3 : 1)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Text('$label: $value',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        ),
      );
}

/// Bold black text line used for totals.
Widget line(String s, {double size = 20, bool bold = true}) => Text(s,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
    style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: Colors.black));

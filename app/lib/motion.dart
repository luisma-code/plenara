import 'package:flutter/material.dart';

/// One vocabulary for meaningful motion. Widgets use these tokens so a state
/// change cannot quietly acquire its own timing language.
abstract final class PlenaraMotion {
  static const acknowledge = Duration(milliseconds: 260);
  static const quick = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 320);
  static const deliberate = Duration(milliseconds: 520);

  static const enter = Curves.easeOutCubic;
  static const leave = Curves.easeInCubic;
  static const move = Curves.easeInOutCubicEmphasized;
}

typedef ContinuityItemBuilder<T> =
    Widget Function(BuildContext context, T item);

/// A small diffing list that keeps a planner object visible while it enters or
/// leaves. The object key is its record id—not its current section—so create,
/// complete, undo, and reschedule read as changes to an existing thing rather
/// than an unrelated page refresh.
class ContinuityColumn<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T item) keyOf;
  final ContinuityItemBuilder<T> itemBuilder;
  final Widget separator;

  const ContinuityColumn({
    super.key,
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.separator = const Divider(height: 1),
  });

  @override
  State<ContinuityColumn<T>> createState() => _ContinuityColumnState<T>();
}

class _ContinuityColumnState<T> extends State<ContinuityColumn<T>> {
  final _listKey = GlobalKey<AnimatedListState>();
  late final List<T> _visible = List<T>.of(widget.items);

  @override
  void didUpdateWidget(covariant ContinuityColumn<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incomingIds = widget.items.map(widget.keyOf).toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var index = _visible.length - 1; index >= 0; index--) {
        final item = _visible[index];
        if (incomingIds.contains(widget.keyOf(item))) continue;
        _visible.removeAt(index);
        _listKey.currentState?.removeItem(
          index,
          (context, animation) => _transition(context, item, animation),
          duration: PlenaraMotion.standard,
        );
      }
      for (var index = 0; index < widget.items.length; index++) {
        final incoming = widget.items[index];
        final id = widget.keyOf(incoming);
        final current = _visible.indexWhere((item) => widget.keyOf(item) == id);
        if (current < 0) {
          _visible.insert(index.clamp(0, _visible.length), incoming);
          _listKey.currentState?.insertItem(
            index,
            duration: PlenaraMotion.standard,
          );
        } else {
          _visible[current] = incoming;
        }
      }
      // Surviving items whose RELATIVE order changed (a reschedule reordered a
      // section) must actually move — updating them in place rendered stale
      // ordering forever. A move is a remove+insert pair on the same timing
      // token, so it reads as motion (and honors reduced-motion through the
      // same _transition path), keeping _visible convergent with widget.items.
      for (var index = 0;
          index < widget.items.length && index < _visible.length;
          index++) {
        final targetId = widget.keyOf(widget.items[index]);
        if (widget.keyOf(_visible[index]) == targetId) continue;
        final from = _visible.indexWhere(
          (item) => widget.keyOf(item) == targetId,
        );
        if (from < 0) continue;
        final moved = _visible.removeAt(from);
        _listKey.currentState?.removeItem(
          from,
          (context, animation) => _transition(context, moved, animation),
          duration: PlenaraMotion.standard,
        );
        _visible.insert(index, moved);
        _listKey.currentState?.insertItem(
          index,
          duration: PlenaraMotion.standard,
        );
      }
      if (mounted) setState(() {});
    });
  }

  Widget _transition(
    BuildContext context,
    T item,
    Animation<double> animation,
  ) {
    final faded = FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: PlenaraMotion.enter),
      child: KeyedSubtree(
        key: ValueKey('continuity-${widget.keyOf(item)}'),
        child: widget.itemBuilder(context, item),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return faded;
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: PlenaraMotion.move),
      alignment: Alignment.topCenter,
      child: faded,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
    key: _listKey,
    initialItemCount: _visible.length,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemBuilder: (context, index, animation) {
      final item = _visible[index];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _transition(context, item, animation),
          if (index != _visible.length - 1) widget.separator,
        ],
      );
    },
  );
}

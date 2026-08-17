import 'package:flutter/material.dart';

import 'plena.dart';

/// Y2 presence: the same entity as home, reduced to a still ember beside
/// reading/detail surfaces. Static by design: it maintains continuity without
/// spending attention or a permanent animation budget.
class PlenaEmber extends StatelessWidget {
  final String mode;
  const PlenaEmber({super.key, required this.mode});

  @override
  Widget build(BuildContext context) => Positioned(
    right: 10,
    top: MediaQuery.paddingOf(context).top + 4,
    child: IgnorePointer(
      child: Semantics(
        label: 'Plena, quiet presence. $mode',
        child: const SizedBox.square(
          key: Key('plena-detail-ember'),
          dimension: 58,
          child: PresenceView(
            state: PresenceState.idle,
            animate: false,
            yieldAnchor: Alignment.center,
          ),
        ),
      ),
    ),
  );
}

class PlenaEmberInline extends StatelessWidget {
  final String mode;
  const PlenaEmberInline({super.key, required this.mode});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      label: 'Plena, quiet presence. $mode',
      child: const SizedBox.square(
        key: Key('plena-inline-ember'),
        dimension: 48,
        child: PresenceView(state: PresenceState.idle, animate: false),
      ),
    ),
  );
}

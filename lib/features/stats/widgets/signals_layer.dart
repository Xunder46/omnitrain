// The Signals layer (Stats PR 6a, Phase 2) — the screen half of the framework.
//
// The layer renders the model: which cards exist, which kinds they are and what
// they say is decided by `resolveSignals` and the registered signals, never
// here. The only arithmetic in this file is presentation — the gap between two
// cards and the size of the dismiss target — and every string it draws is
// either a card's own copy, the header, or the quiet line (D-1001, D-1007).
//
// The layer is presentation-only: no repository, no service, no clock and no
// state. A card is read, and only its dismiss control is interactive (D-1018).

import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/signals.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';

/// Geometry. Local to the layer: no other surface draws a signal card, so these
/// are not theme tokens (D-1002).
const double _kDismissTarget = 48;
const double _kKindIconSize = 18;
const double _kCardGap = 12;

/// The tooltip and semantic label the dismiss control carries (D-1018).
const String _kDismissLabel = 'Dismiss signal';

/// The window's signals: a header, up to [kSignalMaxCards] cards, or the quiet
/// line when nothing qualifies.
class SignalsLayerSection extends StatelessWidget {
  final SignalsData data;
  final OmniThemeColors themeColors;
  final void Function(String id) onDismiss;

  const SignalsLayerSection({
    super.key,
    required this.data,
    required this.themeColors,
    required this.onDismiss,
  });

  /// The kind's icon. Kind is carried by the label and the icon, never by a
  /// colour (D-1002).
  static IconData _iconFor(SignalKind kind) => switch (kind) {
    SignalKind.positive => Icons.trending_up,
    SignalKind.caution => Icons.visibility_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cards = data.cards;

    return Column(
      key: const Key('signals_layer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OmniCardHeader(title: 'SIGNALS'),
        if (cards.isEmpty) ...[
          if (data.showQuietLine) _quietLine(context),
        ] else ...[
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: _kCardGap),
            _card(context, cards[i]),
          ],
        ],
      ],
    );
  }

  /// "Nothing to say" is a state the user can see, not an absence (D-1007).
  Widget _quietLine(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      kSignalQuietLine,
      key: const Key('signals_quiet_line'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: themeColors.textSecondary,
      ),
    );
  }

  Widget _card(BuildContext context, SignalCard card) {
    final theme = Theme.of(context);

    return OmniSurface(
      key: Key('signal_card_${card.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _iconFor(card.kind),
                      size: _kKindIconSize,
                      color: themeColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        signalKindLabel(card.kind),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: themeColors.textSecondary,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  card.observation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: themeColors.textDominant,
                  ),
                ),
                if (card.suggestion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    card.suggestion!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: _kDismissLabel,
            button: true,
            child: SizedBox(
              width: _kDismissTarget,
              height: _kDismissTarget,
              child: IconButton(
                key: Key('signal_dismiss_${card.id}'),
                icon: const Icon(Icons.close),
                iconSize: 20,
                padding: EdgeInsets.zero,
                color: themeColors.textSecondary,
                tooltip: _kDismissLabel,
                onPressed: () => onDismiss(card.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

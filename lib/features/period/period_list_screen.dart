import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/modality_color_utils.dart';
import '../../state/period/period_state.dart';
import '../../data/models/models.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import 'create_period_screen.dart';

class PeriodListScreen extends StatefulWidget {
  final PeriodState periodState;

  const PeriodListScreen({super.key, required this.periodState});

  @override
  State<PeriodListScreen> createState() => _PeriodListScreenState();
}

class _PeriodListScreenState extends State<PeriodListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.periodState.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Training Periods'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: OmniGradientBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.periodState,
            builder: (context, _) {
              if (widget.periodState.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final periods = widget.periodState.periods;
              if (periods.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'No training periods yet.',
                        style: TextStyle(
                          color: OmniTheme.textSecondary.withOpacity(0.6),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: periods.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _PeriodRow(
                  period: periods[index],
                  onEdit: () => _openEdit(context, periods[index]),
                  onDelete: () => _confirmDelete(context, periods[index]),
                ),
              );
            },
          ),
        ),
      ),
      bottomSheet: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity,
            height: OmniTheme.buttonPrimaryHeight,
            child: FilledButton(
              onPressed: () => _openCreate(context),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonBorderRadius,
                    ),
                  ),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 8),
                  Text('Create Period'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePeriodScreen(periodState: widget.periodState),
      ),
    );
    if (created == true) {
      // PeriodState.createPeriod already calls load() internally.
    }
  }

  Future<void> _openEdit(BuildContext context, TrainingPeriod period) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePeriodScreen(
          periodState: widget.periodState,
          existingPeriod: period,
        ),
      ),
    );
    if (edited == true) {
      // PeriodState.updatePeriod already calls load() internally.
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TrainingPeriod period,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Period'),
        content: Text('Delete "${period.name}"?'),
        actions: [
          TextButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
                ),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
                ),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.periodState.deletePeriod(period.id);
    }
  }
}

class _PeriodRow extends StatelessWidget {
  final TrainingPeriod period;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PeriodRow({
    required this.period,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateRange = OmniDateUtils.formatRange(
      period.startDateMs,
      period.endDateMs,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final isActive =
        period.startDateMs <= now && period.endDateMs >= now;

    return Container(
      decoration: BoxDecoration(
        color: OmniTheme.surfaceColor.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
              : OmniTheme.surfaceBorderColor,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Row(
          children: [
            Expanded(
              child: Text(
                period.name,
                style: const TextStyle(
                  color: OmniTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              dateRange,
              style: TextStyle(
                fontSize: 12,
                color: OmniTheme.textSecondary.withOpacity(0.75),
              ),
            ),
            if (period.focusModalities.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: period.focusModalities.map((m) {
                  final c = ModalityColorUtils.colorForModality(m);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ModalityColorUtils.labelForModality(m),
                      style: TextStyle(
                        fontSize: 10,
                        color: c,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: OmniTheme.textSecondary,
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Colors.redAccent,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// Экран Paywall — Design System v2.
//
// Value headline + column headers + CTA-иерархия (primary filled / secondary outline).
// "Debug Screen" переименован в "Signal Analyzer".
// Roadmap card заменила дублирующую строку виджета.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../ui/design_tokens.dart';
import 'pro_status_service.dart';
import 'purchases_gateway.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key, required this.feature});

  /// Название фичи, которая привела пользователя на paywall.
  final String feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'Upgrade to Pro',
          style: AppTextStyles.mono(16, FontWeight.w500, AppColors.textPrimary),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Value headline ────────────────────────────────────────────────
              Text(
                'Читай любой трек.\nБез ограничений.',
                textAlign: TextAlign.center,
                style: AppTextStyles.mono(
                  15, FontWeight.w500, const Color(0xFFC0DCD6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Разблокируй полный потенциал детектора',
                textAlign: TextAlign.center,
                style: AppTextStyles.mono(
                  8.5, FontWeight.w400, AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),

              // ── Comparison table ──────────────────────────────────────────────
              _ComparisonTable(),
              const SizedBox(height: 28),

              // ── CTA — Primary (Lifetime) ──────────────────────────────────────
              _PrimaryCtaButton(
                label: 'Lifetime — \$4.99',
                badgeLabel: 'Best value',
                onTap: () => _purchaseLifetime(context),
              ),
              const SizedBox(height: 12),

              // ── CTA — Secondary (Annual) ──────────────────────────────────────
              _SecondaryCtaButton(
                label: 'Annual — \$3.99/yr',
                onTap: () => _purchaseAnnual(context),
              ),
              const SizedBox(height: 8),

              // ── Restore ───────────────────────────────────────────────────────
              TextButton(
                onPressed: () => _restore(context),
                child: Text(
                  'Restore purchases',
                  style: AppTextStyles.mono(
                    11, FontWeight.w400, AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Roadmap card ──────────────────────────────────────────────────
              const _RoadmapCard(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _purchaseLifetime(BuildContext context) async {
    final result = await ProStatusService.instance.purchaseLifetime();
    if (!context.mounted) return;
    _handlePurchaseResult(context, result);
  }

  Future<void> _purchaseAnnual(BuildContext context) async {
    final result = await ProStatusService.instance.purchaseAnnual();
    if (!context.mounted) return;
    _handlePurchaseResult(context, result);
  }

  Future<void> _restore(BuildContext context) async {
    final result = await ProStatusService.instance.restore();
    if (!context.mounted) return;
    _handlePurchaseResult(context, result);
  }

  void _handlePurchaseResult(BuildContext context, PurchaseResult result) {
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case PurchaseResult.success:
        messenger.showSnackBar(SnackBar(
          content: Text('Success! Welcome to Pro.',
              style: AppTheme.mono(fontSize: 13)),
          backgroundColor: AppTheme.success,
        ));
        Navigator.of(context).pop();
        break;
      case PurchaseResult.cancelled:
        messenger.showSnackBar(SnackBar(
          content: Text('Purchase cancelled.',
              style: AppTheme.mono(fontSize: 13)),
          backgroundColor: AppTheme.textSecondary,
        ));
        break;
      case PurchaseResult.error:
        messenger.showSnackBar(SnackBar(
          content: Text('Purchase failed. Try again.',
              style: AppTheme.mono(fontSize: 13)),
          backgroundColor: AppTheme.danger,
        ));
        break;
    }
  }
}

// ── Comparison table ──────────────────────────────────────────────────────────

class _ComparisonTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          // Column headers
          Row(
            children: [
              Expanded(
                child: Text(
                  'ФУНКЦИЯ',
                  style: AppTextStyles.mono(
                    7.5, FontWeight.w400, AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  'FREE',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.mono(
                    7.5, FontWeight.w400, AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'PRO',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.mono(
                    7.5, FontWeight.w400, AppColors.accent,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.borderFaint, height: 16),
          const _TableRow('BPM Range', '170–230', '155–230'),
          const Divider(color: AppColors.borderFaint, height: 16),
          const _TableRow('Signal Analyzer', '—', '✓'),
          const Divider(color: AppColors.borderFaint, height: 16),
          const _TableRow('История', '30 сек', '24 ч'),
          const Divider(color: AppColors.borderFaint, height: 16),
          const _TableRow('Export CSV/JSON', '—', '✓'),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow(this.feature, this.free, this.pro);
  final String feature;
  final String free;
  final String pro;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            feature,
            style: AppTextStyles.mono(
              11, FontWeight.w400, AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            free,
            textAlign: TextAlign.center,
            style: AppTextStyles.mono(
              11, FontWeight.w400, AppColors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            pro,
            textAlign: TextAlign.right,
            style: AppTextStyles.mono(
              11, FontWeight.w400, AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Primary CTA — filled + "Best value" badge ─────────────────────────────────

class _PrimaryCtaButton extends StatelessWidget {
  const _PrimaryCtaButton({
    required this.label,
    required this.badgeLabel,
    required this.onTap,
  });

  final String label;
  final String badgeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.ctaButton,
            ),
          ),
        ),
        Positioned(
          top: -10,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE0822A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeLabel,
                style: AppTextStyles.mono(
                  7.5, FontWeight.w600, Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Secondary CTA — outline ───────────────────────────────────────────────────

class _SecondaryCtaButton extends StatelessWidget {
  const _SecondaryCtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.bpmEmpty),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.mono(
            10, FontWeight.w400, AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Roadmap card ──────────────────────────────────────────────────────────────

class _RoadmapCard extends StatelessWidget {
  const _RoadmapCard();

  static const _items = [
    'Key + Camelot Wheel',
    'Energy Level 1–10',
    'Lock-screen Widget · iOS 16+',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1009),
        border: Border.all(color: const Color(0xFF1A2E25)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COMING TO PRO', style: AppTextStyles.sectionLabel),
          const SizedBox(height: 8),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.bpmEmpty,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    item,
                    style: AppTextStyles.mono(
                      8.5, FontWeight.w400, AppColors.bpmEmpty,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

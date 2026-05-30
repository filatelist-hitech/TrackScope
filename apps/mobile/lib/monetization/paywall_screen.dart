// Экран Paywall — Free vs Pro сравнение и покупка.
//
// Показывает таблицу сравнения Free/Pro, кнопки покупки (Lifetime $4.99,
// Annual $3.99/yr), кнопку Restore, и плитку lock-screen-виджета "Скоро".
// Стилизован через AppTheme (accent #00E5CC, bg #07070F, mono).

import 'package:flutter/material.dart';

import '../ui/design_tokens.dart';
import 'pro_status_service.dart';
import 'purchases_gateway.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key, required this.feature});

  /// Название фичи, которая привела пользователя на paywall
  /// (для контекста: "debug_screen", "history", "export").
  final String feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Upgrade to Pro', style: AppTheme.mono(fontSize: 16)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Comparison table
              _buildComparisonTable(),
              const SizedBox(height: 32),

              // Purchase buttons
              _buildPurchaseButton(
                context,
                label: 'Lifetime — \$4.99',
                onTap: () => _purchaseLifetime(context),
              ),
              const SizedBox(height: 12),
              _buildPurchaseButton(
                context,
                label: 'Annual — \$3.99/yr',
                onTap: () => _purchaseAnnual(context),
              ),
              const SizedBox(height: 24),

              // Restore button
              TextButton(
                onPressed: () => _restore(context),
                child: Text(
                  'Restore purchases',
                  style: AppTheme.mono(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 32),

              // Lock-screen widget "Скоро" tile
              _buildWidgetTile(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildComparisonRow('BPM Range', '170–230', '155–230'),
          const Divider(color: AppTheme.surfaceHigh, height: 24),
          _buildComparisonRow('Debug Screen', '—', '✓'),
          const Divider(color: AppTheme.surfaceHigh, height: 24),
          _buildComparisonRow('History', '30 sec', 'Unlimited'),
          const Divider(color: AppTheme.surfaceHigh, height: 24),
          _buildComparisonRow('Export CSV/JSON', '—', '✓'),
          const Divider(color: AppTheme.surfaceHigh, height: 24),
          _buildComparisonRow('Lock-screen Widget', '—', 'Скоро'),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String feature, String free, String pro) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            feature,
            style: AppTheme.mono(fontSize: 13, color: AppTheme.textPrimary),
          ),
        ),
        Expanded(
          child: Text(
            free,
            textAlign: TextAlign.center,
            style: AppTheme.mono(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            pro,
            textAlign: TextAlign.center,
            style: AppTheme.mono(fontSize: 13, color: AppTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _buildPurchaseButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.accent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTheme.mono(
              fontSize: 15,
              color: AppTheme.background,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWidgetTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.widgets_outlined, color: AppTheme.textSecondary, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lock-screen Widget',
                  style: AppTheme.mono(fontSize: 14, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Скоро · iOS 16+ и Android',
                  style: AppTheme.mono(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
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
        messenger.showSnackBar(
          SnackBar(
            content: Text('Success! Welcome to Pro.', style: AppTheme.mono(fontSize: 13)),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop();
        break;
      case PurchaseResult.cancelled:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Purchase cancelled.', style: AppTheme.mono(fontSize: 13)),
            backgroundColor: AppTheme.textSecondary,
          ),
        );
        break;
      case PurchaseResult.error:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Purchase failed. Try again.', style: AppTheme.mono(fontSize: 13)),
            backgroundColor: AppTheme.danger,
          ),
        );
        break;
    }
  }
}

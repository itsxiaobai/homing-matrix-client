// 第一百零五批（人類提供 Element X 截圖作版面參考）：歡迎頁。
//
// AGENTS.md：最終介面由人類定稿；此處只照「welcome → 兩個大按鈕 → 建立帳號
// → 版本號」的元件階層做骨架，**不抄襲 Element 的品牌標誌、綠色或文案**。
// 使用 Homing 自己的 #FFBD9F 種子色與自繪 'H' 標誌。
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onManualLogin,
    required this.onQrLogin,
    required this.onCreateAccount,
    this.version,
  });

  final VoidCallback onManualLogin;
  final VoidCallback onQrLogin;
  final VoidCallback onCreateAccount;
  final String? version;

  static const _seed = Color(0xFFFFBD9F);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16323B), Color(0xFF0B1216)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                const Spacer(),
                // 自繪 Homing 標誌（非 Element 品牌）。
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_seed, Color(0xFFE39B76)],
                    ),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      'H',
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Homing',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.t('與人直接對話，不被注意力商業化打擾。'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onQrLogin,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(S.t('使用 QR 碼登入')),
                    style: _pillStyle(theme),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onManualLogin,
                    icon: const Icon(Icons.login),
                    label: Text(S.t('手動登入')),
                    style: _pillStyle(theme),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onCreateAccount,
                  child: Text(
                    S.t('建立帳號'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                if (version != null)
                  Text(
                    '${S.t('版本')} $version',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _pillStyle(ThemeData theme) => ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: theme.textTheme.labelLarge,
      );
}

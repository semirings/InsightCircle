import 'package:flutter/material.dart';

import '../theme.dart';
import 'looker_embed_stub.dart'
    if (dart.library.js_interop) 'looker_embed_web.dart';

export 'looker_embed_stub.dart'
    if (dart.library.js_interop) 'looker_embed_web.dart';

/// Scaffold wrapper that provides the Consortium header + pale-yellow sidebar
/// around a [LookerEmbed]. Drop-in for full-page report display.
class LookerReportDisplay extends StatelessWidget {
  final String reportUrl;
  final String reportTitle;
  final Widget sidebar;

  const LookerReportDisplay({
    super.key,
    required this.reportUrl,
    required this.reportTitle,
    required this.sidebar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                const Text(
                  'InsightCircle',
                  style: TextStyle(
                    color: kRed700,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  reportTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // 3px red stripe
          const SizedBox(height: 3, child: ColoredBox(color: kRed700)),
          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar
                SizedBox(
                  width: 300,
                  child: ColoredBox(
                    color: kSidebarBg,
                    child: sidebar,
                  ),
                ),
                // Report iframe
                Expanded(
                  child: ColoredBox(
                    color: Colors.white,
                    child: LookerEmbed(reportUrl: reportUrl),
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

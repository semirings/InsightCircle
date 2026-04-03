import 'package:flutter/material.dart';
import '../widgets/looker_embed.dart';

// ── Palette (from landing.pen) ─────────────────────────────────────────────
// These mirror theme.dart values but are kept explicit to the design file.
const _kHeaderBg    = Color(0xFF000000);
const _kRedStripe   = Color(0xFFFF0000);
const _kSidebarBg   = Color(0xFFF9F6CB); // #f9f6cb — slightly warmer than kPaleYellow
const _kCardBg      = Color(0xFFCCCCCC);
const _kBodyBg      = Color(0xFFFFFFFF);
const _kStatusBg    = Color(0xFF000000);
const _kHeaderText  = Color(0xFFFFFFFF);
const _kStatusText  = Color(0xFFFFFFFF);

// ── Proportions (from landing.pen 800×600 frame) ──────────────────────────
const _kHeaderH     = 66.0;
const _kStripeH     = 11.0;
const _kSidebarW    = 124.0;
const _kDividerW    = 1.0;
const _kStatusH     = 31.0;
const _kCardW       = 104.0;
const _kCardH       = 61.0;
const _kCardX       = 7.0;

// Three sidebar cards at y=86, 157, 227 within the 800×600 frame.
// Relative to sidebar top (sidebar starts at y=77): 9, 80, 150.
const _kCardOffsets = [9.0, 80.0, 150.0];

/// Landing page generated from landing.pen (Pencil v2.10).
///
/// [reportUrls] maps each sidebar card index to a Looker Studio embed URL.
/// Tapping a card loads its URL in a [LookerEmbed] in the main content frame.
/// Pass fewer URLs than cards to leave some cards inert.
///
/// [body] is shown instead of a [LookerEmbed] when no card is selected or
/// when the tapped card has no corresponding URL.
class LandingPage extends StatefulWidget {
  final List<String> reportUrls;
  final void Function(int index)? onCardTap;
  final Widget body;

  const LandingPage({
    super.key,
    this.reportUrls = const [],
    this.onCardTap,
    this.body = const SizedBox.shrink(),
  });

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  int? _hoveredCard;
  int? _selectedCard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBodyBg,
      body: Column(
        children: [
          _header(),
          // Red stripe (11px)
          const SizedBox(height: _kStripeH, child: ColoredBox(color: _kRedStripe)),
          // Main row
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sidebar(),
                // 1px red vertical divider
                const SizedBox(width: _kDividerW, child: ColoredBox(color: _kRedStripe)),
                _mainContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header() {
    return Container(
      height: _kHeaderH,
      color: _kHeaderBg,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: _kCardX),
      child: const Text(
        'Report',
        style: TextStyle(
          color: _kHeaderText,
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _sidebar() {
    return SizedBox(
      width: _kSidebarW,
      child: ColoredBox(
        color: _kSidebarBg,
        child: Stack(
          children: [
            for (int i = 0; i < _kCardOffsets.length; i++)
              Positioned(
                left: _kCardX,
                top: _kCardOffsets[i],
                child: _sidebarCard(i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarCard(int index) {
    final hovered = _hoveredCard == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredCard = index),
      onExit:  (_) => setState(() => _hoveredCard = null),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedCard = index);
          widget.onCardTap?.call(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: _kCardW,
          height: _kCardH,
          decoration: BoxDecoration(
            color: _kCardBg,
            border: Border(
              left: BorderSide(
                color: hovered ? _kRedStripe : Colors.transparent,
                width: 3,
              ),
            ),
            boxShadow: hovered
                ? [const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                : [],
          ),
        ),
      ),
    );
  }

  Widget _resolveBody() {
    final idx = _selectedCard;
    if (idx != null && idx < widget.reportUrls.length) {
      return LookerEmbed(reportUrl: widget.reportUrls[idx]);
    }
    return widget.body;
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _mainContent() {
    return Expanded(
      child: Column(
        children: [
          // White content frame with outer shadow (from landing.pen effect)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: _kBodyBg,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x40000000), // #00000040
                    offset: const Offset(0, 4),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: _resolveBody(),
            ),
          ),
          // Status bar
          _statusBar(),
        ],
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      height: _kStatusH,
      color: _kStatusBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text(
            'Status',
            style: TextStyle(
              color: _kStatusText,
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(width: 16),
          // Grey progress strip (200→774px in 800px frame = ~71.75% of body width)
          Expanded(
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

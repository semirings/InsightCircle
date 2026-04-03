import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/ingest_action_card.dart';
import '../widgets/looker_embed.dart';

// ── Constants ──────────────────────────────────────────────────────────────

const _kNavH      = 96.0;
const _kSidebarW  = 300.0;
const _kTabLabels = ['Active Report', 'Node History', 'Collaborators', 'Export Logs'];

// ── Page ───────────────────────────────────────────────────────────────────

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _activeNavIndex = 0;
  int _activeTab      = 0;

  // TBD: swap in real Looker URLs per tab
  final List<String?> _reportUrls = [null, null, null, null];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Column(
        children: [
          _TopNavBar(activeIndex: _activeNavIndex, onNavTap: (i) => setState(() => _activeNavIndex = i)),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SideNavBar(),
                Expanded(
                  child: Column(
                    children: [
                      _ContentTabBar(
                        activeIndex: _activeTab,
                        onTap: (i) => setState(() => _activeTab = i),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ReportContainer(reportUrl: _reportUrls[_activeTab]),
                                const SizedBox(height: 48),
                                const _SystemManifest(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

// ── Top Nav ────────────────────────────────────────────────────────────────

class _TopNavBar extends StatelessWidget {
  final int activeIndex;
  final void Function(int) onNavTap;
  const _TopNavBar({required this.activeIndex, required this.onNavTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kNavH,
      decoration: const BoxDecoration(
        color: kBlack,
        border: Border(bottom: BorderSide(color: kRed700, width: 6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: logo + nav links
          Row(
            children: [
              Text(
                'Insight Circle',
                style: spaceGrotesk(fontSize: 24, color: Colors.white, letterSpacing: -1.2),
              ),
              const SizedBox(width: 48),
              _NavLink('Repository', active: activeIndex == 0, onTap: () => onNavTap(0)),
              const SizedBox(width: 32),
              _NavLink('Archive',    active: activeIndex == 1, onTap: () => onNavTap(1)),
              const SizedBox(width: 32),
              _NavLink('Nodes',      active: activeIndex == 2, onTap: () => onNavTap(2)),
            ],
          ),
          // Right: search + icons
          Row(
            children: [
              Container(
                color: Colors.white.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 192,
                      child: TextField(
                        style: inter(fontSize: 12, color: Colors.white, letterSpacing: 0.5),
                        decoration: InputDecoration(
                          hintText: 'QUERY_SYSTEM...',
                          hintStyle: inter(fontSize: 12, color: kGray500),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const Icon(Icons.search, color: kGray400, size: 18),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              const _HoverIcon(Icons.notifications_outlined),
              const SizedBox(width: 16),
              const _HoverIcon(Icons.settings_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavLink(this.label, {this.active = false, required this.onTap});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? Colors.white
        : (_hovered ? kRed700 : kGray400);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.label.toUpperCase(),
              style: spaceGrotesk(fontSize: 14, color: color, letterSpacing: -0.5),
            ),
            if (widget.active)
              Container(height: 1, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _HoverIcon extends StatefulWidget {
  final IconData icon;
  const _HoverIcon(this.icon);

  @override
  State<_HoverIcon> createState() => _HoverIconState();
}

class _HoverIconState extends State<_HoverIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Icon(widget.icon, color: _hovered ? kRed700 : Colors.white, size: 22),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────

class _SideNavBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kSidebarW,
      decoration: const BoxDecoration(
        color: kSidebarBg,
        border: Border(right: BorderSide(color: kRed700)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          IngestActionCard(),
        ],
      ),
    );
  }
}

// ── Content Tab Bar ────────────────────────────────────────────────────────

class _ContentTabBar extends StatelessWidget {
  final int activeIndex;
  final void Function(int) onTap;
  const _ContentTabBar({required this.activeIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kGray200)),
      ),
      padding: const EdgeInsets.fromLTRB(64, 32, 64, 0),
      child: Row(
        children: [
          for (int i = 0; i < _kTabLabels.length; i++) ...[
            _TabItem(
              label: _kTabLabels[i],
              active: activeIndex == i,
              onTap: () => onTap(i),
            ),
            if (i < _kTabLabels.length - 1) const SizedBox(width: 48),
          ],
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabItem({required this.label, required this.active, required this.onTap});

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.active
        ? kBlack
        : (_hovered ? kGray300 : Colors.transparent);
    final textColor = widget.active ? kBlack : kGray400;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor, width: 4)),
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: inter(
              fontSize: 12,
              fontWeight: widget.active ? FontWeight.w900 : FontWeight.w700,
              color: textColor,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Report Container ───────────────────────────────────────────────────────

class _ReportContainer extends StatelessWidget {
  final String? reportUrl;
  const _ReportContainer({this.reportUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 800),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBlack.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          const _ReportToolbar(),
          reportUrl != null
              ? SizedBox(height: 800, child: LookerEmbed(reportUrl: reportUrl!))
              : const _VisualizationSection(),
        ],
      ),
    );
  }
}

// ── Report Toolbar ─────────────────────────────────────────────────────────

class _ReportToolbar extends StatelessWidget {
  const _ReportToolbar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: kSurfaceContainerLow,
        border: Border(bottom: BorderSide(color: Color(0x0D000000))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kSurface,
                  border: Border.all(color: kBlack.withValues(alpha: 0.05)),
                ),
                child: Text('VIEW_MODE: EDIT',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kGray600,
                    )),
              ),
              const SizedBox(width: 24),
              Text('LAST_SYNC: 04:22:19 UTC',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kGray600,
                  )),
            ],
          ),
          Row(
            children: const [
              _ToolbarIcon(Icons.refresh),
              SizedBox(width: 16),
              _ToolbarIcon(Icons.filter_list),
              SizedBox(width: 16),
              _ToolbarIcon(Icons.download),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolbarIcon extends StatefulWidget {
  final IconData icon;
  const _ToolbarIcon(this.icon);

  @override
  State<_ToolbarIcon> createState() => _ToolbarIconState();
}

class _ToolbarIconState extends State<_ToolbarIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Icon(widget.icon, color: _hovered ? kBlack : kGray400, size: 20),
    );
  }
}

// ── Visualization Section ──────────────────────────────────────────────────

class _VisualizationSection extends StatelessWidget {
  const _VisualizationSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(80),
      child: Column(
        children: [
          // Main viz placeholder
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                // Dotted grid background
                Positioned.fill(
                  child: CustomPaint(painter: _DottedGridPainter()),
                ),
                // Dashed border
                Positioned.fill(
                  child: CustomPaint(painter: _DashedBorderPainter()),
                ),
                // Center content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.analytics_outlined, size: 60, color: kGray300),
                      const SizedBox(height: 16),
                      Text(
                        'External Data Stream Required',
                        style: spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 400,
                        child: Text(
                          'This section is configured to ingest Looker Studio visualizations. '
                          'Connect your consortium API key to render real-time mathematical nodes.',
                          textAlign: TextAlign.center,
                          style: inter(fontSize: 14, color: kGray500),
                        ),
                      ),
                      const SizedBox(height: 32),
                      _AuthorizeButton(),
                    ],
                  ),
                ),
                // Corner labels
                Positioned(
                  top: 16, left: 16,
                  child: Text('COORD: 40.7128° N, 74.0060° W',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: kGray400)),
                ),
                Positioned(
                  bottom: 16, right: 16,
                  child: Text('SIGNAL: STABLE',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: kGray400)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Bento grid
          const _BentoGrid(),
        ],
      ),
    );
  }
}

class _AuthorizeButton extends StatefulWidget {
  @override
  State<_AuthorizeButton> createState() => _AuthorizeButtonState();
}

class _AuthorizeButtonState extends State<_AuthorizeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {}, // TBD: trigger auth flow
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
          color: _hovered ? kGray600 : kBlack,
          child: Text(
            'Authorize Repository',
            style: inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bento Grid ─────────────────────────────────────────────────────────────

class _BentoGrid extends StatelessWidget {
  const _BentoGrid();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Mean Latency',
            value: '12.4ms',
            accentColor: kRed700,
            bottom: _ProgressBar(fill: 0.75, color: kRed700),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _StatCard(
            label: 'Node Redundancy',
            value: '0.9992',
            accentColor: kBlack,
            bottom: const _SegmentedBar(),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _StatCard(
            label: 'Consortium Votes',
            value: '21/24',
            accentColor: kRed700,
            bottom: Text(
              'Quorum Reached',
              style: inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kRed700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final Widget bottom;

  const _StatCard({
    required this.label,
    required this.value,
    required this.accentColor,
    required this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: inter(fontSize: 10, fontWeight: FontWeight.w700, color: kGray400, letterSpacing: 1.5),
          ),
          const SizedBox(height: 4),
          Text(value, style: spaceGrotesk(fontSize: 36, color: kBlack)),
          const SizedBox(height: 16),
          bottom,
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double fill;
  final Color color;
  const _ProgressBar({required this.fill, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        height: 4,
        color: kGray100,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fill,
            child: Container(color: color, height: 4),
          ),
        ),
      );
    });
  }
}

class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < 4; i++) ...[
          Expanded(child: Container(height: 4, color: i < 3 ? kBlack : kGray200)),
          if (i < 3) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

// ── System Manifest ────────────────────────────────────────────────────────

class _SystemManifest extends StatelessWidget {
  const _SystemManifest();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Manifest',
                style: spaceGrotesk(fontSize: 12, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'InsightCircle operates on the v4.2 Academic Brutalism protocol. '
                'All data displayed is cryptographically verified by the central consortium '
                'repository. Unauthorized access to mathematical nodes is prohibited under '
                'Article 09-B.',
                style: inter(fontSize: 11, color: kGray500, height: 1.6),
              ),
            ],
          ),
        ),
        Text(
          'Instance: US-EAST-01 // PID: 9283-X',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: kGray400,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────────────

class _DottedGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    const spacing = 10.0;
    const radius  = 0.5;
    for (double x = 0; x <= size.width; x += spacing) {
      for (double y = 0; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kGray300
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    _dash(canvas, paint, Offset.zero,               Offset(size.width, 0));
    _dash(canvas, paint, Offset(size.width, 0),     Offset(size.width, size.height));
    _dash(canvas, paint, Offset(size.width, size.height), Offset(0, size.height));
    _dash(canvas, paint, Offset(0, size.height),    Offset.zero);
  }

  void _dash(Canvas canvas, Paint paint, Offset a, Offset b) {
    const dashLen = 4.0;
    const gapLen  = 4.0;
    final dx  = b.dx - a.dx;
    final dy  = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux  = dx / len;
    final uy  = dy / len;
    double pos = 0;
    bool drawing = true;
    while (pos < len) {
      final seg = math.min(pos + (drawing ? dashLen : gapLen), len);
      if (drawing) {
        canvas.drawLine(
          Offset(a.dx + ux * pos, a.dy + uy * pos),
          Offset(a.dx + ux * seg, a.dy + uy * seg),
          paint,
        );
      }
      pos = seg;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

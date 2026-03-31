import 'package:flutter/material.dart';
import 'theme.dart';

void main() {
  runApp(const InsightVisualApp());
}

// ── App root ───────────────────────────────────────────────────────────────

class InsightVisualApp extends StatelessWidget {
  const InsightVisualApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InsightCircle Consortium Dashboard',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Dashboard(),
    );
  }
}

// ── State types ────────────────────────────────────────────────────────────

enum DashboardMode { idle, action, insight }

const _kSidebarWidth = 270.0;

const _kActionCards = [
  {'label': 'Analyze Video',    'icon': Icons.play_circle_outline},
  {'label': 'Refresh D4M',      'icon': Icons.refresh},
  {'label': 'Update Registry',  'icon': Icons.cloud_upload_outlined},
];

const _kReportTabs = ['Engagement', 'Reach', 'Trends'];

// ── Dashboard ──────────────────────────────────────────────────────────────

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with SingleTickerProviderStateMixin {
  DashboardMode _mode = DashboardMode.idle;
  List<Map<String, dynamic>> _actionResponses = [];
  String? _activeAction;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kReportTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onActionTap(String label) {
    setState(() {
      _mode = DashboardMode.action;
      _activeAction = label;
      // TBD: replace with real endpoint call; stub response for now.
      _actionResponses = [
        {'status': 'processing', 'action': label, 'video_id': 'vid_placeholder'},
      ];
    });
  }

  void _onInsightTap() => setState(() => _mode = DashboardMode.insight);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _Header(),
          // 3px red stripe
          const SizedBox(height: 3, child: ColoredBox(color: kRed)),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  activeAction: _activeAction,
                  onActionTap: _onActionTap,
                  onInsightTap: _onInsightTap,
                ),
                Expanded(
                  child: _Body(
                    mode: _mode,
                    actionResponses: _actionResponses,
                    activeAction: _activeAction ?? '',
                    tabController: _tabController,
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

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: const Row(
        children: [
          Text(
            'InsightCircle',
            style: TextStyle(
              color: kRed,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Consortium Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final String? activeAction;
  final void Function(String) onActionTap;
  final VoidCallback onInsightTap;

  const _Sidebar({
    required this.activeAction,
    required this.onActionTap,
    required this.onInsightTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kSidebarWidth,
      color: kPaleYellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SidebarLabel('ACTIONS'),
          ..._kActionCards.map((a) => _ActionCard(
                label: a['label'] as String,
                icon: a['icon'] as IconData,
                isActive: activeAction == a['label'],
                onTap: () => onActionTap(a['label'] as String),
              )),
          const Divider(thickness: 1, height: 32, indent: 16, endIndent: 16),
          const _SidebarLabel('INSIGHTS'),
          _ActionCard(
            label: 'Looker Reports',
            icon: Icons.bar_chart_outlined,
            isActive: false,
            onTap: onInsightTap,
          ),
        ],
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  final String text;
  const _SidebarLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black45,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

// ── Action Card ────────────────────────────────────────────────────────────

class _ActionCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ActionCard({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = _hovered || widget.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(
                  color: highlight ? kRed : Colors.transparent,
                  width: 4,
                ),
              ),
              boxShadow: highlight
                  ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
                  : [],
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: highlight ? kRed : Colors.black38),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final DashboardMode mode;
  final List<Map<String, dynamic>> actionResponses;
  final String activeAction;
  final TabController tabController;

  const _Body({
    required this.mode,
    required this.actionResponses,
    required this.activeAction,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPaleYellow, Colors.white],
          stops: [0.0, 0.55],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: switch (mode) {
        DashboardMode.idle    => const _IdleBody(),
        DashboardMode.action  => _ActionBody(
            responses: actionResponses,
            actionLabel: activeAction,
          ),
        DashboardMode.insight => _InsightBody(tabController: tabController),
      },
    );
  }
}

// ── Body: Idle ─────────────────────────────────────────────────────────────

class _IdleBody extends StatelessWidget {
  const _IdleBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Select an Action or Report to Begin.',
        style: TextStyle(
          color: Colors.black38,
          fontSize: 18,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ── Body: Action ───────────────────────────────────────────────────────────

class _ActionBody extends StatelessWidget {
  final List<Map<String, dynamic>> responses;
  final String actionLabel;

  const _ActionBody({required this.responses, required this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            actionLabel,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Container(width: 40, height: 3, color: kRed),
          const SizedBox(height: 24),
          if (responses.isEmpty)
            const Text('No response yet.', style: TextStyle(color: Colors.black38))
          else
            _ResponseTable(responses: responses),
        ],
      ),
    );
  }
}

class _ResponseTable extends StatelessWidget {
  final List<Map<String, dynamic>> responses;
  const _ResponseTable({required this.responses});

  @override
  Widget build(BuildContext context) {
    final keys = responses.first.keys.toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.black),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        columns: keys.map((k) => DataColumn(label: Text(k))).toList(),
        rows: responses
            .map((row) => DataRow(
                  cells: keys
                      .map((k) => DataCell(Text('${row[k] ?? ''}')))
                      .toList(),
                ))
            .toList(),
      ),
    );
  }
}

// ── Body: Insight ──────────────────────────────────────────────────────────

class _InsightBody extends StatelessWidget {
  final TabController tabController;
  const _InsightBody({required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: tabController,
            labelColor: kRed,
            unselectedLabelColor: Colors.black45,
            indicatorColor: kRed,
            indicatorWeight: 3,
            tabs: _kReportTabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: _kReportTabs
                .map((t) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bar_chart, size: 56, color: Colors.black12),
                          const SizedBox(height: 12),
                          Text(
                            '$t Report',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black38,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'TBD: Looker Studio embed will load here.',
                            style: TextStyle(color: Colors.black26, fontSize: 13),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

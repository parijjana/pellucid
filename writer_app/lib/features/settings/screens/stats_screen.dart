// @trace FEAT-20260517-120000-0005
// Description: Stats Dashboard Screen with visual progress charts.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_provider.dart';
import '../../editor/providers/theme_provider.dart';
import '../../editor/widgets/integrated_header.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final historyProvider = context.watch<HistoryProvider>();
    final stats = historyProvider.history.take(7).toList().reversed.toList();

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: Column(
        children: [
          IntegratedHeader(
            theme: theme,
            actionButton: IconButton(
              icon: Icon(Icons.arrow_back, size: 20, color: theme.foregroundColor.withValues(alpha: 0.4)),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DAILY PROGRESS (LAST 7 DAYS)', 
                    style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 40),
                  
                  // Visual Bar Chart
                  if (stats.isEmpty)
                    _buildEmptyState(theme)
                  else
                    _buildBarChart(stats, theme),

                  const SizedBox(height: 60),
                  _sectionHeader('Key Metrics', theme),
                  const SizedBox(height: 20),
                  _buildStatRow('Words Written Today', '${historyProvider.todayStats?.wordCountDelta ?? 0}', theme),
                  _buildStatRow('Cumulative Time Spent', _formatHours(historyProvider.currentProjectStats.totalTimeSpent), theme),
                  _buildStatRow('Project Word Count', '${historyProvider.currentProjectStats.totalWordCount}', theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, WriterTheme theme) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: theme.foregroundColor.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildEmptyState(WriterTheme theme) {
    return Center(
      child: Text('No writing history recorded yet.', 
        style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.2), fontStyle: FontStyle.italic)),
    );
  }

  Widget _buildBarChart(List<DailyStats> stats, WriterTheme theme) {
    // Find max value for scaling
    final maxSeconds = stats.map((s) => s.editorTime.inSeconds + s.notesTime.inSeconds).fold(1, max);
    final maxWords = stats.map((s) => s.wordCountDelta.abs()).fold(1, max);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: stats.map((s) => _buildBar(s, maxSeconds, maxWords, theme)).toList(),
        ),
        const SizedBox(height: 20),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem('Editor Time', Colors.blue, theme),
            const SizedBox(width: 20),
            _legendItem('Notes Time', Colors.green, theme),
            const SizedBox(width: 20),
            _legendItem('Words (Dot)', Colors.orange, theme),
          ],
        ),
      ],
    );
  }

  Widget _buildBar(DailyStats s, int maxSeconds, int maxWords, WriterTheme theme) {
    const double maxHeight = 200.0;
    final totalSeconds = s.editorTime.inSeconds + s.notesTime.inSeconds;
    final editorHeight = totalSeconds == 0 ? 0.0 : (s.editorTime.inSeconds / maxSeconds) * maxHeight;
    final notesHeight = totalSeconds == 0 ? 0.0 : (s.notesTime.inSeconds / maxSeconds) * maxHeight;
    
    // Word count dot position
    final wordDotPosition = (s.wordCountDelta.abs() / maxWords) * maxHeight;

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Time Bar (Stacked)
            Container(
              width: 30,
              height: editorHeight + notesHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Container(height: notesHeight, width: 30, color: Colors.green.withValues(alpha: 0.4)),
                  Container(height: editorHeight, width: 30, color: Colors.blue.withValues(alpha: 0.4)),
                ],
              ),
            ),
            // Word Count Dot
            Positioned(
              bottom: wordDotPosition,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(s.date.split('-').last, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.4), fontSize: 10)),
      ],
    );
  }

  Widget _legendItem(String label, Color color, WriterTheme theme) {
    return Row(
      children: [
        Container(width: 10, height: 10, color: color.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.5), fontSize: 10)),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, WriterTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.foregroundColor.withValues(alpha: 0.7), fontSize: 14)),
          Text(value, style: TextStyle(color: theme.foregroundColor, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatHours(Duration d) {
    final hours = d.inSeconds / 3600;
    return '${hours.toStringAsFixed(1)} hrs';
  }
}

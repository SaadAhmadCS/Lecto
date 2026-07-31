import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Transcripts screen — view all recordings with their processing status.
///
/// Fetches recordings from the backend API and displays them
/// in a list with status badges, search, and pull-to-refresh.
class TranscriptsScreen extends StatefulWidget {
  const TranscriptsScreen({super.key});

  @override
  State<TranscriptsScreen> createState() => _TranscriptsScreenState();
}

class _TranscriptsScreenState extends State<TranscriptsScreen> {
  final LectoApiClient _api = LectoApiClient();
  List<Map<String, dynamic>> _recordings = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _api.listRecordings(limit: 50);
      final data = response['data'] as Map<String, dynamic>;
      final recordings = (data['recordings'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transcripts',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_recordings.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadRecordings,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.base),
        itemCount: _recordings.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) =>
            _RecordingCard(
              recording: _recordings[index],
              onTap: () => _navigateToDetail(_recordings[index]),
            ),
      ),
    );
  }

  void _navigateToDetail(Map<String, dynamic> recording) {
    final id = recording['id'] as String;
    final title = recording['title'] as String? ?? 'Recording';
    context.push('/recording/$id?title=${Uri.encodeComponent(title)}');
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryDeep,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'No transcripts yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Text(
              'Record a lecture to generate your first transcript.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 48, color: AppColors.textTertiaryDark),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Could not load recordings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Make sure the backend is running.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _loadRecordings,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recording Card Widget ─────────────────────────────────────────

class _RecordingCard extends StatelessWidget {
  final Map<String, dynamic> recording;
  final VoidCallback onTap;

  const _RecordingCard({
    required this.recording,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = recording['title'] as String? ?? 'Untitled';
    final status = recording['processingStatus'] as String? ?? 'pending';
    final createdAt = recording['createdAt'] as String?;
    final durationMs = recording['totalDurationMs'] as int? ?? 0;
    final chunkCount = (recording['_count'] as Map<String, dynamic>?)?['chunks'] as int? ?? 0;
    final subject = recording['subject'] as Map<String, dynamic>?;

    final statusInfo = _getStatusInfo(status);
    final duration = Duration(milliseconds: durationMs);
    final timeAgo = _formatTimeAgo(createdAt);

    return Material(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.darkBorder),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusBadge(
                    label: statusInfo.label,
                    color: statusInfo.color,
                    icon: statusInfo.icon,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.sm),

              // Subject tag
              if (subject != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Color(
                      int.parse(
                        (subject['color'] as String? ?? '#6366F1')
                            .replaceFirst('#', '0xFF'),
                      ),
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    subject['name'] as String? ?? '',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Color(
                            int.parse(
                              (subject['color'] as String? ?? '#6366F1')
                                  .replaceFirst('#', '0xFF'),
                            ),
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Meta row
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 14, color: AppColors.textTertiaryDark),
                  const SizedBox(width: 4),
                  Text(
                    timeAgo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiaryDark,
                        ),
                  ),
                  const SizedBox(width: AppSpacing.base),
                  if (duration.inSeconds > 0) ...[
                    Icon(Icons.timer_outlined,
                        size: 14, color: AppColors.textTertiaryDark),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(duration),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiaryDark,
                          ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                  ],
                  Icon(Icons.layers_outlined,
                      size: 14, color: AppColors.textTertiaryDark),
                  const SizedBox(width: 4),
                  Text(
                    '$chunkCount chunks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiaryDark,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return _StatusInfo('Ready', AppColors.success, Icons.check_circle_rounded);
      case 'transcribing':
      case 'assembling':
      case 'summarizing':
        return _StatusInfo('Processing', AppColors.info, Icons.autorenew_rounded);
      case 'pending':
        return _StatusInfo('Queued', AppColors.warning, Icons.hourglass_empty_rounded);
      case 'failed_transcription':
      case 'failed_assembly':
      case 'failed_summary':
        return _StatusInfo('Failed', AppColors.error, Icons.error_outline_rounded);
      default:
        return _StatusInfo('New', AppColors.textTertiaryDark, Icons.fiber_new_rounded);
    }
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  String _formatTimeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final date = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 7) {
        return '${date.day}/${date.month}/${date.year}';
      }
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(this.label, this.color, this.icon);
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

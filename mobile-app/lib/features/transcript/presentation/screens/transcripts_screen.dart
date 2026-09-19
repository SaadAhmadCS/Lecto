import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_messages.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../features/recording/data/local/local_recording_feed.dart';
import '../../../../features/recording/data/local/recording_dao.dart';
import '../../../../shared/widgets/recording_card.dart';

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
  late final LectoApiClient _api = context.read<LectoApiClient>();
  late final LocalRecordingFeed _localFeed =
      LocalRecordingFeed(dao: context.read<RecordingDao>());
  List<Map<String, dynamic>> _recordings = [];
  RecordingSort _sort = RecordingSort.date;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // On-device recordings first: they are always available, so the list still
    // shows something useful when the backend is unreachable.
    final local = await _localFeed.list();

    try {
      final response = await _api.listRecordings(limit: 50);
      final recordings = (response['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      setState(() {
        _recordings = _sort.apply(LocalRecordingFeed.merge(recordings, local));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        // Offline with local recordings is not an error state — show them.
        if (local.isNotEmpty) {
          _recordings = _sort.apply(local);
          _error = null;
        } else {
          _error = ErrorMessages.from(e);
        }
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
        actions: [
          RecordingSortButton(
            value: _sort,
            onChanged: (sort) => setState(() {
              _sort = sort;
              _recordings = sort.apply(_recordings);
            }),
          ),
        ],
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
        itemBuilder: (context, index) {
          final recording = _recordings[index];
          final id = recording['id'] as String;
          return Dismissible(
            key: Key(id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.darkSurface,
                  title: const Text('Delete Recording'),
                  content: const Text('Delete this recording? This will permanently remove the transcript and notes.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (direction) async {
              try {
                // A local-only recording was never sent, so deleting it on the
                // backend would 404.
                if (recording['isLocalOnly'] == true) {
                  await context.read<RecordingDao>().deleteRecording(id);
                } else {
                  await _api.deleteRecording(id);
                }
                setState(() {
                  _recordings.removeAt(index);
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recording deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ErrorMessages.from(e, action: 'delete the recording'))),
                  );
                }
              }
            },
            child: RecordingCard(
              recording: recording,
              onTap: () => _navigateToDetail(recording),
            ),
          );
        },
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
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: () => context.push('/record'),
            icon: const Icon(Icons.mic_rounded),
            label: const Text('Start Recording'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
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
              _error ?? ErrorMessages.generic,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Recording Detail Screen — view processing status, transcript & summary.
///
/// Polls the backend for processing status and displays
/// results in a beautiful tabbed interface once ready.
class RecordingDetailScreen extends StatefulWidget {
  final String recordingId;
  final String title;

  const RecordingDetailScreen({
    super.key,
    required this.recordingId,
    required this.title,
  });

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final LectoApiClient _api = LectoApiClient();
  Timer? _pollTimer;

  // State
  String _processingStatus = 'pending';
  int _totalChunks = 0;
  int _transcribedChunks = 0;
  int _percentage = 0;
  String? _transcriptContent;
  String? _summaryContent;
  int _wordCount = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await _api.getProcessingStatus(widget.recordingId);
      final data = response['data'] as Map<String, dynamic>;
      final progress = data['progress'] as Map<String, dynamic>;

      setState(() {
        _processingStatus = data['processingStatus'] as String;
        _totalChunks = progress['totalChunks'] as int;
        _transcribedChunks = progress['transcribedChunks'] as int;
        _percentage = progress['percentage'] as int;
        _isLoading = false;
        _error = null;
      });

      // If completed, fetch content
      if (_processingStatus == 'completed') {
        _pollTimer?.cancel();
        await _fetchContent();
      } else if (_processingStatus.startsWith('failed')) {
        _pollTimer?.cancel();
      } else {
        // Still processing — poll every 3s
        _pollTimer?.cancel();
        _pollTimer = Timer(const Duration(seconds: 3), _fetchStatus);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchContent() async {
    try {
      final transcriptResp = await _api.getTranscript(widget.recordingId);
      final summaryResp = await _api.getSummary(widget.recordingId);

      setState(() {
        if (transcriptResp != null) {
          final data = transcriptResp['data'] as Map<String, dynamic>;
          _transcriptContent = data['content'] as String?;
          _wordCount = data['wordCount'] as int? ?? 0;
        }
        if (summaryResp != null) {
          final data = summaryResp['data'] as Map<String, dynamic>;
          _summaryContent = data['content'] as String?;
        }
      });
    } catch (e) {
      // Non-critical — content just won't show
      debugPrint('Failed to fetch content: $e');
    }
  }

  Future<void> _retryProcessing() async {
    setState(() {
      _processingStatus = 'pending';
      _isLoading = true;
    });

    try {
      await _api.startProcessing(widget.recordingId);
      _fetchStatus();
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
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        bottom: _processingStatus == 'completed'
            ? TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondaryDark,
                tabs: const [
                  Tab(icon: Icon(Icons.notes_rounded), text: 'Notes'),
                  Tab(icon: Icon(Icons.description_outlined), text: 'Transcript'),
                ],
              )
            : null,
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

    if (_processingStatus == 'completed') {
      return TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryView(),
          _buildTranscriptView(),
        ],
      );
    }

    if (_processingStatus.startsWith('failed')) {
      return _buildFailedState();
    }

    return _buildProcessingView();
  }

  Widget _buildProcessingView() {
    final stage = _getStageLabel(_processingStatus);
    final icon = _getStageIcon(_processingStatus);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated pulse
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.2),
              duration: const Duration(milliseconds: 1200),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 40),
                  ),
                );
              },
              onEnd: () => setState(() {}), // Loop animation
            ),

            const SizedBox(height: AppSpacing.xl),

            Text(
              stage,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _getStageDescription(_processingStatus),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Progress bar
            if (_totalChunks > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _percentage / 100,
                  backgroundColor: AppColors.darkSurfaceLight,
                  color: AppColors.primary,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Chunk $_transcribedChunks of $_totalChunks · $_percentage%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiaryDark,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryView() {
    if (_summaryContent == null || _summaryContent!.isEmpty) {
      return const Center(child: Text('Summary not available'));
    }

    return Markdown(
      data: _summaryContent!,
      padding: const EdgeInsets.all(AppSpacing.base),
      styleSheet: _markdownStyleSheet(context),
      selectable: true,
    );
  }

  Widget _buildTranscriptView() {
    if (_transcriptContent == null || _transcriptContent!.isEmpty) {
      return const Center(child: Text('Transcript not available'));
    }

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.sm,
          ),
          color: AppColors.darkSurface,
          child: Row(
            children: [
              Icon(Icons.text_snippet_outlined,
                  size: 16, color: AppColors.textTertiaryDark),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$_wordCount words',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiaryDark,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Markdown(
            data: _transcriptContent!,
            padding: const EdgeInsets.all(AppSpacing.base),
            styleSheet: _markdownStyleSheet(context),
            selectable: true,
          ),
        ),
      ],
    );
  }

  Widget _buildFailedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Processing Failed',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _getFailureMessage(_processingStatus),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: _retryProcessing,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Processing'),
            ),
          ],
        ),
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
              'Connection Error',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not reach the server.\nMake sure the backend is running.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _fetchStatus();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    return MarkdownStyleSheet(
      h1: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryDark,
          ),
      h2: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
      h3: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryDark,
          ),
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textPrimaryDark,
            height: 1.6,
          ),
      listBullet: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondaryDark,
          ),
      code: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: AppColors.darkSurfaceLight,
            color: AppColors.accent,
          ),
      blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondaryDark,
            fontStyle: FontStyle.italic,
          ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 3),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
    );
  }

  String _getStageLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Queued';
      case 'transcribing':
        return 'Transcribing...';
      case 'transcribed':
        return 'Transcription Complete';
      case 'assembling':
        return 'Assembling Transcript...';
      case 'assembled':
        return 'Transcript Ready';
      case 'summarizing':
        return 'Generating Notes...';
      default:
        return 'Processing...';
    }
  }

  IconData _getStageIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'transcribing':
        return Icons.mic_rounded;
      case 'transcribed':
      case 'assembling':
      case 'assembled':
        return Icons.description_outlined;
      case 'summarizing':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.pending_rounded;
    }
  }

  String _getStageDescription(String status) {
    switch (status) {
      case 'pending':
        return 'Your recording is in the queue.\nProcessing will start shortly.';
      case 'transcribing':
        return 'AI is listening to your recording\nand converting speech to text.';
      case 'transcribed':
        return 'All audio has been transcribed.\nAssembling the full document...';
      case 'assembling':
        return 'Combining all chunks into\na single transcript document.';
      case 'assembled':
        return 'Transcript is ready.\nGenerating study notes...';
      case 'summarizing':
        return 'AI is analyzing the transcript\nand creating structured study notes.';
      default:
        return 'Processing your recording...';
    }
  }

  String _getFailureMessage(String status) {
    switch (status) {
      case 'failed_transcription':
        return 'Could not transcribe the audio.\nThis may be due to API rate limits or poor audio quality.';
      case 'failed_assembly':
        return 'Could not assemble the transcript.\nPlease retry.';
      case 'failed_summary':
        return 'Transcription succeeded but summary\ngeneration failed. Please retry.';
      default:
        return 'An unexpected error occurred.\nPlease retry.';
    }
  }
}

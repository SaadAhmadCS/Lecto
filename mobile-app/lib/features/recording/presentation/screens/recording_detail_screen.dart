import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/upload_queue_service.dart';
import '../../../../core/services/processing_notifier.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/export_options_sheet.dart';
import '../widgets/recording_audio_player.dart';
import '../widgets/transcript_search.dart';

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
  static const _waitingForUpload = 'waiting_upload';

  late final LectoApiClient _api = context.read<LectoApiClient>();
  late final UploadQueueService _uploadQueue = context
      .read<UploadQueueService>();
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
  late String _title = widget.title;
  Map<String, dynamic>? _subject;
  DateTime? _recordedAt;
  Duration? _duration;

  // In-transcript search (ORG-013)
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  TranscriptSearchIndex? _searchIndex;
  List<TranscriptMatch> _matches = const [];
  int _currentMatch = 0;
  List<GlobalKey> _paragraphKeys = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    ProcessingNotifier.viewingRecordingId = widget.recordingId;
    _fetchStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (ProcessingNotifier.viewingRecordingId == widget.recordingId) {
      ProcessingNotifier.viewingRecordingId = null;
    }
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    // Audio still in the on-device sync queue: the backend may not know this
    // recording yet, so show upload progress instead of a 404 error.
    if (!_uploadQueue.isRecordingFullyUploaded(widget.recordingId)) {
      setState(() {
        _processingStatus = _waitingForUpload;
        _isLoading = false;
        _error = null;
      });
      _pollTimer?.cancel();
      _pollTimer = Timer(const Duration(seconds: 3), _fetchStatus);
      return;
    }

    try {
      final response = await _api.getProcessingStatus(widget.recordingId);
      final data = response['data'] as Map<String, dynamic>;
      final progress = data['progress'] as Map<String, dynamic>;

      if (_subject == null) _loadRecordingInfo();

      if (!mounted) return;
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
      if (!mounted) return;
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

  void _openSearch() {
    final transcript = _transcriptContent;
    if (transcript == null) return;

    final index = _searchIndex ??= TranscriptSearchIndex(transcript);
    setState(() {
      _isSearching = true;
      _paragraphKeys = List.generate(
        index.paragraphs.length,
        (_) => GlobalKey(),
      );
    });
    _tabController.animateTo(1); // Transcript tab
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _matches = const [];
      _currentMatch = 0;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _matches = _searchIndex?.findMatches(query) ?? const [];
      _currentMatch = 0;
    });
    _scrollToCurrentMatch();
  }

  /// Move to the next (+1) or previous (-1) match, wrapping around.
  void _jumpToMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatch = (_currentMatch + delta) % _matches.length;
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    if (_matches.isEmpty) return;
    final key = _paragraphKeys[_matches[_currentMatch].paragraph];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _jumpToMatch(1),
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: const InputDecoration(
        hintText: 'Search transcript',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
      ),
    );
  }

  List<Widget> _buildSearchActions() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return [
      if (hasQuery)
        Center(
          child: Text(
            _matches.isEmpty
                ? 'No matches'
                : '${_currentMatch + 1} of ${_matches.length}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondaryDark),
          ),
        ),
      IconButton(
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
        tooltip: 'Previous match',
        onPressed: _matches.isEmpty ? null : () => _jumpToMatch(-1),
      ),
      IconButton(
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        tooltip: 'Next match',
        onPressed: _matches.isEmpty ? null : () => _jumpToMatch(1),
      ),
      IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close search',
        onPressed: _closeSearch,
      ),
    ];
  }

  /// The backend doesn't know a recording until its upload starts syncing.
  bool get _canEditOnServer => _processingStatus != _waitingForUpload;

  /// Title, subject, date and duration for the app bar and PDF header.
  Future<void> _loadRecordingInfo() async {
    try {
      final response = await _api.getRecording(widget.recordingId);
      final data = response['data'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _title = data['title'] as String? ?? _title;
        _subject = data['subject'] as Map<String, dynamic>?;
        _recordedAt = DateTime.tryParse(data['createdAt'] as String? ?? '');
        final durationMs = data['totalDurationMs'] as int? ?? 0;
        _duration = durationMs > 0 ? Duration(milliseconds: durationMs) : null;
      });
    } catch (e) {
      debugPrint('Failed to load recording info: $e');
    }
  }

  void _onMenuAction(_DetailAction action) {
    switch (action) {
      case _DetailAction.rename:
        _renameRecording();
      case _DetailAction.move:
        _moveRecording();
      case _DetailAction.copy:
        Clipboard.setData(
          ClipboardData(text: _summaryContent ?? _transcriptContent ?? ''),
        );
        _showSnack('Notes copied to clipboard');
      case _DetailAction.delete:
        _deleteRecording();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _renameRecording() async {
    final controller = TextEditingController(text: _title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Rename recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: AppConstants.maxRecordingTitleLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Recording title'),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newTitle == null || newTitle.isEmpty || newTitle == _title) return;

    try {
      await _api.updateRecording(widget.recordingId, title: newTitle);
      if (!mounted) return;
      setState(() => _title = newTitle);
      _showSnack('Recording renamed');
    } catch (e) {
      _showSnack('Failed to rename: $e');
    }
  }

  Future<void> _moveRecording() async {
    final currentSubjectId = _subject?['id'] as String?;

    final target = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _api.listSubjects(),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  'Could not load subjects',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final subjects = (snapshot.data!['data'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    'Move to…',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final subject in subjects)
                  ListTile(
                    leading: Icon(
                      Icons.folder_rounded,
                      color: _parseColor(subject['color'] as String?),
                    ),
                    title: Text(subject['name'] as String? ?? 'Untitled'),
                    trailing: subject['id'] == currentSubjectId
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    enabled: subject['id'] != currentSubjectId,
                    onTap: () => Navigator.of(ctx).pop(subject),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (target == null) return;

    try {
      final response = await _api.updateRecording(
        widget.recordingId,
        subjectId: target['id'] as String,
      );
      final data = response['data'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _subject = data['subject'] as Map<String, dynamic>?);
      _showSnack('Moved to ${target['name']}');
    } catch (e) {
      _showSnack('Failed to move: $e');
    }
  }

  Future<void> _deleteRecording() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete Recording'),
        content: const Text(
          'Delete this recording? This will permanently remove the transcript and notes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.deleteRecording(widget.recordingId);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Recording deleted');
    } catch (e) {
      _showSnack('Failed to delete: $e');
    }
  }

  static Color _parseColor(String? hex) {
    try {
      return Color(int.parse((hex ?? '#6366F1').replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: _isSearching
            ? _buildSearchField()
            : GestureDetector(
                onTap: _canEditOnServer ? _renameRecording : null,
                child: Text(
                  _title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
        actions: _isSearching
            ? _buildSearchActions()
            : [
                if (_processingStatus == 'completed' &&
                    _transcriptContent != null)
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search transcript',
                    onPressed: _openSearch,
                  ),
                if (_processingStatus == 'completed' && _summaryContent != null)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Export PDF',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => ExportOptionsSheet(
                          title: _title,
                          subjectName: _subject?['name'] as String?,
                          recordingDate: _recordedAt,
                          duration: _duration,
                          summaryContent: _summaryContent!,
                          transcriptContent: _transcriptContent,
                        ),
                      );
                    },
                  ),
                PopupMenuButton<_DetailAction>(
                  tooltip: 'More',
                  onSelected: _onMenuAction,
                  itemBuilder: (context) => [
                    if (_canEditOnServer) ...[
                      const PopupMenuItem(
                        value: _DetailAction.rename,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Rename'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _DetailAction.move,
                        child: ListTile(
                          leading: Icon(Icons.drive_file_move_outline),
                          title: Text('Move to…'),
                        ),
                      ),
                    ],
                    if (_processingStatus == 'completed' &&
                        (_summaryContent != null || _transcriptContent != null))
                      const PopupMenuItem(
                        value: _DetailAction.copy,
                        child: ListTile(
                          leading: Icon(Icons.copy_rounded),
                          title: Text('Copy notes'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: _DetailAction.delete,
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.error,
                        ),
                        title: Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
        bottom: _processingStatus == 'completed'
            ? TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondaryDark,
                tabs: const [
                  Tab(icon: Icon(Icons.notes_rounded), text: 'Notes'),
                  Tab(
                    icon: Icon(Icons.description_outlined),
                    text: 'Transcript',
                  ),
                ],
              )
            : null,
      ),
      body: _buildBody(),
      // Plays the audio kept on this device, on every tab and state
      bottomNavigationBar: RecordingAudioPlayerBar(
        recordingId: widget.recordingId,
      ),
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
        children: [_buildSummaryView(), _buildTranscriptView()],
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
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
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
              Icon(
                Icons.text_snippet_outlined,
                size: 16,
                color: AppColors.textTertiaryDark,
              ),
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
          child: _isSearching && _searchController.text.trim().isNotEmpty
              ? SearchableTranscriptView(
                  index: _searchIndex!,
                  matches: _matches,
                  currentMatch: _currentMatch,
                  paragraphKeys: _paragraphKeys,
                )
              : Markdown(
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
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
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
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.textTertiaryDark,
            ),
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
      listBullet: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryDark),
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
          left: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.darkBorder, width: 1)),
      ),
    );
  }

  String _getStageLabel(String status) {
    switch (status) {
      case _waitingForUpload:
        return 'Uploading Audio...';
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
      case _waitingForUpload:
        return Icons.cloud_upload_outlined;
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
      case _waitingForUpload:
        return "Your recording is uploading from this device.\nIt continues automatically when you're online.";
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

enum _DetailAction { rename, move, copy, delete }

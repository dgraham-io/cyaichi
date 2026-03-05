import 'dart:async';
import 'dart:convert';

import 'package:client/api/api_client.dart';
import 'package:client/src/flow/connection_validation.dart';
import 'package:client/src/flow/flow_document_builder.dart';
import 'package:client/src/flow/flow_validation.dart';
import 'package:client/src/flow/node_registry.dart';
import 'package:client/src/flow/primary_output.dart';
import 'package:client/src/flow/run_request_builder.dart';
import 'package:client/src/flow/run_preflight.dart';
import 'package:client/src/flow/run_output_resolver.dart';
import 'package:client/src/io/workspace_root_path.dart';
import 'package:client/src/models/server_models.dart';
import 'package:client/src/workspaces/workspace_state.dart';
import 'package:client/src/widgets/error_banner.dart';
import 'package:client/theme/cyaichi_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

typedef ApiClientFactory =
    ApiClient Function({
      required String baseUrl,
      required int runRequestTimeoutSeconds,
    });

ApiClient _defaultApiClientFactory({
  required String baseUrl,
  required int runRequestTimeoutSeconds,
}) {
  return ApiClient(
    baseUrl: baseUrl,
    runRequestTimeout: Duration(seconds: runRequestTimeoutSeconds),
  );
}

@visibleForTesting
double clampRightOverlaySidebarWidth(
  double requestedWidth,
  double screenWidth,
) {
  final clampedMax = (screenWidth * 0.5).clamp(280.0, double.infinity);
  return requestedWidth.clamp(280.0, clampedMax).toDouble();
}

class FlowCanvasScreen extends StatefulWidget {
  const FlowCanvasScreen({
    super.key,
    this.apiClientFactory = _defaultApiClientFactory,
  });

  final ApiClientFactory apiClientFactory;

  @override
  State<FlowCanvasScreen> createState() => _FlowCanvasScreenState();
}

class _FlowCanvasScreenState extends State<FlowCanvasScreen> {
  static const _uuid = Uuid();

  static const _defaultServerBaseUrl = 'http://localhost:8080';
  static const _defaultRunRequestTimeoutSeconds = 300;
  static const _defaultRunInputFile = 'input.txt';
  static const _defaultRunOutputFile = 'output.txt';
  static const _outputPreviewLimit = 4000;

  static const _prefServerBaseUrl = 'client.server_base_url';
  static const _prefWorkspaceDataRoot = 'client.workspace_data_root';
  static const _prefSelectedWorkspaceId = 'client.selected_workspace_id';
  static const _prefHiddenWorkspaceIDs = 'client.hidden_workspace_ids';
  static const _prefAutoSetHeadOnSave = 'client.auto_set_head_on_save';
  static const _prefNodeTypesCache = 'client.node_types.cache.v1';
  static const _prefRunRequestTimeoutSeconds =
      'client.run_request_timeout_seconds';
  static const _prefLastOpenedFlowWorkspaceId =
      'client.last_opened_flow.workspace_id';
  static const _prefLastOpenedFlowDocId = 'client.last_opened_flow.doc_id';
  static const _prefLastOpenedFlowVerId = 'client.last_opened_flow.ver_id';
  static const _prefRightOverlaySidebarOpen =
      'client.right_overlay_sidebar_open';
  static const _prefRightOverlaySidebarWidth =
      'client.right_overlay_sidebar_width';

  late final NodeFlowController<Map<String, dynamic>, dynamic> _controller;
  late final TextEditingController _flowTitleController;
  late final TextEditingController _inputFileController;
  late final TextEditingController _outputFileController;
  late final TextEditingController _nodePaletteSearchController;

  late ApiClient _apiClient;
  NodeTypeRegistry _nodeTypeRegistry = NodeTypeRegistry.fallback();

  String _serverBaseUrl = _defaultServerBaseUrl;
  late String _workspaceDataRoot = defaultWorkspaceDataRoot();
  bool _settingsLoaded = false;
  String _nodeTypesStatus = 'cached/fallback';

  final List<String> _workspaceIds = <String>[];
  final Map<String, String> _workspaceNames = <String, String>{};
  final Set<String> _hiddenWorkspaceIDs = <String>{};
  String? _selectedWorkspaceId;

  String? _selectedNodeId;
  String? _selectedConnectionId;
  String? _primaryWriteNodeId;
  int _nodeCounter = 1;
  bool _isFlowDirty = false;
  bool _hasAttemptedRun = false;

  bool _isCreatingWorkspace = false;
  bool _isSavingToServer = false;
  bool _isRunning = false;
  String? _connectionRejectReason;
  String? _runValidationError;
  Timer? _validationDebounce;
  List<String> _flowValidationErrors = const <String>[];
  List<String> _flowValidationWarnings = const <String>[];

  String _lastRunStatus = 'idle';
  String? _lastRunError;
  String? _lastRunErrorKind;
  String? _lastRunErrorNodeId;
  String? _lastRunErrorCopyText;
  String? _lastRunErrorCopyJson;
  String? _lastRunId;
  String? _lastRunVerId;
  String? _lastOutputPath;
  String? _lastOutputContent;
  String? _lastOutputContentFull;
  String? _lastOutputArtifactSummary;
  List<String> _lastRunInvocations = const <String>[];
  bool _lastRunRetryable = false;
  bool _lastRunTimedOut = false;
  Duration? _lastRunDuration;
  int _runRequestToken = 0;
  bool _runWaitCancelled = false;

  String? _currentFlowDocId;
  String? _currentFlowVerId;
  String? _currentFlowWorkspaceId;
  List<String> _currentFlowParents = const <String>[];
  bool _autoSetHeadOnSave = false;
  int _runRequestTimeoutSeconds = _defaultRunRequestTimeoutSeconds;
  String? _lastOpenedFlowWorkspaceId;
  String? _lastOpenedFlowDocId;
  String? _lastOpenedFlowVerId;
  bool _isLoadingFlow = false;
  bool _isLoadingWorkspaces = false;
  bool _didShowMissingWorkspaceToast = false;

  int _selectedTabIndex = 0;

  bool _flowsLoading = false;
  String? _flowsError;
  List<FlowListItem> _flows = const <FlowListItem>[];

  bool _runsLoading = false;
  String? _runsError;
  List<RunListItem> _runs = const <RunListItem>[];

  bool _notesLoading = false;
  String? _notesError;
  List<NoteListItem> _notes = const <NoteListItem>[];

  String _lastExportJson = '';
  String _nodePaletteSearchQuery = '';
  Timer? _nodePaletteSearchDebounce;
  bool _isRightOverlaySidebarOpen = true;
  double _rightOverlaySidebarWidth = 360;
  double _canvasZoomLevel = 1.0;

  @override
  void initState() {
    super.initState();

    _controller = NodeFlowController<Map<String, dynamic>, dynamic>(
      // Use official API toggle from vyuh_node_flow to hide attribution.
      config: NodeFlowConfig(scrollToZoom: false, showAttribution: false),
    );
    _flowTitleController = TextEditingController(text: 'My Flow');
    _inputFileController = TextEditingController();
    _outputFileController = TextEditingController();
    _nodePaletteSearchController = TextEditingController();
    _apiClient = _createApiClient(_serverBaseUrl, _runRequestTimeoutSeconds);
    _scheduleFlowValidation(immediate: true);

    _loadSettings();
  }

  ApiClient _createApiClient(String baseUrl, int runRequestTimeoutSeconds) {
    return widget.apiClientFactory(
      baseUrl: baseUrl,
      runRequestTimeoutSeconds: runRequestTimeoutSeconds,
    );
  }

  @override
  void dispose() {
    _validationDebounce?.cancel();
    _nodePaletteSearchDebounce?.cancel();
    _controller.dispose();
    _flowTitleController.dispose();
    _inputFileController.dispose();
    _outputFileController.dispose();
    _nodePaletteSearchController.dispose();
    _apiClient.close();
    super.dispose();
  }

  void _onNodePaletteSearchChanged(String value) {
    _nodePaletteSearchDebounce?.cancel();
    _nodePaletteSearchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _nodePaletteSearchQuery = value;
      });
    });
  }

  void _clearNodePaletteSearch() {
    _nodePaletteSearchDebounce?.cancel();
    _nodePaletteSearchController.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _nodePaletteSearchQuery = '';
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedBaseUrl =
        prefs.getString(_prefServerBaseUrl) ?? _defaultServerBaseUrl;
    final loadedWorkspaceRoot =
        prefs.getString(_prefWorkspaceDataRoot) ?? defaultWorkspaceDataRoot();
    final loadedSelectedWorkspace = prefs.getString(_prefSelectedWorkspaceId);
    final loadedHiddenWorkspaceIDs =
        prefs.getStringList(_prefHiddenWorkspaceIDs) ?? <String>[];
    final loadedAutoSetHead = prefs.getBool(_prefAutoSetHeadOnSave) ?? false;
    final loadedRunRequestTimeout =
        prefs.getInt(_prefRunRequestTimeoutSeconds) ??
        _defaultRunRequestTimeoutSeconds;
    final loadedLastOpenedFlowWorkspaceId = prefs.getString(
      _prefLastOpenedFlowWorkspaceId,
    );
    final loadedLastOpenedFlowDocId = prefs.getString(_prefLastOpenedFlowDocId);
    final loadedLastOpenedFlowVerId = prefs.getString(_prefLastOpenedFlowVerId);
    final loadedRightOverlaySidebarOpen =
        prefs.getBool(_prefRightOverlaySidebarOpen) ?? true;
    final loadedRightOverlaySidebarWidth =
        prefs.getDouble(_prefRightOverlaySidebarWidth) ??
        (prefs.getInt(_prefRightOverlaySidebarWidth)?.toDouble() ?? 360);
    final nodeTypeCacheRaw = prefs.getString(_prefNodeTypesCache);

    _apiClient.close();
    _apiClient = _createApiClient(loadedBaseUrl, loadedRunRequestTimeout);

    var loadedRegistry = NodeTypeRegistry.fallback();
    if (nodeTypeCacheRaw != null && nodeTypeCacheRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(nodeTypeCacheRaw);
        if (decoded is List<dynamic>) {
          final cachedDefs = decoded
              .whereType<Map<String, dynamic>>()
              .map(NodeTypeDef.fromJson)
              .toList(growable: false);
          loadedRegistry = NodeTypeRegistry.fromServerNodeTypes(
            cachedDefs,
            source: NodeTypeRegistrySource.cached,
          );
        }
      } catch (_) {
        loadedRegistry = NodeTypeRegistry.fallback();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _serverBaseUrl = loadedBaseUrl;
      _workspaceDataRoot = loadedWorkspaceRoot;
      _workspaceIds.clear();
      _workspaceNames.clear();
      _hiddenWorkspaceIDs
        ..clear()
        ..addAll(
          loadedHiddenWorkspaceIDs
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty),
        );
      _selectedWorkspaceId = loadedSelectedWorkspace;
      _autoSetHeadOnSave = loadedAutoSetHead;
      _runRequestTimeoutSeconds = loadedRunRequestTimeout < 5
          ? 5
          : loadedRunRequestTimeout;
      _lastOpenedFlowWorkspaceId = loadedLastOpenedFlowWorkspaceId;
      _lastOpenedFlowDocId = loadedLastOpenedFlowDocId;
      _lastOpenedFlowVerId = loadedLastOpenedFlowVerId;
      _isRightOverlaySidebarOpen = loadedRightOverlaySidebarOpen;
      _rightOverlaySidebarWidth = loadedRightOverlaySidebarWidth;
      _nodeTypeRegistry = loadedRegistry;
      _nodeTypesStatus = _nodeTypesStatusLabel(loadedRegistry.source);
      _settingsLoaded = true;
    });

    unawaited(_refreshNodeTypesFromServer(showFailureSnack: true));
    await _refreshWorkspaceData();
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerBaseUrl, _serverBaseUrl);
    await prefs.setString(_prefWorkspaceDataRoot, _workspaceDataRoot);
    await prefs.setBool(_prefAutoSetHeadOnSave, _autoSetHeadOnSave);
    await prefs.setInt(
      _prefRunRequestTimeoutSeconds,
      _runRequestTimeoutSeconds,
    );
    await prefs.remove('client.workspace_ids');
    await prefs.remove('client.workspace_entries.v1');
    if (_selectedWorkspaceId == null) {
      await prefs.remove(_prefSelectedWorkspaceId);
    } else {
      await prefs.setString(_prefSelectedWorkspaceId, _selectedWorkspaceId!);
    }
    await prefs.setStringList(
      _prefHiddenWorkspaceIDs,
      _hiddenWorkspaceIDs.toList(growable: false),
    );
    if (_lastOpenedFlowWorkspaceId == null ||
        _lastOpenedFlowDocId == null ||
        _lastOpenedFlowVerId == null) {
      await prefs.remove(_prefLastOpenedFlowWorkspaceId);
      await prefs.remove(_prefLastOpenedFlowDocId);
      await prefs.remove(_prefLastOpenedFlowVerId);
    } else {
      await prefs.setString(
        _prefLastOpenedFlowWorkspaceId,
        _lastOpenedFlowWorkspaceId!,
      );
      await prefs.setString(_prefLastOpenedFlowDocId, _lastOpenedFlowDocId!);
      await prefs.setString(_prefLastOpenedFlowVerId, _lastOpenedFlowVerId!);
    }
    await prefs.setBool(
      _prefRightOverlaySidebarOpen,
      _isRightOverlaySidebarOpen,
    );
    await prefs.setDouble(
      _prefRightOverlaySidebarWidth,
      _rightOverlaySidebarWidth,
    );
  }

  void _toggleRightOverlaySidebar() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isRightOverlaySidebarOpen = !_isRightOverlaySidebarOpen;
    });
    unawaited(_persistSettings());
  }

  void _zoomCanvasBy(double delta) {
    _controller.zoomBy(delta);
    if (!mounted) {
      return;
    }
    setState(() {
      _canvasZoomLevel = (_canvasZoomLevel + delta).clamp(0.1, 4.0);
    });
  }

  void _resetCanvasZoom() {
    _controller.zoomTo(1.0);
    if (!mounted) {
      return;
    }
    setState(() {
      _canvasZoomLevel = 1.0;
    });
  }

  void _resizeRightOverlaySidebar(double deltaX, double screenWidth) {
    final nextWidth = clampRightOverlaySidebarWidth(
      _rightOverlaySidebarWidth - deltaX,
      screenWidth,
    );
    if (!mounted || (nextWidth - _rightOverlaySidebarWidth).abs() < 0.01) {
      return;
    }
    setState(() {
      _rightOverlaySidebarWidth = nextWidth;
    });
  }

  Future<void> _onWorkspaceSelected(String? workspaceId) async {
    setState(() {
      _selectedWorkspaceId = workspaceId;
      _primaryWriteNodeId = null;
      _hasAttemptedRun = false;
    });
    await _persistSettings();
    await _refreshWorkspaceData();
  }

  Future<bool> _handleTabChange(int nextIndex) async {
    if (nextIndex == _selectedTabIndex) {
      return true;
    }
    if (_selectedTabIndex == 0 && _isFlowDirty) {
      final decision = await _promptUnsavedFlowDecision();
      switch (decision) {
        case _UnsavedFlowDecision.cancel:
          return false;
        case _UnsavedFlowDecision.save:
          final saved = await _saveNewFlowVersionToServer();
          if (!saved) {
            return false;
          }
          break;
        case _UnsavedFlowDecision.discard:
          break;
      }
    }
    if (!mounted) {
      return false;
    }
    setState(() {
      _selectedTabIndex = nextIndex;
    });
    return true;
  }

  Future<_UnsavedFlowDecision> _promptUnsavedFlowDecision() async {
    final result = await showDialog<_UnsavedFlowDecision>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have unsaved flow changes. Update before leaving the Flow editor?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedFlowDecision.discard),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedFlowDecision.cancel),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_UnsavedFlowDecision.save),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
    return result ?? _UnsavedFlowDecision.cancel;
  }

  Future<void> _onTopNavSelected(int index) async {
    if (!await _handleTabChange(index)) {
      return;
    }
    if (index == 1) {
      await _loadFlows();
    }
    if (index == 2) {
      await _loadRuns();
    }
    if (index == 3) {
      await _loadNotes();
    }
  }

  Widget _buildTopNavGroup() {
    return Card(
      key: const Key('top-nav-group'),
      margin: EdgeInsets.zero,
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: ButtonStyle(
              minimumSize: WidgetStateProperty.all(const Size(0, 46)),
              visualDensity: VisualDensity.standard,
              textStyle: WidgetStateProperty.all(
                Theme.of(context).textTheme.labelLarge,
              ),
            ),
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.edit_outlined, size: 20),
                label: Text('Flow'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.account_tree_outlined, size: 20),
                label: Text('Flows'),
              ),
              ButtonSegment<int>(
                value: 2,
                icon: Icon(Icons.history, size: 20),
                label: Text('Runs'),
              ),
              ButtonSegment<int>(
                value: 3,
                icon: Icon(Icons.sticky_note_2_outlined, size: 20),
                label: Text('Notes'),
              ),
            ],
            selected: <int>{_selectedTabIndex},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) {
                return;
              }
              unawaited(_onTopNavSelected(selection.first));
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelectedWorkspace = _selectedWorkspaceId != null;
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: 52,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hub),
                    const SizedBox(width: 8),
                    Text('cyaichi${_isFlowDirty ? ' •' : ''}'),
                  ],
                ),
              ),
              Center(child: _buildTopNavGroup()),
            ],
          ),
        ),
        actions: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Row(
              key: const Key('workspace-title-row'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoadingWorkspaces) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    key: const Key('workspace-title-label'),
                    _currentWorkspaceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hasSelectedWorkspace
                        ? null
                        : Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: PopupMenuButton<_WorkspaceMenuAction>(
                    key: const Key('workspace-actions-button'),
                    tooltip: 'Workspace actions',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert),
                    onSelected: _openWorkspaceMenuAction,
                    itemBuilder: (context) => _buildWorkspaceMenuItems(
                      context,
                      hasSelectedWorkspace: hasSelectedWorkspace,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          if (_selectedTabIndex == 0) ...[
            IconButton(
              tooltip: 'Export JSON',
              onPressed: _onExportJson,
              icon: const Icon(Icons.upload_file),
            ),
            IconButton(
              tooltip: 'Import JSON',
              onPressed: _onImportJson,
              icon: const Icon(Icons.download),
            ),
          ],
          IconButton(
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildFlowTab(),
          _buildFlowsTab(),
          _buildRunsTab(),
          _buildNotesTab(),
        ],
      ),
      floatingActionButton: _selectedTabIndex == 3
          ? FloatingActionButton.extended(
              onPressed: _selectedWorkspaceId == null
                  ? null
                  : _showCreateNoteDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Note'),
            )
          : null,
    );
  }

  Widget _buildFlowTab() {
    final runGuard = _computeRunGuard();
    final hasWorkspaceSelected = _selectedWorkspaceId != null;
    final nodes = _controller.nodes.values.toList(growable: false);
    final selectedNode = _selectedNodeId == null
        ? null
        : _controller.getNode(_selectedNodeId!);
    final selectedConnection = _selectedConnectionId == null
        ? null
        : _controller.getConnection(_selectedConnectionId!);
    final canvasTheme = NodeFlowTheme.dark;

    final hasFlowErrors = _flowValidationErrors.isNotEmpty;
    final hasOtherFlowBlockers =
        runGuard.blockers.isNotEmpty && hasWorkspaceSelected && !hasFlowErrors;
    final runDisabledNoWorkspace = !hasWorkspaceSelected;
    final runDisabledInvalid = hasFlowErrors || hasOtherFlowBlockers;
    final runDisabledRunning = _isRunning;
    final runEnabled =
        !runDisabledNoWorkspace && !runDisabledInvalid && !runDisabledRunning;
    final showRunBlockedOverlay = !runEnabled;
    final firstValidationIssue = hasFlowErrors
        ? _flowValidationErrors.first
        : (hasOtherFlowBlockers ? runGuard.blockers.first : null);
    final runTooltip = runDisabledRunning
        ? 'Running...'
        : runDisabledNoWorkspace
        ? 'Run (select a workspace)'
        : runEnabled
        ? 'Run'
        : firstValidationIssue == null
        ? 'Run (fix flow errors)'
        : 'Run (fix flow errors): $firstValidationIssue';

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            _RunFlowIntent(),
        SingleActivator(LogicalKeyboardKey.enter, meta: true): _RunFlowIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _RunFlowIntent: CallbackAction<_RunFlowIntent>(
            onInvoke: (_) {
              final shortcutGuard = _computeRunGuard(forRunAttempt: true);
              if (_isRunning) {
                return null;
              }
              if (_selectedWorkspaceId != null && shortcutGuard.canRun) {
                unawaited(_runFlow());
              } else {
                _onRunBlockedAttempt();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.delete ||
                    event.logicalKey == LogicalKeyboardKey.backspace)) {
              _deleteSelected();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              AbsorbPointer(
                absorbing: !hasWorkspaceSelected,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final panelWidth = clampRightOverlaySidebarWidth(
                      _rightOverlaySidebarWidth,
                      constraints.maxWidth,
                    );
                    final panelRight = _isRightOverlaySidebarOpen
                        ? 0.0
                        : -(panelWidth + 16);
                    final toggleRight = _isRightOverlaySidebarOpen
                        ? panelWidth + 12
                        : 12.0;
                    return Stack(
                      children: [
                        KeyedSubtree(
                          key: const Key('flow-canvas-pane'),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  CyaichiTheme.background,
                                  CyaichiTheme.surface,
                                  CyaichiTheme.outline.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                            child: Stack(
                              children: [
                                NodeFlowEditor<Map<String, dynamic>, dynamic>(
                                  controller: _controller,
                                  theme: canvasTheme,
                                  nodeBuilder: _buildNodeCard,
                                  behavior: NodeFlowBehavior.design,
                                  events:
                                      NodeFlowEvents<
                                        Map<String, dynamic>,
                                        dynamic
                                      >(
                                        node: NodeEvents(
                                          onSelected: (node) {
                                            setState(() {
                                              _selectedNodeId = node?.id;
                                            });
                                          },
                                        ),
                                        connection:
                                            ConnectionEvents<
                                              Map<String, dynamic>,
                                              dynamic
                                            >(
                                              onBeforeComplete:
                                                  _validateConnectionBeforeComplete,
                                              onCreated: (_) {
                                                _markFlowDirty();
                                              },
                                              onDeleted: (_) {
                                                _markFlowDirty();
                                              },
                                              onSelected: (connection) {
                                                setState(() {
                                                  _selectedConnectionId =
                                                      connection?.id;
                                                });
                                              },
                                              onConnectEnd: (_, __, ___) {
                                                final reason =
                                                    _connectionRejectReason;
                                                if (reason != null && mounted) {
                                                  _showSnack(reason);
                                                  _connectionRejectReason =
                                                      null;
                                                }
                                              },
                                            ),
                                        onSelectionChange: (selection) {
                                          setState(() {
                                            _selectedNodeId =
                                                selection.nodes.isEmpty
                                                ? null
                                                : selection.nodes.first.id;
                                            _selectedConnectionId =
                                                selection.connections.isEmpty
                                                ? null
                                                : selection
                                                      .connections
                                                      .first
                                                      .id;
                                          });
                                        },
                                      ),
                                ),
                                Positioned(
                                  left: 12,
                                  top: 12,
                                  child: _FlowTitleOverlay(
                                    title: _flowTitleController.text,
                                    canUpdate:
                                        !_isSavingToServer &&
                                        _selectedWorkspaceId != null &&
                                        _isFlowDirty,
                                    canDuplicate: !_isSavingToServer,
                                    canSetHead:
                                        !_isSavingToServer &&
                                        _selectedWorkspaceId != null,
                                    onRename: _showRenameFlowDialog,
                                    onUpdate: () {
                                      unawaited(_saveNewFlowVersionToServer());
                                    },
                                    onDuplicate: () {
                                      unawaited(_duplicateCurrentFlow());
                                    },
                                    onSetHead: () {
                                      unawaited(_setCurrentFlowAsHead());
                                    },
                                    runEnabled: runEnabled,
                                    showRunBlockedOverlay:
                                        showRunBlockedOverlay,
                                    isRunning: _isRunning,
                                    runTooltip: runTooltip,
                                    onRun: () {
                                      unawaited(_runFlow());
                                    },
                                  ),
                                ),
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  top: 12,
                                  right: toggleRight,
                                  child: _CanvasControlGroup(
                                    panelOpen: _isRightOverlaySidebarOpen,
                                    onTogglePanel: _toggleRightOverlaySidebar,
                                    onZoomIn: () => _zoomCanvasBy(0.1),
                                    onZoomOut: () => _zoomCanvasBy(-0.1),
                                    onResetZoom: _resetCanvasZoom,
                                    zoomPercent: (_canvasZoomLevel * 100)
                                        .round(),
                                  ),
                                ),
                                if (_isLoadingFlow)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black.withValues(
                                        alpha: 0.28,
                                      ),
                                      child: Center(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outlineVariant,
                                            ),
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            child: Text('Loading flow...'),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          key: const Key('right-overlay-sidebar-position'),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          top: 0,
                          bottom: 0,
                          right: panelRight,
                          child: IgnorePointer(
                            ignoring: !_isRightOverlaySidebarOpen,
                            child: SizedBox(
                              key: const Key('right-overlay-sidebar'),
                              width: panelWidth,
                              child: Stack(
                                children: [
                                  Material(
                                    elevation: 10,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outlineVariant,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    10,
                                                    10,
                                                    10,
                                                    6,
                                                  ),
                                              child: SizedBox(
                                                height: 220,
                                                child: _PalettePanel(
                                                  nodeTypes:
                                                      _nodeTypeRegistry.all,
                                                  onAddNode: _addNode,
                                                  searchController:
                                                      _nodePaletteSearchController,
                                                  searchQuery:
                                                      _nodePaletteSearchQuery,
                                                  onSearchChanged:
                                                      _onNodePaletteSearchChanged,
                                                  onClearSearch:
                                                      _clearNodePaletteSearch,
                                                ),
                                              ),
                                            ),
                                            const Divider(height: 1),
                                            Expanded(
                                              child: _InspectorPanel(
                                                selectedNode: selectedNode,
                                                selectedConnection:
                                                    selectedConnection,
                                                isPrimaryWriteNode:
                                                    selectedNode != null &&
                                                    selectedNode.type ==
                                                        'file.write' &&
                                                    _isPrimaryWriteNode(
                                                      selectedNode.id,
                                                    ),
                                                nodeType: selectedNode == null
                                                    ? null
                                                    : _nodeTypeRegistry.byType(
                                                        selectedNode.type,
                                                      ),
                                                onTitleChanged: (value) =>
                                                    _updateNodeTitle(
                                                      selectedNode,
                                                      value,
                                                    ),
                                                onConfigChanged: (key, value) =>
                                                    _updateNodeConfig(
                                                      selectedNode,
                                                      key,
                                                      value,
                                                    ),
                                                onDeleteNode:
                                                    _deleteSelectedNode,
                                                onDeleteConnection:
                                                    _deleteSelectedConnection,
                                                onSetPrimaryOutput:
                                                    selectedNode == null
                                                    ? null
                                                    : () =>
                                                          _setPrimaryOutputNode(
                                                            selectedNode.id,
                                                          ),
                                              ),
                                            ),
                                            const Divider(height: 1),
                                            _RunPanel(
                                              inputFileController:
                                                  _inputFileController,
                                              outputFileController:
                                                  _outputFileController,
                                              inputFileHint:
                                                  _defaultRunInputFile,
                                              outputFileHint:
                                                  _defaultRunOutputFile,
                                              status: _lastRunStatus,
                                              blockers: runGuard.blockers,
                                              showBlockers: _hasAttemptedRun,
                                              subtleHint:
                                                  !_hasAttemptedRun &&
                                                      runGuard
                                                          .blockers
                                                          .isNotEmpty
                                                  ? runGuard.blockers.first
                                                  : null,
                                              showEmptyHint: nodes.isEmpty,
                                              validationError:
                                                  _runValidationError,
                                              runId: _lastRunId,
                                              runVerId: _lastRunVerId,
                                              error: _lastRunError,
                                              errorKind: _lastRunErrorKind,
                                              errorNodeId: _lastRunErrorNodeId,
                                              errorCopyText:
                                                  _lastRunErrorCopyText,
                                              errorCopyJson:
                                                  _lastRunErrorCopyJson,
                                              invocations: _lastRunInvocations,
                                              outputArtifactSummary:
                                                  _lastOutputArtifactSummary,
                                              outputPath: _lastOutputPath,
                                              outputContent: _lastOutputContent,
                                              outputContentFull:
                                                  _lastOutputContentFull,
                                              isRunning: _isRunning,
                                              duration: _lastRunDuration,
                                              retryable: _lastRunRetryable,
                                              runTimedOut: _lastRunTimedOut,
                                              onRetry: _runFlow,
                                              onCancel: _cancelRunWait,
                                              onOpenRunDetails:
                                                  _openLatestRunDetailsFromPanel,
                                              onRefreshRuns: _loadRuns,
                                              onOpenOutputFileFromTimeout:
                                                  _openKnownOutputFileFromRunPanel,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: MouseRegion(
                                      cursor:
                                          SystemMouseCursors.resizeLeftRight,
                                      child: GestureDetector(
                                        key: const Key(
                                          'right-sidebar-resize-handle-hit',
                                        ),
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragUpdate: (details) {
                                          _resizeRightOverlaySidebar(
                                            details.delta.dx,
                                            constraints.maxWidth,
                                          );
                                        },
                                        onHorizontalDragEnd: (_) {
                                          unawaited(_persistSettings());
                                        },
                                        child: SizedBox(
                                          width: 8,
                                          height: double.infinity,
                                          child: Center(
                                            child: Container(
                                              width: 1,
                                              height: 96,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant
                                                  .withValues(alpha: 0.55),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (!hasWorkspaceSelected)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.24),
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'No workspace selected',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _showSelectWorkspaceDialog,
                                icon: const Icon(Icons.workspaces_outlined),
                                label: const Text('Select workspace'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlowsTab() {
    if (_selectedWorkspaceId == null) {
      return const Center(
        child: Text('Select or create a workspace to view flows.'),
      );
    }
    if (_flowsLoading && _flows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_flowsError != null && _flows.isEmpty) {
      return _ErrorState(
        title: 'Flow list error',
        message: _flowsError!,
        onRetry: _loadFlows,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFlows,
      child: _flows.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No flows found for this workspace.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _flows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final flow = _flows[index];
                return ListTile(
                  title: Text(
                    flow.title.isEmpty ? '(untitled flow)' : flow.title,
                  ),
                  subtitle: SelectionArea(
                    child: Text(
                      '${_friendlyDate(flow.createdAt)}'
                      '${flow.ref.isEmpty ? '' : ' • ref: ${flow.ref}'}\n'
                      'doc_id: ${flow.docId}\n'
                      'ver_id: ${flow.verId}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openFlowFromLibrary(flow),
                );
              },
            ),
    );
  }

  Widget _buildRunsTab() {
    if (_selectedWorkspaceId == null) {
      return const Center(
        child: Text('Select or create a workspace to view runs.'),
      );
    }
    if (_runsLoading && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_runsError != null && _runs.isEmpty) {
      return _ErrorState(
        title: 'Runs list error',
        message: _runsError!,
        onRetry: _loadRuns,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRuns,
      child: _runs.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No runs found for this workspace.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _runs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _runs[index];
                return ListTile(
                  title: Text(_friendlyDate(item.createdAt)),
                  subtitle: Text(
                    'mode: ${item.mode.isEmpty ? 'n/a' : item.mode}',
                  ),
                  trailing: _StatusBadge(status: item.status),
                  onTap: () => _openRunDetails(item),
                );
              },
            ),
    );
  }

  Widget _buildNotesTab() {
    if (_selectedWorkspaceId == null) {
      return const Center(
        child: Text('Select or create a workspace to view notes.'),
      );
    }
    if (_notesLoading && _notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notesError != null && _notes.isEmpty) {
      return _ErrorState(
        title: 'Notes list error',
        message: _notesError!,
        onRetry: _loadNotes,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: _notes.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No notes found for this workspace.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _notes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _notes[index];
                return ListTile(
                  title: Text(item.title.isEmpty ? '(untitled)' : item.title),
                  subtitle: Text(
                    '${item.scope} • ${_friendlyDate(item.createdAt)}\n${item.bodyPreview}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => _openNote(item),
                );
              },
            ),
    );
  }

  Widget _buildNodeCard(BuildContext context, Node<Map<String, dynamic>> node) {
    final data = node.data;
    final nodeType = _nodeTypeRegistry.byType(node.type);
    final title = (data['title'] as String?)?.trim();
    final visibleTitle = (title == null || title.isEmpty)
        ? (nodeType?.displayName ?? node.type)
        : title;
    final config = _readConfig(data);
    final isPrimaryWrite =
        node.type == 'file.write' && _isPrimaryWriteNode(node.id);
    final configSummary = _nodeConfigSummary(node.type, config);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CyaichiTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: node.isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: node.isSelected ? 2 : 1,
        ),
        boxShadow: node.isSelected
            ? [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 1.5,
                ),
              ]
            : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            visibleTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isPrimaryWrite)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _Pill(
                label: 'Primary',
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
          if (configSummary != null) ...[
            const SizedBox(height: 2),
            Text(
              configSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              _Pill(
                label: 'in ${_readFlowPorts(data['inputs']).length}',
                color: Theme.of(context).colorScheme.secondaryContainer,
              ),
              _Pill(
                label: 'out ${_readFlowPorts(data['outputs']).length}',
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    final baseUrlController = TextEditingController(text: _serverBaseUrl);
    final workspaceRootController = TextEditingController(
      text: _workspaceDataRoot,
    );
    final runTimeoutController = TextEditingController(
      text: _runRequestTimeoutSeconds.toString(),
    );
    var autoSetHeadOnSave = _autoSetHeadOnSave;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Client Settings'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Server base URL',
                        hintText: 'http://localhost:8080',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: workspaceRootController,
                      decoration: const InputDecoration(
                        labelText: 'Workspace data root (must match server)',
                        hintText: './workspace-data',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Resolved path: ${resolveWorkspaceDataRoot(workspaceRootController.text)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: runTimeoutController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Run request timeout (seconds)',
                        hintText: '300',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-set head on save'),
                      value: autoSetHeadOnSave,
                      onChanged: (value) {
                        setDialogState(() {
                          autoSetHeadOnSave = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Node types: $_nodeTypesStatus',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      baseUrlController.dispose();
      workspaceRootController.dispose();
      runTimeoutController.dispose();
      return;
    }

    final nextBaseUrl = baseUrlController.text.trim();
    final nextWorkspaceRoot = workspaceRootController.text.trim();
    final nextRunTimeoutRaw = runTimeoutController.text.trim();
    final nextRunTimeout = int.tryParse(nextRunTimeoutRaw);
    baseUrlController.dispose();
    workspaceRootController.dispose();
    runTimeoutController.dispose();

    if (nextBaseUrl.isEmpty || Uri.tryParse(nextBaseUrl) == null) {
      _showSnack('Invalid server URL');
      return;
    }
    if (nextWorkspaceRoot.isEmpty) {
      _showSnack('Workspace data root cannot be empty');
      return;
    }
    if (nextRunTimeout == null || nextRunTimeout < 5) {
      _showSnack('Run request timeout must be an integer >= 5');
      return;
    }

    setState(() {
      _serverBaseUrl = nextBaseUrl;
      _workspaceDataRoot = nextWorkspaceRoot;
      _autoSetHeadOnSave = autoSetHeadOnSave;
      _runRequestTimeoutSeconds = nextRunTimeout;
    });
    _apiClient.close();
    _apiClient = _createApiClient(_serverBaseUrl, _runRequestTimeoutSeconds);
    await _refreshNodeTypesFromServer(showFailureSnack: true);
    await _persistSettings();
    await _refreshWorkspaceData();
    _showSnack('Settings saved');
  }

  String get _currentWorkspaceLabel {
    final id = _selectedWorkspaceId;
    if (id == null) {
      return 'No workspace';
    }
    return _workspaceNames[id] ?? 'Workspace ${_shortId(id)}';
  }

  List<PopupMenuEntry<_WorkspaceMenuAction>> _buildWorkspaceMenuItems(
    BuildContext context, {
    required bool hasSelectedWorkspace,
  }) {
    return [
      PopupMenuItem(
        value: _WorkspaceMenuAction.rename,
        enabled: hasSelectedWorkspace,
        child: const ListTile(
          leading: Icon(Icons.drive_file_rename_outline),
          title: Text('Rename workspace'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: _WorkspaceMenuAction.select,
        child: ListTile(
          leading: Icon(Icons.swap_horiz),
          title: Text('Select workspace'),
          dense: true,
        ),
      ),
      const PopupMenuItem(
        value: _WorkspaceMenuAction.create,
        child: ListTile(
          leading: Icon(Icons.add_circle_outline),
          title: Text('New workspace'),
          dense: true,
        ),
      ),
      PopupMenuItem(
        value: _WorkspaceMenuAction.delete,
        enabled: hasSelectedWorkspace,
        child: ListTile(
          leading: Icon(
            Icons.delete_outline,
            color: hasSelectedWorkspace
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          title: Text(
            'Delete workspace',
            style: TextStyle(
              color: hasSelectedWorkspace
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          dense: true,
        ),
      ),
    ];
  }

  Future<void> _openWorkspaceMenuAction(_WorkspaceMenuAction action) async {
    switch (action) {
      case _WorkspaceMenuAction.rename:
        await _showRenameWorkspaceDialog();
      case _WorkspaceMenuAction.select:
        await _showSelectWorkspaceDialog();
      case _WorkspaceMenuAction.create:
        await _showCreateWorkspaceDialog();
      case _WorkspaceMenuAction.delete:
        await _showDeleteWorkspaceDialog();
    }
  }

  Future<void> _showSelectWorkspaceDialog() async {
    await _showSelectWorkspaceDialogInternal(forceSelection: false);
  }

  Future<void> _showSelectWorkspaceDialogInternal({
    required bool forceSelection,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !forceSelection,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select workspace'),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _workspaceIds.isEmpty
                  ? const Text('No workspaces found on server.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _workspaceIds.length,
                      itemBuilder: (context, index) {
                        final workspaceID = _workspaceIds[index];
                        final workspaceName =
                            _workspaceNames[workspaceID] ??
                            'Workspace ${_shortId(workspaceID)}';
                        return ListTile(
                          leading: const Icon(Icons.workspaces_outlined),
                          title: Text(workspaceName),
                          subtitle: Text(_shortId(workspaceID)),
                          selected: workspaceID == _selectedWorkspaceId,
                          onTap: () async {
                            Navigator.of(dialogContext).pop();
                            await _onWorkspaceSelected(workspaceID);
                          },
                        );
                      },
                    ),
            ),
          ),
          actions: [
            if (!forceSelection && _selectedWorkspaceId != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
            FilledButton.tonalIcon(
              key: const Key('workspace-select-new-workspace'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _showCreateWorkspaceDialog();
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('New workspace'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateWorkspaceDialog() async {
    final controller = TextEditingController();
    var isSubmitting = false;
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New workspace'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: false,
                        decoration: const InputDecoration(
                          labelText: 'Workspace name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 10),
                        ErrorBanner(
                          title: 'Request error',
                          message: errorMessage!,
                          copyText:
                              'title: Request error\nmessage: ${errorMessage!}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  key: const Key('workspace-create-confirm'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          var didCloseDialog = false;
                          final name = controller.text.trim();
                          if (name.isEmpty) {
                            setDialogState(() {
                              errorMessage = 'Workspace name is required.';
                            });
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });
                          try {
                            await _createWorkspace(name);
                            if (mounted && dialogContext.mounted) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              didCloseDialog = true;
                              Navigator.of(dialogContext).pop();
                            }
                          } on ApiError catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                errorMessage = _formatApiError(error);
                              });
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                errorMessage = error.toString();
                              });
                            }
                          } finally {
                            if (dialogContext.mounted && !didCloseDialog) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRenameWorkspaceDialog() async {
    final workspaceID = _selectedWorkspaceId;
    if (workspaceID == null) {
      return;
    }
    final currentName = _workspaceNames[workspaceID] ?? 'Workspace';
    final controller = TextEditingController(text: currentName);
    var isSubmitting = false;
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Rename workspace'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: false,
                        decoration: const InputDecoration(
                          labelText: 'Workspace name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 10),
                        ErrorBanner(
                          title: 'Request error',
                          message: errorMessage!,
                          copyText:
                              'title: Request error\nmessage: ${errorMessage!}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  key: const Key('workspace-rename-save'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          var didCloseDialog = false;
                          final nextName = controller.text.trim();
                          if (nextName.isEmpty) {
                            setDialogState(() {
                              errorMessage = 'Workspace name is required.';
                            });
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });
                          try {
                            await _renameWorkspace(workspaceID, nextName);
                            if (mounted && dialogContext.mounted) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              didCloseDialog = true;
                              Navigator.of(dialogContext).pop();
                            }
                          } on ApiError catch (error) {
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              errorMessage = _formatApiError(error);
                            });
                          } catch (error) {
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              errorMessage = error.toString();
                            });
                          } finally {
                            if (dialogContext.mounted && !didCloseDialog) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteWorkspaceDialog() async {
    final workspaceID = _selectedWorkspaceId;
    if (workspaceID == null) {
      return;
    }
    var isSubmitting = false;
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete workspace?'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This will delete the workspace record and may orphan data on disk. This action is soft-delete only for MVP.',
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      ErrorBanner(
                        title: 'Delete failed',
                        message: errorMessage!,
                        copyText:
                            'title: Delete failed\nmessage: ${errorMessage!}',
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  key: const Key('workspace-delete-confirm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });
                          try {
                            await _softDeleteWorkspace(workspaceID);
                            if (!mounted) {
                              return;
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            await _showSelectWorkspaceDialogInternal(
                              forceSelection: true,
                            );
                          } on ApiError catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                errorMessage = _formatApiError(error);
                              });
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                errorMessage = error.toString();
                              });
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _refreshWorkspaceData() async {
    if (mounted) {
      setState(() {
        _isLoadingFlow = true;
      });
    }
    try {
      await _loadWorkspaces();
      await _loadFlows();
      await _autoOpenFlowForSelectedWorkspace();
      await _loadRuns();
      await _loadNotes();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFlow = false;
        });
      }
    }
  }

  Future<void> _loadWorkspaces() async {
    if (mounted) {
      setState(() {
        _isLoadingWorkspaces = true;
      });
    }
    try {
      final items = dedupeWorkspaceItemsByID(await _apiClient.getWorkspaces())
          .where((item) => !_hiddenWorkspaceIDs.contains(item.workspaceId))
          .toList(growable: false);
      if (!mounted) {
        return;
      }

      final nextIDs = items
          .map((item) => item.workspaceId)
          .toList(growable: false);
      final nextNames = <String, String>{};
      for (final item in items) {
        final trimmedName = item.name.trim();
        nextNames[item.workspaceId] = trimmedName.isEmpty
            ? 'Workspace ${_shortId(item.workspaceId)}'
            : trimmedName;
      }

      final previousSelected = _selectedWorkspaceId;
      final selectedExists =
          previousSelected != null && nextIDs.contains(previousSelected);
      setState(() {
        _workspaceIds
          ..clear()
          ..addAll(nextIDs);
        _workspaceNames
          ..clear()
          ..addAll(nextNames);
        if (!selectedExists) {
          _selectedWorkspaceId = null;
        }
      });

      if (!selectedExists &&
          previousSelected != null &&
          !_didShowMissingWorkspaceToast) {
        _didShowMissingWorkspaceToast = true;
        _showSnack('Previous workspace not found; please select a workspace.');
      }

      await _persistSettings();
    } on ApiError catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceIds.clear();
        _workspaceNames.clear();
        _selectedWorkspaceId = null;
      });
      await _persistSettings();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWorkspaces = false;
        });
      }
    }
  }

  Future<void> _autoOpenFlowForSelectedWorkspace() async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      return;
    }
    if (_flowsError != null) {
      return;
    }
    if (_flows.isEmpty) {
      _controller.clearGraph();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentFlowDocId = null;
        _currentFlowVerId = null;
        _currentFlowWorkspaceId = workspaceId;
        _currentFlowParents = const <String>[];
        _lastOpenedFlowWorkspaceId = workspaceId;
        _lastOpenedFlowDocId = null;
        _lastOpenedFlowVerId = null;
      });
      _scheduleFlowValidation(immediate: true);
      await _persistSettings();
      return;
    }

    FlowListItem? selected;
    if (_lastOpenedFlowWorkspaceId == workspaceId &&
        _lastOpenedFlowDocId != null &&
        _lastOpenedFlowVerId != null) {
      for (final flow in _flows) {
        if (flow.docId == _lastOpenedFlowDocId &&
            flow.verId == _lastOpenedFlowVerId) {
          selected = flow;
          break;
        }
      }
    }
    selected ??= _flows.first;
    if (_currentFlowDocId == selected.docId &&
        _currentFlowVerId == selected.verId &&
        _currentFlowWorkspaceId == workspaceId &&
        _controller.nodes.isNotEmpty) {
      return;
    }
    await _openFlowByListItem(
      selected,
      autoOpen: true,
      showSnack: false,
      selectFlowTab: false,
    );
  }

  Future<void> _refreshNodeTypesFromServer({
    required bool showFailureSnack,
  }) async {
    try {
      final defs = await _apiClient.getNodeTypes();
      if (defs.isEmpty) {
        throw ApiError(message: 'empty node type registry from server');
      }
      final nextRegistry = NodeTypeRegistry.fromServerNodeTypes(
        defs,
        source: NodeTypeRegistrySource.server,
      );
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        defs.map((item) => item.toJson()).toList(growable: false),
      );
      await prefs.setString(_prefNodeTypesCache, encoded);
      if (!mounted) {
        return;
      }
      setState(() {
        _nodeTypeRegistry = nextRegistry;
        _nodeTypesStatus = _nodeTypesStatusLabel(nextRegistry.source);
      });
      _scheduleFlowValidation(immediate: true);
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nodeTypesStatus = _nodeTypesStatusLabel(_nodeTypeRegistry.source);
      });
      if (showFailureSnack) {
        _showCopyableErrorSnack(
          message: 'Node types fetch failed. Using cached/fallback registry.',
          copyText: _buildApiErrorCopyText(
            error,
            title: 'Node types fetch failed',
          ),
        );
      }
      debugPrint('node types fetch failed: ${_formatApiError(error)}');
    }
  }

  String _nodeTypesStatusLabel(NodeTypeRegistrySource source) {
    switch (source) {
      case NodeTypeRegistrySource.server:
        return 'server';
      case NodeTypeRegistrySource.cached:
      case NodeTypeRegistrySource.fallback:
        return 'cached/fallback';
    }
  }

  _RunGuardResult _computeRunGuard({bool forRunAttempt = false}) {
    final blockers = <String>[];
    if (_selectedWorkspaceId == null) {
      blockers.add('Select or create a workspace to save and run.');
    }

    final nodes = _controller.nodes.values.toList(growable: false);
    final edges = _controller.connections.toList(growable: false);
    if (nodes.isEmpty) {
      blockers.add('Add at least one node before running.');
    }
    if (edges.isEmpty) {
      blockers.add('Create at least one connection before running.');
    }

    if (_flowValidationErrors.isNotEmpty) {
      blockers.addAll(_flowValidationErrors);
    }

    final hasFileReadNode = nodes.any((node) => node.type == 'file.read');
    final hasFileWriteNode = nodes.any((node) => node.type == 'file.write');
    final includePathRequirements =
        forRunAttempt ||
        _hasAttemptedRun ||
        hasFileReadNode ||
        hasFileWriteNode;
    if (includePathRequirements) {
      final runDefaultsCheck = buildRunRequestParams(
        enteredInputFile: _inputFileController.text,
        enteredOutputFile: _outputFileController.text,
        readNodeConfigInputFiles: _collectReadNodeInputDefaults(),
        writeNodes: _collectWriteNodeOptions(),
        preferredPrimaryWriteNodeId: _primaryWriteNodeId,
      );
      if (runDefaultsCheck.errorMessage != null) {
        blockers.add(runDefaultsCheck.errorMessage!);
      }
    }

    return _RunGuardResult(canRun: blockers.isEmpty, blockers: blockers);
  }

  void _onRunBlockedAttempt() {
    _runFlowValidationNow();
    final runGuard = _computeRunGuard(forRunAttempt: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _hasAttemptedRun = true;
      _runValidationError = null;
    });
    if (runGuard.blockers.isNotEmpty) {
      _showSnack('Run blocked. Review requirements in Run Panel.');
    }
  }

  void _markFlowDirty() {
    if (!mounted) {
      return;
    }
    if (_isFlowDirty) {
      _scheduleFlowValidation();
      return;
    }
    setState(() {
      _isFlowDirty = true;
    });
    _scheduleFlowValidation();
  }

  void _scheduleFlowValidation({bool immediate = false}) {
    _validationDebounce?.cancel();
    if (immediate) {
      _runFlowValidationNow();
      return;
    }
    _validationDebounce = Timer(const Duration(milliseconds: 220), () {
      _runFlowValidationNow();
    });
  }

  void _runFlowValidationNow() {
    final nodes = _controller.nodes.values.toList(growable: false);
    final edges = _controller.connections.toList(growable: false);
    final result = validateFlowGraph(
      nodes: nodes
          .map(
            (node) => FlowValidationNode(
              id: node.id,
              type: node.type,
              inputPorts: _readFlowPorts(
                node.data['inputs'],
              ).map((port) => port.port).toList(growable: false),
              outputPorts: _readFlowPorts(
                node.data['outputs'],
              ).map((port) => port.port).toList(growable: false),
              config: _readConfig(node.data),
            ),
          )
          .toList(growable: false),
      edges: edges
          .map(
            (edge) => FlowValidationEdge(
              sourceNodeId: edge.sourceNodeId,
              sourcePortId: edge.sourcePortId,
              targetNodeId: edge.targetNodeId,
              targetPortId: edge.targetPortId,
            ),
          )
          .toList(growable: false),
      nodeTypeLookup: _nodeTypeRegistry.byType,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _flowValidationErrors = result.errors
          .map((issue) => issue.message)
          .toList(growable: false);
      _flowValidationWarnings = result.warnings
          .map((issue) => issue.message)
          .toList(growable: false);
    });
  }

  Future<void> _showRenameFlowDialog() async {
    var draftTitle = _flowTitleController.text;
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename flow'),
          content: TextFormField(
            autofocus: true,
            initialValue: draftTitle,
            onChanged: (value) {
              draftTitle = value;
            },
            decoration: const InputDecoration(
              labelText: 'Flow title',
              border: OutlineInputBorder(),
            ),
            onFieldSubmitted: (_) =>
                Navigator.of(dialogContext).pop(draftTitle.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(draftTitle.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (nextTitle == null) {
      return;
    }
    if (nextTitle == _flowTitleController.text) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _flowTitleController.text = nextTitle;
    });
    _markFlowDirty();
  }

  void _clearFlowDirty() {
    if (!_isFlowDirty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isFlowDirty = false;
    });
  }

  Future<void> _loadFlows() async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _flows = const <FlowListItem>[];
        _flowsError = null;
        _flowsLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _flowsLoading = true;
        _flowsError = null;
      });
    }

    try {
      final flows = await _apiClient.getFlows(workspaceId: workspaceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _flows = flows;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _flowsError = _formatApiError(error);
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _flowsLoading = false;
      });
    }
  }

  Future<void> _loadRuns() async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _runs = const <RunListItem>[];
        _runsError = null;
        _runsLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _runsLoading = true;
        _runsError = null;
      });
    }

    try {
      final runs = await _apiClient.getRuns(workspaceId: workspaceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _runs = runs;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _runsError = _formatApiError(error);
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _runsLoading = false;
      });
    }
  }

  Future<void> _loadNotes() async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = const <NoteListItem>[];
        _notesError = null;
        _notesLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _notesLoading = true;
        _notesError = null;
      });
    }

    try {
      final notes = await _apiClient.getNotes(workspaceId: workspaceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = notes;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notesError = _formatApiError(error);
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _notesLoading = false;
      });
    }
  }

  Future<WorkspaceCreated> _createWorkspace(String workspaceName) async {
    if (_isCreatingWorkspace) {
      throw ApiError(message: 'Workspace create already in progress.');
    }

    setState(() {
      _isCreatingWorkspace = true;
    });
    try {
      final created = await _apiClient.createWorkspace(name: workspaceName);
      setState(() {
        _selectedWorkspaceId = created.workspaceId;
      });
      await _loadWorkspaces();
      if (_workspaceIds.contains(created.workspaceId)) {
        setState(() {
          _selectedWorkspaceId = created.workspaceId;
        });
      }
      await _persistSettings();
      await _refreshWorkspaceData();
      _showSnack(
        'Workspace created: $workspaceName (${_shortId(created.workspaceId)})',
      );
      return created;
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingWorkspace = false;
        });
      }
    }
  }

  Future<void> _renameWorkspace(String workspaceID, String nextName) async {
    await _apiClient.patchWorkspace(workspaceId: workspaceID, name: nextName);
    await _loadWorkspaces();
    await _persistSettings();
    _showSnack('Workspace renamed');
  }

  Future<void> _softDeleteWorkspace(String workspaceID) async {
    await _apiClient.deleteWorkspace(workspaceId: workspaceID);
    _hiddenWorkspaceIDs.add(workspaceID);
    if (_selectedWorkspaceId == workspaceID) {
      _selectedWorkspaceId = null;
      _lastOpenedFlowWorkspaceId = null;
      _lastOpenedFlowDocId = null;
      _lastOpenedFlowVerId = null;
    }
    await _loadWorkspaces();
    await _persistSettings();
    _showSnack('Workspace deleted');
  }

  Future<bool> _saveNewFlowVersionToServer() async {
    if (_isSavingToServer) {
      return false;
    }
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      _showSnack('Select or create a workspace first.');
      return false;
    }

    setState(() {
      _isSavingToServer = true;
    });

    final flowDocId =
        _currentFlowDocId != null &&
            _currentFlowWorkspaceId == workspaceId &&
            _currentFlowVerId != null
        ? _currentFlowDocId!
        : _uuid.v4();
    final previousVerID = _currentFlowWorkspaceId == workspaceId
        ? _currentFlowVerId
        : null;
    final flowVerId = _uuid.v4();
    final snapshot = _collectCanvasFlowSnapshot();

    final document = buildFlowDocumentEnvelope(
      workspaceId: workspaceId,
      docId: flowDocId,
      verId: flowVerId,
      createdAt: DateTime.now().toUtc(),
      title: _flowTitleController.text,
      parents: previousVerID == null
          ? const <String>[]
          : <String>[previousVerID],
      nodes: snapshot.$1,
      edges: snapshot.$2,
    );

    try {
      await _apiClient.putFlowDocument(
        docId: flowDocId,
        verId: flowVerId,
        document: document,
      );
      if (_autoSetHeadOnSave) {
        await _apiClient.setHead(
          workspaceId: workspaceId,
          docId: flowDocId,
          verId: flowVerId,
        );
      }

      setState(() {
        _currentFlowDocId = flowDocId;
        _currentFlowVerId = flowVerId;
        _currentFlowWorkspaceId = workspaceId;
        _currentFlowParents = previousVerID == null
            ? const <String>[]
            : <String>[previousVerID];
        _lastOpenedFlowWorkspaceId = workspaceId;
        _lastOpenedFlowDocId = flowDocId;
        _lastOpenedFlowVerId = flowVerId;
        _isFlowDirty = false;
      });
      await _persistSettings();
      await _loadFlows();
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved new version: $flowVerId'),
          action: SnackBarAction(
            label: 'Set Head',
            onPressed: () {
              _setCurrentFlowAsHead();
            },
          ),
        ),
      );
      return true;
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingToServer = false;
        });
      }
    }
  }

  Future<void> _duplicateCurrentFlow() async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      _showSnack('Select or create a workspace first.');
      return;
    }
    if (_isSavingToServer) {
      return;
    }

    setState(() {
      _isSavingToServer = true;
    });

    final docId = _uuid.v4();
    final verId = _uuid.v4();
    final snapshot = _collectCanvasFlowSnapshot();
    final document = buildDuplicateFlowDocument(
      workspaceId: workspaceId,
      docId: docId,
      verId: verId,
      createdAt: DateTime.now().toUtc(),
      title: _flowTitleController.text,
      nodes: snapshot.$1,
      edges: snapshot.$2,
    );

    try {
      await _apiClient.putFlowDocument(
        docId: docId,
        verId: verId,
        document: document,
      );
      if (_autoSetHeadOnSave) {
        await _apiClient.setHead(
          workspaceId: workspaceId,
          docId: docId,
          verId: verId,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _currentFlowDocId = docId;
        _currentFlowVerId = verId;
        _currentFlowWorkspaceId = workspaceId;
        _currentFlowParents = const <String>[];
        _lastOpenedFlowWorkspaceId = workspaceId;
        _lastOpenedFlowDocId = docId;
        _lastOpenedFlowVerId = verId;
        _isFlowDirty = false;
      });
      await _persistSettings();
      await _loadFlows();
      _showSnack(
        _autoSetHeadOnSave
            ? 'Duplicated flow and set head (${_shortId(docId)} @ ${_shortId(verId)})'
            : 'Duplicated flow (${_shortId(docId)} @ ${_shortId(verId)})',
      );
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingToServer = false;
        });
      }
    }
  }

  Future<void> _setCurrentFlowAsHead() async {
    final workspaceId = _selectedWorkspaceId;
    final docId = _currentFlowDocId;
    final verId = _currentFlowVerId;
    if (workspaceId == null || docId == null || verId == null) {
      _showSnack('Open or save a flow first.');
      return;
    }
    if (_currentFlowWorkspaceId != workspaceId) {
      _showSnack(
        'Current flow belongs to workspace ${_shortId(_currentFlowWorkspaceId ?? '')}; select/open a flow in this workspace first.',
      );
      return;
    }
    try {
      await _apiClient.setHead(
        workspaceId: workspaceId,
        docId: docId,
        verId: verId,
      );
      _showSnack('Head set to ${_shortId(docId)} @ ${_shortId(verId)}');
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
    }
  }

  Future<void> _runFlow() async {
    if (_isRunning) {
      return;
    }

    _runFlowValidationNow();

    setState(() {
      _hasAttemptedRun = true;
    });

    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      _showSnack('Select or create a workspace first.');
      return;
    }
    final runGuard = _computeRunGuard(forRunAttempt: true);
    if (!runGuard.canRun) {
      setState(() {
        _runValidationError = null;
      });
      return;
    }

    setState(() {
      _runValidationError = null;
    });

    final initialWrites = _collectWriteNodeOptions();
    final requiresPrimaryDialog =
        initialWrites.length > 1 &&
        choosePrimaryWriteNodeId(
              writes: initialWrites,
              preferredPrimaryNodeId: _primaryWriteNodeId,
            ) ==
            null &&
        _outputFileController.text.trim().isEmpty;
    if (requiresPrimaryDialog) {
      final selectedNodeId = await _promptPrimaryOutputSelection(initialWrites);
      if (selectedNodeId == null) {
        setState(() {
          _runValidationError =
              'Select a primary output node or enter output_file to run.';
        });
        return;
      }
      _setPrimaryOutputNode(selectedNodeId);
    }

    final writes = _collectWriteNodeOptions();
    final validation = buildRunRequestParams(
      enteredInputFile: _inputFileController.text,
      enteredOutputFile: _outputFileController.text,
      readNodeConfigInputFiles: _collectReadNodeInputDefaults(),
      writeNodes: writes,
      preferredPrimaryWriteNodeId: _primaryWriteNodeId,
    );
    if (!validation.isValid || validation.params == null) {
      setState(() {
        _runValidationError =
            validation.errorMessage ?? 'Run validation failed';
      });
      return;
    }
    final params = validation.params!;

    if (_inputFileController.text.trim().isEmpty) {
      _inputFileController.text = params.inputFile;
    }
    if (_outputFileController.text.trim().isEmpty) {
      _outputFileController.text = params.outputFile;
    }
    if (params.primaryWriteNodeId.isNotEmpty) {
      _primaryWriteNodeId = params.primaryWriteNodeId;
    }

    final runToken = ++_runRequestToken;
    final runStartedAt = DateTime.now();
    _runWaitCancelled = false;

    setState(() {
      _isRunning = true;
      _lastRunStatus = 'running';
      _runValidationError = null;
      _lastRunError = null;
      _lastRunErrorKind = null;
      _lastRunErrorNodeId = null;
      _lastRunErrorCopyText = null;
      _lastRunErrorCopyJson = null;
      _lastRunId = null;
      _lastRunVerId = null;
      _lastOutputPath = null;
      _lastOutputContent = null;
      _lastOutputContentFull = null;
      _lastOutputArtifactSummary = null;
      _lastRunInvocations = const <String>[];
      _lastRunRetryable = false;
      _lastRunTimedOut = false;
      _lastRunDuration = null;
    });
    _showSnack('Running...');

    final saveDecision = await ensureFlowSavedForRun(
      isFlowDirty: _isFlowDirty,
      saveNewVersion: _saveNewFlowVersionToServer,
    );
    if (!saveDecision.shouldContinue) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _lastRunStatus = 'failed';
          _lastRunError = saveDecision.errorMessage ?? 'Run preflight failed.';
          _lastRunErrorKind = 'client';
          _lastRunErrorNodeId = null;
          _lastRunErrorCopyText = _buildRunErrorCopyText(
            title: 'Run failed',
            message: saveDecision.errorMessage ?? 'Run preflight failed.',
            kind: 'client',
            workspaceId: workspaceId,
            flowDocId: _currentFlowDocId,
            flowVerId: _currentFlowVerId,
          );
          _lastRunErrorCopyJson = null;
          _lastRunTimedOut = false;
        });
      }
      return;
    }
    if (_currentFlowDocId == null || _currentFlowVerId == null) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _lastRunStatus = 'failed';
          _lastRunError = 'Save flow before running.';
          _lastRunErrorKind = 'client';
          _lastRunErrorNodeId = null;
          _lastRunErrorCopyText = _buildRunErrorCopyText(
            title: 'Run failed',
            message: 'Save flow before running.',
            kind: 'client',
            workspaceId: workspaceId,
          );
          _lastRunErrorCopyJson = null;
          _lastRunTimedOut = false;
        });
      }
      _showSnack('Run failed');
      return;
    }
    if (_currentFlowWorkspaceId != workspaceId) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _lastRunStatus = 'failed';
          _lastRunError =
              'Open or save a flow in the selected workspace before running.';
          _lastRunErrorKind = 'client';
          _lastRunErrorNodeId = null;
          _lastRunErrorCopyText = _buildRunErrorCopyText(
            title: 'Run failed',
            message:
                'Open or save a flow in the selected workspace before running.',
            kind: 'client',
            workspaceId: workspaceId,
            flowDocId: _currentFlowDocId,
            flowVerId: _currentFlowVerId,
          );
          _lastRunErrorCopyJson = null;
          _lastRunTimedOut = false;
        });
      }
      _showSnack('Run failed');
      return;
    }

    try {
      await _apiClient.setHead(
        workspaceId: workspaceId,
        docId: _currentFlowDocId!,
        verId: _currentFlowVerId!,
      );
      if (!_isRunRequestActive(runToken)) {
        return;
      }
      final run = await _apiClient.createRun(
        workspaceId: workspaceId,
        flowDocId: _currentFlowDocId!,
        inputFile: params.inputFile,
        outputFile: params.outputFile,
      );
      if (!_isRunRequestActive(runToken)) {
        return;
      }

      final runDoc = await _apiClient.getDocument(
        docType: 'run',
        docId: run.runId,
        verId: run.runVerId,
      );
      if (!_isRunRequestActive(runToken)) {
        return;
      }
      final runBody = runDoc['body'] as Map<String, dynamic>?;
      final status = runBody?['status'] as String? ?? 'succeeded';
      final traceError = _traceErrorDetails(runBody);
      final invocations = _invocationSummaries(runBody);

      String? outputPath;
      String? outputContent;
      String? outputContentFull;
      String? outputArtifactSummary;
      String? runError = traceError?.message;
      if (status == 'succeeded') {
        final resolution = await resolveRunOutputs(
          runBody: runBody,
          fetchArtifactDocument:
              ({required String docId, required String verId}) {
                return _apiClient.getDocument(
                  docType: 'artifact',
                  docId: docId,
                  verId: verId,
                );
              },
        );
        if (!_isRunRequestActive(runToken)) {
          return;
        }
        if (resolution.outputArtifacts.isNotEmpty) {
          outputArtifactSummary = resolution.outputArtifacts
              .map((item) => item.summary)
              .join(' | ');
          outputPath = resolution.outputArtifacts
              .map((item) => item.path)
              .whereType<String>()
              .firstWhere((path) => path.trim().isNotEmpty, orElse: () => '');
          if (outputPath != null && outputPath!.trim().isEmpty) {
            outputPath = null;
          }
        }
        if (resolution.previewText != null &&
            resolution.previewText!.trim().isNotEmpty) {
          outputContentFull = resolution.previewText!;
          outputContent = outputContentFull.length > _outputPreviewLimit
              ? '${outputContentFull.substring(0, _outputPreviewLimit)}...'
              : outputContentFull;
        } else if (resolution.fallbackMessage != null &&
            resolution.fallbackMessage!.trim().isNotEmpty) {
          runError = resolution.fallbackMessage!;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _lastRunStatus = status;
        _lastRunId = run.runId;
        _lastRunVerId = run.runVerId;
        _lastRunError = runError;
        _lastRunErrorKind = traceError?.kind;
        _lastRunErrorNodeId = traceError?.nodeId;
        _lastRunErrorCopyText = runError == null
            ? null
            : _buildRunErrorCopyText(
                title: status == 'succeeded' ? 'Run warning' : 'Run failed',
                message: runError,
                kind: traceError?.kind,
                nodeId: traceError?.nodeId,
                runId: run.runId,
                runVerId: run.runVerId,
                workspaceId: workspaceId,
                flowDocId: _currentFlowDocId,
                flowVerId: _currentFlowVerId,
              );
        _lastRunErrorCopyJson = null;
        _lastOutputPath = outputPath;
        _lastOutputContent = outputContent;
        _lastOutputContentFull = outputContentFull;
        _lastOutputArtifactSummary = outputArtifactSummary;
        _lastRunInvocations = invocations;
        _lastRunTimedOut = false;
        _lastRunDuration = DateTime.now().difference(runStartedAt);
      });
      _showSnack(status == 'succeeded' ? 'Run succeeded' : 'Run failed');
    } on ApiError catch (error) {
      String status = 'failed';
      String? runId;
      String? runVerId;
      _TraceErrorDetails? traceError;
      List<String> invocationSummaries = const <String>[];

      final body = error.responseBody;
      final isRunCreateTimeout =
          error.isTimeout &&
          error.method == 'POST' &&
          error.endpoint == '/v1/runs';
      final isRetryable = error.isNetwork || error.statusCode == 502;
      if (body != null) {
        final valueRunId = body['run_id'];
        final valueRunVerId = body['run_ver_id'];
        if (valueRunId is String && valueRunId.isNotEmpty) {
          runId = valueRunId;
        }
        if (valueRunVerId is String && valueRunVerId.isNotEmpty) {
          runVerId = valueRunVerId;
        }
      }

      if (runId != null && runVerId != null) {
        try {
          final runDoc = await _apiClient.getDocument(
            docType: 'run',
            docId: runId,
            verId: runVerId,
          );
          if (!_isRunRequestActive(runToken)) {
            return;
          }
          final runBody = runDoc['body'] as Map<String, dynamic>?;
          status = runBody?['status'] as String? ?? status;
          traceError = _traceErrorDetails(runBody);
          invocationSummaries = _invocationSummaries(runBody);
        } on ApiError {
          traceError = null;
        }
      }

      if (!mounted) {
        return;
      }

      final timeoutSeconds = error.timeoutSeconds ?? _runRequestTimeoutSeconds;
      final timeoutOutputPath = params.outputFile;
      final displayErrorMessage = isRunCreateTimeout
          ? 'Run request timed out after ${timeoutSeconds}s. The run may have completed. Check Runs tab.'
          : (traceError?.message ?? _formatApiError(error));

      setState(() {
        _lastRunStatus = isRunCreateTimeout ? 'timed_out' : status;
        _lastRunId = runId;
        _lastRunVerId = runVerId;
        _lastRunError = displayErrorMessage;
        _lastRunErrorKind = traceError?.kind;
        _lastRunErrorNodeId = traceError?.nodeId;
        _lastRunErrorCopyText = _buildRunErrorCopyText(
          title: 'Run failed',
          message: displayErrorMessage,
          kind: traceError?.kind,
          nodeId: traceError?.nodeId,
          runId: runId,
          runVerId: runVerId,
          workspaceId: workspaceId,
          flowDocId: _currentFlowDocId,
          flowVerId: _currentFlowVerId,
          apiError: error,
        );
        _lastRunErrorCopyJson = body == null ? null : jsonEncode(body);
        _lastRunInvocations = invocationSummaries;
        _lastRunRetryable = isRunCreateTimeout ? false : isRetryable;
        _lastRunTimedOut = isRunCreateTimeout;
        if (isRunCreateTimeout) {
          _lastOutputPath = timeoutOutputPath;
        }
        _lastRunDuration = DateTime.now().difference(runStartedAt);
      });
      if (isRunCreateTimeout) {
        _showSnack(
          'Run request timed out after ${timeoutSeconds}s. The run may have completed.',
        );
      } else {
        _showSnack('Run failed');
      }
    } finally {
      if (mounted && _isRunRequestActive(runToken)) {
        setState(() {
          _isRunning = false;
          if (_runWaitCancelled) {
            _lastRunStatus = 'cancelled';
            _lastRunError = 'Run wait cancelled by user.';
          }
        });
      }
      await _loadRuns();
    }
  }

  bool _isRunRequestActive(int token) {
    return token == _runRequestToken && !_runWaitCancelled;
  }

  void _cancelRunWait() {
    if (!_isRunning) {
      return;
    }
    setState(() {
      _runWaitCancelled = true;
      _isRunning = false;
      _lastRunStatus = 'cancelled';
      _lastRunError = 'Run wait cancelled by user.';
    });
    _showSnack('Run wait cancelled');
  }

  List<String> _collectReadNodeInputDefaults() {
    return _controller.nodes.values
        .where((node) => node.type == 'file.read')
        .map((node) => (_readConfig(node.data)['input_file'] as String?) ?? '')
        .toList(growable: false);
  }

  List<String> _invocationSummaries(Map<String, dynamic>? runBody) {
    if (runBody == null) {
      return const <String>[];
    }
    final invocations = runBody['invocations'];
    if (invocations is! List<dynamic>) {
      return const <String>[];
    }
    return invocations
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          final nodeId = entry['node_id'] as String? ?? '(unknown)';
          final status = entry['status'] as String? ?? 'unknown';
          return '$nodeId: $status';
        })
        .toList(growable: false);
  }

  ConnectionValidationResult _validateConnectionBeforeComplete(
    ConnectionCompleteContext<Map<String, dynamic>> context,
  ) {
    final sourceSchema = _schemaForPort(
      context.sourceNode,
      context.sourcePort.id,
    );
    final targetSchema = _schemaForPort(
      context.targetNode,
      context.targetPort.id,
    );
    final result = validateTypedConnection(
      sourceIsOutput: context.sourcePort.isOutput,
      targetIsInput: context.targetPort.isInput,
      sourceSchema: sourceSchema,
      targetSchema: targetSchema,
    );
    if (!result.allowed) {
      _connectionRejectReason = result.reason ?? 'Connection rejected.';
      return ConnectionValidationResult.deny(
        reason: result.reason,
        showMessage: true,
      );
    }
    _connectionRejectReason = null;
    return const ConnectionValidationResult.allow();
  }

  String? _schemaForPort(Node<Map<String, dynamic>> node, String portId) {
    for (final port in _readFlowPorts(node.data['inputs'])) {
      if (port.port == portId && port.schema.trim().isNotEmpty) {
        return port.schema;
      }
    }
    for (final port in _readFlowPorts(node.data['outputs'])) {
      if (port.port == portId && port.schema.trim().isNotEmpty) {
        return port.schema;
      }
    }
    return null;
  }

  Future<void> _deleteSelected() async {
    if (_selectedConnectionId != null) {
      await _deleteSelectedConnection();
      return;
    }
    if (_selectedNodeId != null) {
      await _deleteSelectedNode();
    }
  }

  Future<void> _deleteSelectedConnection() async {
    final connectionId = _selectedConnectionId;
    if (connectionId == null) {
      return;
    }
    try {
      _controller.removeConnection(connectionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedConnectionId = null;
      });
      _markFlowDirty();
      _showSnack('Connection deleted');
    } catch (error) {
      _showSnack('Failed to delete connection: $error');
    }
  }

  Future<void> _deleteSelectedNode() async {
    final nodeId = _selectedNodeId;
    if (nodeId == null) {
      return;
    }
    try {
      _controller.removeNode(nodeId);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedNodeId = null;
        _selectedConnectionId = null;
        if (_primaryWriteNodeId == nodeId) {
          _primaryWriteNodeId = null;
        }
      });
      _markFlowDirty();
      _showSnack('Node deleted');
    } catch (error) {
      _showSnack('Failed to delete node: $error');
    }
  }

  bool _isPrimaryWriteNode(String nodeId) {
    if (_primaryWriteNodeId == nodeId) {
      return true;
    }
    final node = _controller.getNode(nodeId);
    if (node == null || node.type != 'file.write') {
      return false;
    }
    final config = _readConfig(node.data);
    return config['primary'] == true;
  }

  void _setPrimaryOutputNode(String nodeId) {
    for (final node in _controller.nodes.values) {
      if (node.type != 'file.write') {
        continue;
      }
      final config = _readConfig(node.data);
      if (node.id == nodeId) {
        config['primary'] = true;
      } else {
        config.remove('primary');
      }
      node.data['config'] = config;
    }
    setState(() {
      _primaryWriteNodeId = nodeId;
    });
    _markFlowDirty();
    _showSnack('Primary output set');
  }

  List<WriteNodeOption> _collectWriteNodeOptions() {
    return _controller.nodes.values
        .where((node) => node.type == 'file.write')
        .map((node) {
          final config = _readConfig(node.data);
          final outputFile = (config['output_file'] as String?)?.trim() ?? '';
          final title =
              (node.data['title'] as String?)?.trim().isNotEmpty == true
              ? node.data['title'] as String
              : node.id;
          return WriteNodeOption(
            nodeId: node.id,
            title: title,
            outputFile: outputFile,
            isPrimary: _isPrimaryWriteNode(node.id),
          );
        })
        .toList(growable: false);
  }

  Future<String?> _promptPrimaryOutputSelection(
    List<WriteNodeOption> writes,
  ) async {
    return showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select primary output'),
          content: SizedBox(
            width: 640,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: writes.length,
              itemBuilder: (context, index) {
                final write = writes[index];
                final output = write.outputFile.isEmpty
                    ? '(missing)'
                    : write.outputFile;
                return ListTile(
                  title: Text(write.title),
                  subtitle: Text(output),
                  onTap: () => Navigator.of(context).pop(write.nodeId),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRunDetails(RunListItem item) async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _RunDetailsScreen(
          apiClient: _apiClient,
          runItem: item,
          friendlyDate: _friendlyDate,
        ),
      ),
    );
  }

  Future<void> _openLatestRunDetailsFromPanel() async {
    final workspaceId = _selectedWorkspaceId;
    final runId = _lastRunId;
    final runVerId = _lastRunVerId;
    if (workspaceId == null || runId == null || runVerId == null) {
      return;
    }
    final runItem = RunListItem(
      docId: runId,
      verId: runVerId,
      createdAt: DateTime.now().toIso8601String(),
      status: _lastRunStatus,
      mode: 'hybrid',
    );
    await _openRunDetails(runItem);
  }

  Future<void> _openKnownOutputFileFromRunPanel() async {
    final runId = _lastRunId;
    final runVerId = _lastRunVerId;
    if (runId == null || runVerId == null) {
      _showSnack('Run details are not available yet.');
      return;
    }
    try {
      final runDoc = await _apiClient.getRun(docId: runId, verId: runVerId);
      final runBody = runDoc['body'] as Map<String, dynamic>?;
      final resolution = await resolveRunOutputs(
        runBody: runBody,
        fetchArtifactDocument:
            ({required String docId, required String verId}) {
              return _apiClient.getDocument(
                docType: 'artifact',
                docId: docId,
                verId: verId,
              );
            },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final preview = resolution.previewText;
        if (preview != null && preview.trim().isNotEmpty) {
          _lastOutputContentFull = preview;
          _lastOutputContent = preview.length > _outputPreviewLimit
              ? '${preview.substring(0, _outputPreviewLimit)}...'
              : preview;
          _lastRunError = null;
        } else {
          _lastRunError =
              resolution.fallbackMessage ??
              'Output file created on server. Client cannot read server filesystem.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Failed to request file preview: $error');
    }
  }

  Future<void> _openFlowFromLibrary(FlowListItem flow) async {
    await _openFlowByListItem(
      flow,
      autoOpen: false,
      showSnack: true,
      selectFlowTab: true,
    );
  }

  Future<void> _openFlowByListItem(
    FlowListItem flow, {
    required bool autoOpen,
    required bool showSnack,
    required bool selectFlowTab,
  }) async {
    if (mounted) {
      setState(() {
        _isLoadingFlow = true;
      });
    }
    try {
      final document = await _apiClient.getDocument(
        docType: 'flow',
        docId: flow.docId,
        verId: flow.verId,
      );
      _importFlowDocumentMap(document, persistLastOpened: true);
      if (!mounted) {
        return;
      }
      setState(() {
        if (selectFlowTab) {
          _selectedTabIndex = 0;
        }
      });
      if (showSnack) {
        _showSnack(
          'Loaded flow ${_shortId(flow.docId)} @ ${_shortId(flow.verId)}',
        );
      }
    } on ApiError catch (error) {
      if (showSnack || !autoOpen) {
        _showSnack(_formatApiError(error));
      }
    } on FormatException catch (error) {
      if (showSnack || !autoOpen) {
        _showSnack('Invalid flow document: ${error.message}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFlow = false;
        });
      }
    }
  }

  Future<void> _openNote(NoteListItem item) async {
    try {
      final doc = await _apiClient.getNote(
        docId: item.docId,
        verId: item.verId,
      );
      if (!mounted) {
        return;
      }
      final meta = doc['meta'] as Map<String, dynamic>?;
      final body = doc['body'] as Map<String, dynamic>?;
      final content = body?['content'] as Map<String, dynamic>?;
      final fullBody = content?['body'] as String? ?? '';
      final title = meta?['title'] as String? ?? '(untitled)';
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(child: SelectableText(fullBody)),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
    }
  }

  Future<void> _showCreateNoteDialog() async {
    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      _showSnack('Select or create a workspace first.');
      return;
    }
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String scope = 'personal';

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New Note'),
              content: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: scope,
                      decoration: const InputDecoration(
                        labelText: 'Scope',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'personal',
                          child: Text('personal'),
                        ),
                        DropdownMenuItem(value: 'team', child: Text('team')),
                        DropdownMenuItem(value: 'org', child: Text('org')),
                        DropdownMenuItem(
                          value: 'public_read',
                          child: Text('public_read'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          scope = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        labelText: 'Body',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted != true) {
      titleController.dispose();
      bodyController.dispose();
      return;
    }

    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    titleController.dispose();
    bodyController.dispose();

    if (body.isEmpty) {
      _showSnack('Note body cannot be empty');
      return;
    }

    try {
      await _apiClient.createNote(
        workspaceId: workspaceId,
        scope: scope,
        title: title,
        body: body,
      );
      await _loadNotes();
      _showSnack('Note created');
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
    }
  }

  String _friendlyDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  _TraceErrorDetails? _traceErrorDetails(Map<String, dynamic>? runBody) {
    if (runBody == null) {
      return null;
    }
    final traceRef = runBody['trace_ref'];
    if (traceRef is! Map<String, dynamic>) {
      return null;
    }
    final error = traceRef['error'];
    if (error is! Map<String, dynamic>) {
      return null;
    }
    final message = error['message'];
    if (message is! String || message.trim().isEmpty) {
      return null;
    }
    final kind = error['kind'];
    final nodeID = error['node_id'];
    return _TraceErrorDetails(
      message: message,
      kind: kind is String && kind.trim().isNotEmpty ? kind : null,
      nodeId: nodeID is String && nodeID.trim().isNotEmpty ? nodeID : null,
    );
  }

  String _formatApiError(ApiError error) {
    final endpoint = (error.method != null && error.endpoint != null)
        ? '${error.method} ${error.endpoint}'
        : null;
    if (error.isNetwork) {
      if (endpoint != null) {
        return 'server not reachable ($endpoint): ${error.message}';
      }
      return 'server not reachable: ${error.message}';
    }
    if (error.statusCode != null) {
      if (endpoint != null) {
        return 'HTTP ${error.statusCode} ($endpoint): ${error.message}';
      }
      return 'HTTP ${error.statusCode}: ${error.message}';
    }
    if (endpoint != null) {
      return '$endpoint: ${error.message}';
    }
    return error.message;
  }

  String _buildApiErrorCopyText(ApiError error, {String? title}) {
    final lines = <String>[
      'timestamp: ${DateTime.now().toUtc().toIso8601String()}',
      if (title != null && title.trim().isNotEmpty) 'title: $title',
      if (error.statusCode != null) 'status_code: ${error.statusCode}',
      if (error.method != null) 'method: ${error.method}',
      if (error.endpoint != null) 'endpoint: ${error.endpoint}',
      'message: ${error.message}',
    ];
    final body = error.responseBody;
    if (body != null) {
      final runID = body['run_id'];
      final runVerID = body['run_ver_id'];
      if (runID is String && runID.trim().isNotEmpty) {
        lines.add('run_id: $runID');
      }
      if (runVerID is String && runVerID.trim().isNotEmpty) {
        lines.add('run_ver_id: $runVerID');
      }
      final traceRef = body['trace_ref'];
      if (traceRef is Map<String, dynamic>) {
        final traceError = traceRef['error'];
        if (traceError is Map<String, dynamic>) {
          final traceMessage = traceError['message'];
          final traceKind = traceError['kind'];
          final traceNodeID = traceError['node_id'];
          if (traceMessage is String && traceMessage.trim().isNotEmpty) {
            lines.add('trace_ref.error.message: $traceMessage');
          }
          if (traceKind is String && traceKind.trim().isNotEmpty) {
            lines.add('trace_ref.error.kind: $traceKind');
          }
          if (traceNodeID is String && traceNodeID.trim().isNotEmpty) {
            lines.add('trace_ref.error.node_id: $traceNodeID');
          }
        }
      }
    }
    return lines.join('\n');
  }

  String _buildRunErrorCopyText({
    required String title,
    required String message,
    String? kind,
    String? nodeId,
    String? runId,
    String? runVerId,
    String? workspaceId,
    String? flowDocId,
    String? flowVerId,
    ApiError? apiError,
  }) {
    final lines = <String>[
      'timestamp: ${DateTime.now().toUtc().toIso8601String()}',
      'title: $title',
      'message: $message',
      if (kind != null && kind.trim().isNotEmpty) 'kind: $kind',
      if (nodeId != null && nodeId.trim().isNotEmpty) 'node_id: $nodeId',
      if (runId != null && runId.trim().isNotEmpty) 'run_id: $runId',
      if (runVerId != null && runVerId.trim().isNotEmpty)
        'run_ver_id: $runVerId',
      if (workspaceId != null && workspaceId.trim().isNotEmpty)
        'workspace_id: $workspaceId',
      if (flowDocId != null && flowDocId.trim().isNotEmpty)
        'flow_doc_id: $flowDocId',
      if (flowVerId != null && flowVerId.trim().isNotEmpty)
        'flow_ver_id: $flowVerId',
    ];
    if (apiError != null) {
      lines.add('');
      lines.add(_buildApiErrorCopyText(apiError, title: 'API error'));
    }
    return lines.join('\n');
  }

  Future<void> _onExportJson() async {
    final workspaceId = _selectedWorkspaceId ?? _uuid.v4();
    final docId = _currentFlowDocId ?? _uuid.v4();
    final verId = _currentFlowVerId ?? _uuid.v4();
    final snapshot = _collectCanvasFlowSnapshot();

    final exported = buildFlowDocumentEnvelope(
      workspaceId: workspaceId,
      docId: docId,
      verId: verId,
      createdAt: DateTime.now().toUtc(),
      title: _flowTitleController.text,
      parents: _currentFlowParents,
      nodes: snapshot.$1,
      edges: snapshot.$2,
    );

    final prettyJson = const JsonEncoder.withIndent('  ').convert(exported);
    setState(() {
      _lastExportJson = prettyJson;
    });

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Flow JSON'),
          content: SizedBox(
            width: 760,
            child: SelectableText(prettyJson, maxLines: 24),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: prettyJson));
                if (!dialogContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Flow JSON copied to clipboard'),
                  ),
                );
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onImportJson() async {
    final inputController = TextEditingController(text: _lastExportJson);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import Flow JSON'),
          content: SizedBox(
            width: 760,
            child: TextField(
              controller: inputController,
              maxLines: 24,
              decoration: const InputDecoration(
                hintText: 'Paste flow JSON here',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(inputController.text),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    inputController.dispose();

    if (text == null || text.trim().isEmpty) {
      return;
    }

    try {
      _importFlowDocumentJson(text);
      if (!mounted) {
        return;
      }
      _showSnack('Flow imported');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Import failed: $error');
    }
  }

  void _importFlowDocumentJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Top-level JSON must be an object.');
    }
    _importFlowDocumentMap(decoded, persistLastOpened: false);
  }

  void _importFlowDocumentMap(
    Map<String, dynamic> decoded, {
    required bool persistLastOpened,
  }) {
    final parsed = parseFlowDocumentEnvelope(decoded);

    if (persistLastOpened) {
      _lastOpenedFlowWorkspaceId = parsed.workspaceId;
      _lastOpenedFlowDocId = parsed.docId;
      _lastOpenedFlowVerId = parsed.verId;
    }
    unawaited(_persistSettings());

    if (parsed.title.trim().isNotEmpty) {
      _flowTitleController.text = parsed.title;
    }

    _controller.clearGraph();

    final knownNodeIds = <String>{};
    String? importedPrimaryWriteNodeId;
    for (var index = 0; index < parsed.nodes.length; index++) {
      final item = parsed.nodes[index];
      final rawConfig = Map<String, dynamic>.from(item.config);
      final ui = rawConfig['ui'];
      final legacyUI = rawConfig['_ui'];
      final uiMap = ui is Map<String, dynamic>
          ? ui
          : (legacyUI is Map<String, dynamic> ? legacyUI : <String, dynamic>{});
      final nodeType = _nodeTypeRegistry.byType(item.type);
      final inputs = item.inputs.isNotEmpty
          ? item.inputs
          : (nodeType?.inputs.map((port) => port.toFlowPort()).toList() ??
                const <FlowPort>[]);
      final outputs = item.outputs.isNotEmpty
          ? item.outputs
          : (nodeType?.outputs.map((port) => port.toFlowPort()).toList() ??
                const <FlowPort>[]);

      final position = Offset(
        (uiMap['x'] as num?)?.toDouble() ??
            (100 + (index % 4) * 240).toDouble(),
        (uiMap['y'] as num?)?.toDouble() ??
            (100 + (index ~/ 4) * 180).toDouble(),
      );
      final size = Size(
        (uiMap['width'] as num?)?.toDouble() ?? 220,
        (uiMap['height'] as num?)?.toDouble() ?? 132,
      );

      final ports = <Port>[
        ..._buildPorts(inputs, PortPosition.left),
        ..._buildPorts(outputs, PortPosition.right),
      ];

      final node = Node<Map<String, dynamic>>(
        id: item.id,
        type: item.type,
        position: position,
        size: size,
        ports: ports,
        data: <String, dynamic>{
          'title': item.title,
          'config': rawConfig
            ..remove('_ui')
            ..remove('ui'),
          'inputs': inputs.map((port) => port.toJson()).toList(),
          'outputs': outputs.map((port) => port.toJson()).toList(),
        },
      );
      _controller.addNode(node);
      knownNodeIds.add(item.id);
      if (item.type == 'file.write' && rawConfig['primary'] == true) {
        importedPrimaryWriteNodeId = item.id;
      }
    }

    for (final edge in parsed.edges) {
      if (!knownNodeIds.contains(edge.sourceNode) ||
          !knownNodeIds.contains(edge.targetNode)) {
        continue;
      }
      _controller.addConnection(
        Connection<dynamic>(
          id: _uuid.v4(),
          sourceNodeId: edge.sourceNode,
          sourcePortId: edge.sourcePort,
          targetNodeId: edge.targetNode,
          targetPortId: edge.targetPort,
        ),
      );
    }

    setState(() {
      _selectedNodeId = null;
      _lastExportJson = const JsonEncoder.withIndent('  ').convert(decoded);
      _currentFlowDocId = parsed.docId;
      _currentFlowVerId = parsed.verId;
      _currentFlowWorkspaceId = parsed.workspaceId;
      _currentFlowParents = parsed.parents;
      _primaryWriteNodeId = importedPrimaryWriteNodeId;
      _isFlowDirty = false;
      _hasAttemptedRun = false;
    });
    _scheduleFlowValidation(immediate: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fitToView();
    });
    if (kDebugMode) {
      debugPrint(
        'Loaded flow ${parsed.docId}/${parsed.verId} nodes=${parsed.nodes.length} edges=${parsed.edges.length}',
      );
    }
  }

  void _addNode(String typeId) {
    final template = _nodeTypeRegistry.createTemplate(typeId);
    final nodeId = _uuid.v4();
    final title = '${template.displayName} $_nodeCounter';
    final position = Offset(
      120 + ((_nodeCounter - 1) % 4) * 70,
      100 + ((_nodeCounter - 1) ~/ 4) * 70,
    );
    _nodeCounter += 1;

    final ports = <Port>[
      ..._buildPorts(template.inputs, PortPosition.left),
      ..._buildPorts(template.outputs, PortPosition.right),
    ];

    final node = Node<Map<String, dynamic>>(
      id: nodeId,
      type: template.typeId,
      position: position,
      size: const Size(220, 132),
      ports: ports,
      data: <String, dynamic>{
        'title': title,
        'config': Map<String, dynamic>.from(template.config),
        'inputs': template.inputs.map((port) => port.toJson()).toList(),
        'outputs': template.outputs.map((port) => port.toJson()).toList(),
      },
    );

    setState(() {
      _controller.addNode(node);
      _controller.selectNode(nodeId);
      _selectedNodeId = nodeId;
    });
    _markFlowDirty();
  }

  List<Port> _buildPorts(List<FlowPort> defs, PortPosition side) {
    if (defs.isEmpty) {
      return const <Port>[];
    }

    return List<Port>.generate(defs.length, (index) {
      final gap = 132 / (defs.length + 1);
      return Port(
        id: defs[index].port,
        name: defs[index].port,
        position: side,
        type: side == PortPosition.left ? PortType.input : PortType.output,
        offset: Offset(0, (index + 1) * gap),
        multiConnections: true,
      );
    });
  }

  void _updateNodeTitle(Node<Map<String, dynamic>>? node, String value) {
    if (node == null) {
      return;
    }

    setState(() {
      node.data['title'] = value;
    });
    _markFlowDirty();
  }

  void _updateNodeConfig(
    Node<Map<String, dynamic>>? node,
    String key,
    dynamic value,
  ) {
    if (node == null) {
      return;
    }

    setState(() {
      final config = _readConfig(node.data);
      if (value is String && value.trim().isEmpty) {
        config.remove(key);
      } else {
        config[key] = value;
      }
      node.data['config'] = config;
    });
    _markFlowDirty();
  }

  (List<FlowNodeSnapshot>, List<FlowEdgeSnapshot>)
  _collectCanvasFlowSnapshot() {
    final nodes = _controller.nodes.values
        .map((node) {
          final nodeType = _nodeTypeRegistry.byType(node.type);
          final fallbackInputs = _readFlowPorts(node.data['inputs']);
          final fallbackOutputs = _readFlowPorts(node.data['outputs']);
          final inputs = nodeType != null
              ? nodeType.inputs.map((port) => port.toFlowPort()).toList()
              : fallbackInputs;
          final outputs = nodeType != null
              ? nodeType.outputs.map((port) => port.toFlowPort()).toList()
              : fallbackOutputs;
          final config = _readConfig(node.data)
            ..['ui'] = <String, dynamic>{
              'x': node.position.value.dx,
              'y': node.position.value.dy,
              'width': node.size.value.width,
              'height': node.size.value.height,
            };
          return FlowNodeSnapshot(
            id: node.id,
            type: node.type,
            title: (node.data['title'] as String?)?.trim().isNotEmpty == true
                ? node.data['title'] as String
                : node.type,
            inputs: inputs,
            outputs: outputs,
            config: config,
          );
        })
        .toList(growable: false);

    final edges = _controller.connections
        .map(
          (connection) => FlowEdgeSnapshot(
            sourceNode: connection.sourceNodeId,
            sourcePort: connection.sourcePortId,
            targetNode: connection.targetNodeId,
            targetPort: connection.targetPortId,
          ),
        )
        .toList(growable: false);

    return (nodes, edges);
  }

  String? _nodeConfigSummary(String type, Map<String, dynamic> config) {
    switch (type) {
      case 'file.read':
        final inputFile = (config['input_file'] as String?)?.trim();
        if (inputFile != null && inputFile.isNotEmpty) {
          return 'input: $inputFile';
        }
        return null;
      case 'file.write':
        final outputFile = (config['output_file'] as String?)?.trim();
        if (outputFile != null && outputFile.isNotEmpty) {
          return 'output: $outputFile';
        }
        return null;
      case 'llm.chat':
        final model = (config['model'] as String?)?.trim();
        if (model != null && model.isNotEmpty) {
          return 'model: $model';
        }
        return null;
      default:
        return null;
    }
  }

  String _shortId(String id) {
    if (id.length <= 8) {
      return id;
    }
    return id.substring(0, 8);
  }

  String _joinPath(String first, String second, String third) {
    String trimSegment(String value) {
      return value
          .replaceAll(RegExp(r'^/+'), '')
          .replaceAll(RegExp(r'/+$'), '');
    }

    final leadingDot = first.startsWith('./') ? './' : '';
    final cleanFirst = trimSegment(first);
    final cleanSecond = trimSegment(second);
    final cleanThird = trimSegment(third);

    final joined = [
      cleanFirst,
      cleanSecond,
      cleanThird,
    ].where((segment) => segment.isNotEmpty).join('/');

    if (leadingDot.isNotEmpty && !joined.startsWith('./')) {
      return '$leadingDot$joined';
    }
    return joined;
  }

  Map<String, dynamic> _readConfig(Map<String, dynamic> data) {
    final config = data['config'];
    if (config is Map<String, dynamic>) {
      return Map<String, dynamic>.from(config);
    }
    return <String, dynamic>{};
  }

  List<FlowPort> _readFlowPorts(Object? rawPorts) {
    if (rawPorts is! List) {
      return const <FlowPort>[];
    }

    final result = <FlowPort>[];
    for (final item in rawPorts) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final port = item['port'];
      final schema = item['schema'];
      if (port is String && schema is String) {
        result.add(FlowPort(port: port, schema: schema));
      }
    }
    return result;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCopyableErrorSnack({
    required String message,
    required String copyText,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: copyText));
            if (!mounted) {
              return;
            }
            _showSnack('Copied');
          },
        ),
      ),
    );
  }

  @visibleForTesting
  int get debugCanvasNodeCount => _controller.nodes.length;

  @visibleForTesting
  int get debugCanvasEdgeCount => _controller.connections.length;

  @visibleForTesting
  bool get debugHasFlowValidationErrors => _flowValidationErrors.isNotEmpty;

  @visibleForTesting
  List<String> get debugFlowValidationErrors =>
      List<String>.from(_flowValidationErrors);

  @visibleForTesting
  List<String> get debugFlowValidationWarnings =>
      List<String>.from(_flowValidationWarnings);

  @visibleForTesting
  void debugSetSimpleGraphForTest({
    required List<Node<Map<String, dynamic>>> nodes,
    required List<Connection<dynamic>> connections,
  }) {
    _controller.clearGraph();
    for (final node in nodes) {
      _controller.addNode(node);
    }
    for (final connection in connections) {
      _controller.addConnection(connection);
    }
    _scheduleFlowValidation(immediate: true);
  }
}

class _TraceErrorDetails {
  const _TraceErrorDetails({required this.message, this.kind, this.nodeId});

  final String message;
  final String? kind;
  final String? nodeId;
}

class _RunGuardResult {
  const _RunGuardResult({required this.canRun, required this.blockers});

  final bool canRun;
  final List<String> blockers;
}

enum _UnsavedFlowDecision { discard, cancel, save }

enum _WorkspaceMenuAction { rename, select, create, delete }

class _RunFlowIntent extends Intent {
  const _RunFlowIntent();
}

class _FlowTitleOverlay extends StatelessWidget {
  const _FlowTitleOverlay({
    required this.title,
    required this.canUpdate,
    required this.canDuplicate,
    required this.canSetHead,
    required this.onRename,
    required this.onUpdate,
    required this.onDuplicate,
    required this.onSetHead,
    required this.runEnabled,
    required this.showRunBlockedOverlay,
    required this.isRunning,
    required this.runTooltip,
    required this.onRun,
  });

  final String title;
  final bool canUpdate;
  final bool canDuplicate;
  final bool canSetHead;
  final VoidCallback onRename;
  final VoidCallback onUpdate;
  final VoidCallback onDuplicate;
  final VoidCallback onSetHead;
  final bool runEnabled;
  final bool showRunBlockedOverlay;
  final bool isRunning;
  final String runTooltip;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.trim().isEmpty ? '(untitled flow)' : title;
    return Card(
      key: const Key('flow-title-overlay'),
      margin: EdgeInsets.zero,
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  key: const Key('flow-title-display'),
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 6),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    key: const Key('flow-title-edit-menu-rename'),
                    leadingIcon: const Icon(Icons.drive_file_rename_outline),
                    onPressed: onRename,
                    child: const Text('Rename flow'),
                  ),
                  MenuItemButton(
                    key: const Key('flow-title-edit-menu-update'),
                    leadingIcon: const Icon(Icons.system_update_alt),
                    onPressed: canUpdate ? onUpdate : null,
                    child: const Tooltip(
                      message: 'Save as new flow version',
                      child: Text('Update'),
                    ),
                  ),
                  MenuItemButton(
                    key: const Key('flow-title-edit-menu-duplicate'),
                    leadingIcon: const Icon(Icons.content_copy_outlined),
                    onPressed: canDuplicate ? onDuplicate : null,
                    child: const Tooltip(
                      message: 'Duplicate this flow',
                      child: Text('Duplicate'),
                    ),
                  ),
                  MenuItemButton(
                    key: const Key('flow-title-edit-menu-set-head'),
                    leadingIcon: const Icon(Icons.push_pin_outlined),
                    onPressed: canSetHead ? onSetHead : null,
                    child: const Tooltip(
                      message: 'Set workspace head to current flow',
                      child: Text('Set head'),
                    ),
                  ),
                ],
                builder: (context, controller, child) {
                  return Tooltip(
                    message: 'Flow actions',
                    child: IconButton(
                      key: const Key('flow-title-actions-button'),
                      tooltip: null,
                      onPressed: () {
                        if (controller.isOpen) {
                          controller.close();
                          return;
                        }
                        controller.open();
                      },
                      icon: const Icon(Icons.more_vert),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                    ),
                  );
                },
              ),
              SizedBox(
                key: const Key('flow-title-run-divider'),
                height: 24,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.8),
                ),
              ),
              Tooltip(
                key: const Key('flow-title-run-tooltip'),
                message: runTooltip,
                child: IconButton(
                  key: const Key('flow-title-run-button'),
                  tooltip: null,
                  onPressed: runEnabled ? onRun : null,
                  icon: SizedBox(
                    width: 22,
                    height: 22,
                    child: isRunning
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Center(
                                child: Icon(Icons.play_arrow_rounded),
                              ),
                              if (showRunBlockedOverlay)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Icon(
                                    Icons.block,
                                    key: const Key(
                                      'flow-title-run-blocked-overlay',
                                    ),
                                    size: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.error.withValues(alpha: 0.8),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PalettePanel extends StatelessWidget {
  const _PalettePanel({
    required this.nodeTypes,
    required this.onAddNode,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  final List<NodeTypeDefinition> nodeTypes;
  final ValueChanged<String> onAddNode;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final visibleNodeTypes = normalizedQuery.isEmpty
        ? nodeTypes
        : nodeTypes
              .where((type) {
                final name = type.displayName.toLowerCase();
                final typeId = type.typeId.toLowerCase();
                final category = type.category.toLowerCase();
                return name.contains(normalizedQuery) ||
                    typeId.contains(normalizedQuery) ||
                    category.contains(normalizedQuery);
              })
              .toList(growable: false);
    final grouped = <String, List<NodeTypeDefinition>>{};
    for (final type in visibleNodeTypes) {
      grouped
          .putIfAbsent(type.category, () => <NodeTypeDefinition>[])
          .add(type);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceVariant.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('node-palette-search-field'),
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search nodes…',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: normalizedQuery.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('node-palette-search-clear'),
                        tooltip: 'Clear search',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: grouped.isEmpty
                  ? Center(
                      child: Text(
                        'No matching nodes',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...grouped.entries.expand((entry) sync* {
                            yield Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                entry.key.toUpperCase(),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            );
                            for (final nodeType in entry.value) {
                              yield Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: FilledButton.icon(
                                  key: Key('add-${nodeType.typeId}'),
                                  onPressed: () => onAddNode(nodeType.typeId),
                                  icon: Icon(nodeType.icon),
                                  label: Text(nodeType.displayName),
                                ),
                              );
                            }
                            yield const SizedBox(height: 2);
                          }),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({
    required this.selectedNode,
    required this.selectedConnection,
    required this.isPrimaryWriteNode,
    required this.nodeType,
    required this.onTitleChanged,
    required this.onConfigChanged,
    required this.onDeleteNode,
    required this.onDeleteConnection,
    required this.onSetPrimaryOutput,
  });

  final Node<Map<String, dynamic>>? selectedNode;
  final Connection<dynamic>? selectedConnection;
  final bool isPrimaryWriteNode;
  final NodeTypeDefinition? nodeType;
  final ValueChanged<String> onTitleChanged;
  final void Function(String key, dynamic value) onConfigChanged;
  final Future<void> Function() onDeleteNode;
  final Future<void> Function() onDeleteConnection;
  final VoidCallback? onSetPrimaryOutput;

  @override
  Widget build(BuildContext context) {
    if (selectedNode == null && selectedConnection == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Inspector\n\nSelect a node on the canvas.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    if (selectedNode == null && selectedConnection != null) {
      final connection = selectedConnection!;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Connection\n${connection.sourceNodeId}.${connection.sourcePortId} -> ${connection.targetNodeId}.${connection.targetPortId}',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onDeleteConnection,
              icon: const Icon(Icons.delete),
              label: const Text('Delete connection'),
            ),
          ],
        ),
      );
    }

    final node = selectedNode!;
    final title = (node.data['title'] as String?) ?? '';
    final config = _readConfigStatic(node.data);
    final definition = nodeType;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            definition?.displayName ?? node.type,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: Key('title-field-${node.id}'),
            initialValue: title,
            decoration: const InputDecoration(
              labelText: 'Node title',
              border: OutlineInputBorder(),
            ),
            onChanged: onTitleChanged,
          ),
          const SizedBox(height: 12),
          ...?definition?.inspectorFields.map((field) {
            final label = field.optionalHint
                ? '${field.label} (optional)'
                : field.label;
            switch (field.kind) {
              case NodeInspectorFieldKind.string:
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    key: Key('${field.key}-field-${node.id}'),
                    initialValue: (config[field.key] as String?) ?? '',
                    minLines: field.multiline ? 2 : 1,
                    maxLines: field.multiline ? 5 : 1,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => onConfigChanged(field.key, value),
                  ),
                );
              case NodeInspectorFieldKind.boolType:
                final value = config[field.key] == true;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    value: value,
                    onChanged: (value) => onConfigChanged(field.key, value),
                  ),
                );
            }
          }),
          if (node.type == 'file.write') ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: onSetPrimaryOutput,
              icon: const Icon(Icons.flag),
              label: Text(
                isPrimaryWriteNode
                    ? 'Primary Output Selected'
                    : 'Set as Primary Output',
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onDeleteNode,
            icon: const Icon(Icons.delete),
            label: const Text('Delete node'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _readConfigStatic(Map<String, dynamic> data) {
    final config = data['config'];
    if (config is Map<String, dynamic>) {
      return Map<String, dynamic>.from(config);
    }
    return <String, dynamic>{};
  }
}

class _RunPanel extends StatelessWidget {
  const _RunPanel({
    required this.inputFileController,
    required this.outputFileController,
    required this.inputFileHint,
    required this.outputFileHint,
    required this.status,
    required this.blockers,
    required this.showBlockers,
    required this.subtleHint,
    required this.showEmptyHint,
    required this.validationError,
    required this.runId,
    required this.runVerId,
    required this.error,
    required this.errorKind,
    required this.errorNodeId,
    required this.errorCopyText,
    required this.errorCopyJson,
    required this.invocations,
    required this.outputArtifactSummary,
    required this.outputPath,
    required this.outputContent,
    required this.outputContentFull,
    required this.isRunning,
    required this.duration,
    required this.retryable,
    required this.runTimedOut,
    required this.onRetry,
    required this.onCancel,
    required this.onOpenRunDetails,
    required this.onRefreshRuns,
    required this.onOpenOutputFileFromTimeout,
  });

  final TextEditingController inputFileController;
  final TextEditingController outputFileController;
  final String inputFileHint;
  final String outputFileHint;
  final String status;
  final List<String> blockers;
  final bool showBlockers;
  final String? subtleHint;
  final bool showEmptyHint;
  final String? validationError;
  final String? runId;
  final String? runVerId;
  final String? error;
  final String? errorKind;
  final String? errorNodeId;
  final String? errorCopyText;
  final String? errorCopyJson;
  final List<String> invocations;
  final String? outputArtifactSummary;
  final String? outputPath;
  final String? outputContent;
  final String? outputContentFull;
  final bool isRunning;
  final Duration? duration;
  final bool retryable;
  final bool runTimedOut;
  final Future<void> Function() onRetry;
  final VoidCallback onCancel;
  final Future<void> Function() onOpenRunDetails;
  final Future<void> Function() onRefreshRuns;
  final Future<void> Function() onOpenOutputFileFromTimeout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Run Panel',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _RunStatusChip(status: status, isRunning: isRunning),
                    ],
                  );
                }
                return Row(
                  children: [
                    Text(
                      'Run Panel',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    _RunStatusChip(status: status, isRunning: isRunning),
                  ],
                );
              },
            ),
            if (isRunning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Running...'),
                  ],
                ),
              ),
            if (validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ErrorBanner(
                  title: 'Validation error',
                  message: validationError!,
                  copyText:
                      'title: Validation error\nmessage: ${validationError!}',
                ),
              ),
            if (showEmptyHint)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Add nodes from the left palette to get started.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (!showBlockers && subtleHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Run unavailable: $subtleHint',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (showBlockers && blockers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ErrorBanner(
                  title: 'Run blocked',
                  message: blockers.map((item) => '• $item').join('\n'),
                  copyText: 'title: Run blocked\n${blockers.join('\n')}',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: inputFileController,
              decoration: InputDecoration(
                labelText: 'input_file',
                hintText: inputFileHint,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: outputFileController,
              decoration: InputDecoration(
                labelText: 'output_file',
                hintText: outputFileHint,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (runId != null) Text('run_id: $runId'),
            if (runVerId != null) Text('run_ver_id: $runVerId'),
            if (duration != null)
              Text('duration: ${duration!.inMilliseconds}ms'),
            if (outputArtifactSummary != null)
              Text('output_artifact: $outputArtifactSummary'),
            if (outputPath != null)
              SelectionArea(child: Text('output_path: $outputPath')),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ErrorBanner(
                  title: 'Run failed',
                  message: [
                    if (errorKind != null) 'kind: $errorKind',
                    if (errorNodeId != null) 'node_id: $errorNodeId',
                    error!,
                  ].join('\n'),
                  copyText: errorCopyText,
                  copyJsonText: errorCopyJson,
                ),
              ),
            if (invocations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invocations',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    ...invocations.map((line) => Text('• $line')),
                  ],
                ),
              ),
            if (runId != null && runVerId != null && status == 'failed')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: onOpenRunDetails,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open run details'),
                ),
              ),
            if (runTimedOut)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onRefreshRuns,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Runs'),
                    ),
                    if (outputPath != null && outputPath!.trim().isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: onOpenOutputFileFromTimeout,
                        icon: const Icon(Icons.file_open),
                        label: const Text('Request file preview'),
                      ),
                  ],
                ),
              ),
            if ((retryable || isRunning) && !isRunning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            if (isRunning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel wait'),
                ),
              ),
            if (outputContent != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: SelectableText(outputContent!),
                ),
              ),
            if (outputContent != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: outputContent!),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Output copied to clipboard'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy output'),
                    ),
                    if (outputPath != null)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: outputPath!),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Output path copied'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy output file path'),
                      ),
                    if (outputContentFull != null &&
                        outputContentFull!.length > outputContent!.length)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) {
                              return AlertDialog(
                                title: const Text('Full output'),
                                content: SizedBox(
                                  width: 760,
                                  child: SingleChildScrollView(
                                    child: SelectableText(outputContentFull!),
                                  ),
                                ),
                                actions: [
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                    child: const Text('Close'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.open_in_full),
                        label: const Text('Open full'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunStatusChip extends StatelessWidget {
  const _RunStatusChip({required this.status, required this.isRunning});

  final String status;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final normalized = isRunning ? 'running' : status;
    late final Color color;
    switch (normalized) {
      case 'succeeded':
        color = Colors.green;
        break;
      case 'failed':
        color = Theme.of(context).colorScheme.error;
        break;
      case 'timed_out':
        color = Theme.of(context).colorScheme.error;
        break;
      case 'running':
        color = Colors.orange;
        break;
      default:
        color = Theme.of(context).colorScheme.outline;
        break;
    }

    return Tooltip(
      message: normalized,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            normalized,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    switch (status) {
      case 'succeeded':
        color = Colors.green;
        break;
      case 'failed':
        color = Theme.of(context).colorScheme.error;
        break;
      default:
        color = Theme.of(context).colorScheme.outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorBanner(
              title: title,
              message: message,
              copyText: 'title: $title\nmessage: $message',
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _CanvasControlGroup extends StatelessWidget {
  const _CanvasControlGroup({
    required this.panelOpen,
    required this.onTogglePanel,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.zoomPercent,
  });

  final bool panelOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final int zoomPercent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('canvas-control-group'),
      margin: EdgeInsets.zero,
      elevation: 3,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: SizedBox(
          width: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: panelOpen ? 'Hide panel' : 'Show panel',
                child: IconButton(
                  key: const Key('right-sidebar-toggle'),
                  tooltip: null,
                  onPressed: onTogglePanel,
                  icon: Icon(
                    panelOpen ? Icons.chevron_right : Icons.chevron_left,
                  ),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Container(
                  key: const Key('canvas-toggle-zoom-divider'),
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              Tooltip(
                key: const Key('canvas-zoom-in-tooltip'),
                message: 'Zoom in',
                child: IconButton(
                  key: const Key('canvas-zoom-in-button'),
                  tooltip: null,
                  onPressed: onZoomIn,
                  icon: const Icon(Icons.add),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Tooltip(
                key: const Key('canvas-zoom-out-tooltip'),
                message: 'Zoom out',
                child: IconButton(
                  key: const Key('canvas-zoom-out-button'),
                  tooltip: null,
                  onPressed: onZoomOut,
                  icon: const Icon(Icons.remove),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Text(
                    key: const Key('canvas-zoom-percent-label'),
                    '$zoomPercent%',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Tooltip(
                key: const Key('canvas-zoom-reset-tooltip'),
                message: 'Reset zoom',
                child: IconButton(
                  key: const Key('canvas-zoom-reset-button'),
                  tooltip: null,
                  onPressed: onResetZoom,
                  icon: const Icon(Icons.center_focus_strong_outlined),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunDetailsScreen extends StatefulWidget {
  const _RunDetailsScreen({
    required this.apiClient,
    required this.runItem,
    required this.friendlyDate,
  });

  final ApiClient apiClient;
  final RunListItem runItem;
  final String Function(String raw) friendlyDate;

  @override
  State<_RunDetailsScreen> createState() => _RunDetailsScreenState();
}

class _RunDetailsScreenState extends State<_RunDetailsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _runDoc;
  String? _outputPreview;
  String? _outputPreviewError;
  String? _outputPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final runDoc = await widget.apiClient.getRun(
        docId: widget.runItem.docId,
        verId: widget.runItem.verId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _runDoc = runDoc;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openOutputFile(
    String outputDocId,
    String outputVerId,
    BuildContext context,
  ) async {
    setState(() {
      _outputPreview = null;
      _outputPreviewError = null;
      _outputPath = null;
    });

    try {
      final runBody = _runDoc?['body'] as Map<String, dynamic>?;
      final resolution = await resolveRunOutputs(
        runBody: runBody,
        fetchArtifactDocument:
            ({required String docId, required String verId}) {
              return widget.apiClient.getDocument(
                docType: 'artifact',
                docId: docId,
                verId: verId,
              );
            },
      );
      final selectedOutput = resolution.outputArtifacts.firstWhere(
        (item) =>
            item.ref.docId == outputDocId && item.ref.verId == outputVerId,
        orElse: () => ResolvedRunOutputArtifact(
          ref: ArtifactRefId(docId: outputDocId, verId: outputVerId),
          schema: '',
          path: null,
          bytes: null,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _outputPath = selectedOutput.path;
        final preview = resolution.previewText;
        if (preview != null && preview.trim().isNotEmpty) {
          _outputPreview = preview.length > 2000
              ? '${preview.substring(0, 2000)}...'
              : preview;
        } else {
          _outputPreview = null;
          _outputPreviewError =
              resolution.fallbackMessage ??
              'Output file created on server. Client cannot read server filesystem.';
        }
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _outputPreviewError = error.toString();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _outputPreviewError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final runBody = _runDoc?['body'];
    final body = runBody is Map<String, dynamic>
        ? runBody
        : const <String, dynamic>{};
    final flowRef = body['flow_ref'];
    final flowRefMap = flowRef is Map<String, dynamic>
        ? flowRef
        : const <String, dynamic>{};
    final invocations = body['invocations'];
    final invocationList = invocations is List
        ? invocations.whereType<Map<String, dynamic>>().toList(growable: false)
        : const <Map<String, dynamic>>[];
    final outputs = body['outputs'];
    final outputList = outputs is List
        ? outputs.whereType<Map<String, dynamic>>().toList(growable: false)
        : const <Map<String, dynamic>>[];
    final traceRef = body['trace_ref'];
    final traceRefMap = traceRef is Map<String, dynamic>
        ? traceRef
        : const <String, dynamic>{};
    final traceError = traceRefMap['error'];
    final traceErrorMap = traceError is Map<String, dynamic>
        ? traceError
        : const <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Run Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(
              title: 'Run details error',
              message: _error!,
              onRetry: _load,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'created_at: ${widget.friendlyDate(widget.runItem.createdAt)}',
                ),
                const SizedBox(height: 8),
                Text('status: ${widget.runItem.status}'),
                Text('mode: ${widget.runItem.mode}'),
                const SizedBox(height: 12),
                Text(
                  'flow_ref: ${flowRefMap['doc_id'] ?? ''} @ ${flowRefMap['ver_id'] ?? ''}',
                ),
                const SizedBox(height: 16),
                Text(
                  'Invocations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (invocationList.isEmpty) const Text('(none)'),
                ...invocationList.map((invocation) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(invocation['node_id'] as String? ?? ''),
                    trailing: _StatusBadge(
                      status: invocation['status'] as String? ?? 'unknown',
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text('Error', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (traceErrorMap.isEmpty) const Text('(none)'),
                if (traceErrorMap.isNotEmpty)
                  ErrorBanner(
                    title: 'Run trace error',
                    message:
                        'message: ${traceErrorMap['message'] ?? ''}\nkind: ${traceErrorMap['kind'] ?? ''}\nnode_id: ${traceErrorMap['node_id'] ?? ''}',
                    copyText:
                        'title: Run trace error\nrun_id: ${widget.runItem.docId}\nrun_ver_id: ${widget.runItem.verId}\nmessage: ${traceErrorMap['message'] ?? ''}\nkind: ${traceErrorMap['kind'] ?? ''}\nnode_id: ${traceErrorMap['node_id'] ?? ''}',
                    copyJsonText: jsonEncode(traceErrorMap),
                  ),
                const SizedBox(height: 16),
                Text('Outputs', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (outputList.isEmpty) const Text('(none)'),
                ...outputList.map((outputRef) {
                  final artifactRefRaw = outputRef['artifact_ref'];
                  final artifactRef = artifactRefRaw is Map<String, dynamic>
                      ? artifactRefRaw
                      : outputRef;
                  final docId = artifactRef['doc_id'] as String? ?? '';
                  final verId = artifactRef['ver_id'] as String? ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('artifact: $docId @ $verId'),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: docId.isEmpty || verId.isEmpty
                                ? null
                                : () => _openOutputFile(docId, verId, context),
                            child: const Text('Request file preview'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (_outputPath != null) Text('output_path: $_outputPath'),
                if (_outputPreviewError != null)
                  ErrorBanner(
                    title: 'Output preview error',
                    message: _outputPreviewError!,
                    copyText:
                        'title: Output preview error\nrun_id: ${widget.runItem.docId}\nrun_ver_id: ${widget.runItem.verId}\nmessage: ${_outputPreviewError!}',
                  ),
                if (_outputPreview != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: SelectableText(_outputPreview!),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

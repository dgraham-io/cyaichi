import 'dart:convert';

import 'package:client/api/api_client.dart';
import 'package:client/src/flow/flow_document_builder.dart';
import 'package:client/src/io/local_file_reader.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

class FlowCanvasScreen extends StatefulWidget {
  const FlowCanvasScreen({super.key});

  @override
  State<FlowCanvasScreen> createState() => _FlowCanvasScreenState();
}

class _FlowCanvasScreenState extends State<FlowCanvasScreen> {
  static const _uuid = Uuid();

  static const _defaultServerBaseUrl = 'http://localhost:8080';
  static const _defaultWorkspaceDataRoot = './workspace-data';

  static const _prefServerBaseUrl = 'client.server_base_url';
  static const _prefWorkspaceDataRoot = 'client.workspace_data_root';
  static const _prefWorkspaceIds = 'client.workspace_ids';
  static const _prefSelectedWorkspaceId = 'client.selected_workspace_id';
  static const _prefAutoSetHeadOnSave = 'client.auto_set_head_on_save';

  late final NodeFlowController<Map<String, dynamic>, Map<String, dynamic>>
  _controller;
  final LocalFileReader _localFileReader = createLocalFileReader();

  late final TextEditingController _flowTitleController;
  late final TextEditingController _inputFileController;
  late final TextEditingController _outputFileController;

  late ApiClient _apiClient;

  String _serverBaseUrl = _defaultServerBaseUrl;
  String _workspaceDataRoot = _defaultWorkspaceDataRoot;
  bool _settingsLoaded = false;

  final List<String> _workspaceIds = <String>[];
  String? _selectedWorkspaceId;

  String? _selectedNodeId;
  int _nodeCounter = 1;

  bool _isCreatingWorkspace = false;
  bool _isSavingToServer = false;
  bool _isRunning = false;

  String _lastRunStatus = 'idle';
  String? _lastRunError;
  String? _lastRunId;
  String? _lastRunVerId;
  String? _lastOutputPath;
  String? _lastOutputContent;

  String? _currentFlowDocId;
  String? _currentFlowVerId;
  String? _currentFlowWorkspaceId;
  List<String> _currentFlowParents = const <String>[];
  bool _autoSetHeadOnSave = false;

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

  @override
  void initState() {
    super.initState();

    _controller =
        NodeFlowController<Map<String, dynamic>, Map<String, dynamic>>(
          config: NodeFlowConfig(scrollToZoom: false),
        );
    _flowTitleController = TextEditingController(text: 'My Flow');
    _inputFileController = TextEditingController(text: 'input.txt');
    _outputFileController = TextEditingController(text: 'output.txt');
    _apiClient = ApiClient(baseUrl: _serverBaseUrl);

    _loadSettings();
  }

  @override
  void dispose() {
    _controller.dispose();
    _flowTitleController.dispose();
    _inputFileController.dispose();
    _outputFileController.dispose();
    _apiClient.close();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedBaseUrl =
        prefs.getString(_prefServerBaseUrl) ?? _defaultServerBaseUrl;
    final loadedWorkspaceRoot =
        prefs.getString(_prefWorkspaceDataRoot) ?? _defaultWorkspaceDataRoot;
    final loadedWorkspaceIds =
        prefs.getStringList(_prefWorkspaceIds) ?? <String>[];
    final loadedSelectedWorkspace = prefs.getString(_prefSelectedWorkspaceId);
    final loadedAutoSetHead = prefs.getBool(_prefAutoSetHeadOnSave) ?? false;

    _apiClient.close();
    _apiClient = ApiClient(baseUrl: loadedBaseUrl);

    if (!mounted) {
      return;
    }

    setState(() {
      _serverBaseUrl = loadedBaseUrl;
      _workspaceDataRoot = loadedWorkspaceRoot;
      _workspaceIds
        ..clear()
        ..addAll(loadedWorkspaceIds);
      _selectedWorkspaceId =
          loadedWorkspaceIds.contains(loadedSelectedWorkspace)
          ? loadedSelectedWorkspace
          : null;
      _autoSetHeadOnSave = loadedAutoSetHead;
      _settingsLoaded = true;
    });

    await _refreshWorkspaceData();
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerBaseUrl, _serverBaseUrl);
    await prefs.setString(_prefWorkspaceDataRoot, _workspaceDataRoot);
    await prefs.setBool(_prefAutoSetHeadOnSave, _autoSetHeadOnSave);
    await prefs.setStringList(_prefWorkspaceIds, _workspaceIds);
    if (_selectedWorkspaceId == null) {
      await prefs.remove(_prefSelectedWorkspaceId);
    } else {
      await prefs.setString(_prefSelectedWorkspaceId, _selectedWorkspaceId!);
    }
  }

  Future<void> _onWorkspaceSelected(String? workspaceId) async {
    setState(() {
      _selectedWorkspaceId = workspaceId;
    });
    await _persistSettings();
    await _refreshWorkspaceData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('cyaichi flow client'),
        actions: [
          IconButton(
            tooltip: 'Workspaces',
            onPressed: _showWorkspaceDialog,
            icon: const Icon(Icons.workspaces),
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
        bottom: _selectedTabIndex == 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(74),
                child: _TopControlsBar(
                  settingsLoaded: _settingsLoaded,
                  workspaceIds: _workspaceIds,
                  selectedWorkspaceId: _selectedWorkspaceId,
                  flowTitleController: _flowTitleController,
                  isCreatingWorkspace: _isCreatingWorkspace,
                  isSavingToServer: _isSavingToServer,
                  isRunning: _isRunning,
                  onWorkspaceSelected: _onWorkspaceSelected,
                  onCreateWorkspace: _createWorkspace,
                  onSaveToServer: _saveNewFlowVersionToServer,
                  onSetHead: _setCurrentFlowAsHead,
                  onDuplicate: _duplicateCurrentFlow,
                  onRun: _runFlow,
                ),
              )
            : null,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) async {
          setState(() {
            _selectedTabIndex = index;
          });
          if (index == 1) {
            await _loadFlows();
          }
          if (index == 2) {
            await _loadRuns();
          }
          if (index == 3) {
            await _loadNotes();
          }
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.account_tree), label: 'Flow'),
          NavigationDestination(
            icon: Icon(Icons.library_books),
            label: 'Flows',
          ),
          NavigationDestination(icon: Icon(Icons.play_circle), label: 'Runs'),
          NavigationDestination(icon: Icon(Icons.note_alt), label: 'Notes'),
        ],
      ),
      floatingActionButton: _selectedTabIndex == 3
          ? FloatingActionButton.extended(
              onPressed: _showCreateNoteDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Note'),
            )
          : null,
    );
  }

  Widget _buildFlowTab() {
    final selectedNode = _selectedNodeId == null
        ? null
        : _controller.getNode(_selectedNodeId!);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvasTheme = isDark ? NodeFlowTheme.dark : NodeFlowTheme.light;

    return Row(
      children: [
        _PalettePanel(
          onAddFileRead: () => _addNode(NodeKind.fileRead),
          onAddLlmChat: () => _addNode(NodeKind.llmChat),
          onAddFileWrite: () => _addNode(NodeKind.fileWrite),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: canvasTheme.backgroundColor),
            child: NodeFlowEditor<Map<String, dynamic>, Map<String, dynamic>>(
              controller: _controller,
              theme: canvasTheme,
              nodeBuilder: _buildNodeCard,
              behavior: NodeFlowBehavior.design,
              events: NodeFlowEvents(
                node: NodeEvents(
                  onSelected: (node) {
                    setState(() {
                      _selectedNodeId = node?.id;
                    });
                  },
                ),
                onSelectionChange: (selection) {
                  if (selection.nodes.isEmpty && _selectedNodeId != null) {
                    setState(() {
                      _selectedNodeId = null;
                    });
                  }
                },
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 380,
          child: Column(
            children: [
              Expanded(
                child: _InspectorPanel(
                  selectedNode: selectedNode,
                  onTitleChanged: (value) =>
                      _updateNodeTitle(selectedNode, value),
                  onConfigChanged: (key, value) =>
                      _updateNodeConfig(selectedNode, key, value),
                ),
              ),
              const Divider(height: 1),
              _RunPanel(
                inputFileController: _inputFileController,
                outputFileController: _outputFileController,
                status: _lastRunStatus,
                runId: _lastRunId,
                runVerId: _lastRunVerId,
                error: _lastRunError,
                outputPath: _lastOutputPath,
                outputContent: _lastOutputContent,
                isRunning: _isRunning,
              ),
            ],
          ),
        ),
      ],
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
      return _ErrorState(message: _flowsError!, onRetry: _loadFlows);
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
      return _ErrorState(message: _runsError!, onRetry: _loadRuns);
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
      return _ErrorState(message: _notesError!, onRetry: _loadNotes);
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
    final title = (data['title'] as String?)?.trim();
    final visibleTitle = (title == null || title.isEmpty) ? node.type : title;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: node.isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: node.isSelected ? 2 : 1,
        ),
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
          const SizedBox(height: 6),
          Text(
            node.type,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Wrap(
            spacing: 8,
            runSpacing: 6,
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
                        labelText: 'Workspace data root',
                        hintText: './workspace-data',
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
      return;
    }

    final nextBaseUrl = baseUrlController.text.trim();
    final nextWorkspaceRoot = workspaceRootController.text.trim();
    baseUrlController.dispose();
    workspaceRootController.dispose();

    if (nextBaseUrl.isEmpty || Uri.tryParse(nextBaseUrl) == null) {
      _showSnack('Invalid server URL');
      return;
    }
    if (nextWorkspaceRoot.isEmpty) {
      _showSnack('Workspace data root cannot be empty');
      return;
    }

    setState(() {
      _serverBaseUrl = nextBaseUrl;
      _workspaceDataRoot = nextWorkspaceRoot;
      _autoSetHeadOnSave = autoSetHeadOnSave;
    });
    _apiClient.close();
    _apiClient = ApiClient(baseUrl: _serverBaseUrl);
    await _persistSettings();
    await _refreshWorkspaceData();
    _showSnack('Settings saved');
  }

  Future<void> _showWorkspaceDialog() async {
    String? selected = _selectedWorkspaceId;
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Workspaces'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_workspaceIds.isEmpty)
                      const Text('No workspaces saved in client settings yet.'),
                    if (_workspaceIds.isNotEmpty)
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _workspaceIds.length,
                          itemBuilder: (context, index) {
                            final workspaceId = _workspaceIds[index];
                            return RadioListTile<String>(
                              dense: true,
                              title: Text(workspaceId),
                              value: workspaceId,
                              groupValue: selected,
                              onChanged: (value) {
                                setDialogState(() {
                                  selected = value;
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _createWorkspace();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New Workspace'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await _onWorkspaceSelected(result);
    }
  }

  Future<void> _refreshWorkspaceData() async {
    await _loadFlows();
    await _loadRuns();
    await _loadNotes();
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

  Future<void> _createWorkspace() async {
    if (_isCreatingWorkspace) {
      return;
    }

    setState(() {
      _isCreatingWorkspace = true;
    });

    try {
      final created = await _apiClient.createWorkspace(
        name: 'Client Workspace ${DateTime.now().toIso8601String()}',
      );
      setState(() {
        if (!_workspaceIds.contains(created.workspaceId)) {
          _workspaceIds.add(created.workspaceId);
        }
        _selectedWorkspaceId = created.workspaceId;
      });
      await _persistSettings();
      await _refreshWorkspaceData();
      _showSnack('Workspace created: ${_shortId(created.workspaceId)}');
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingWorkspace = false;
        });
      }
    }
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
      });
      await _loadFlows();
      _showSnack(
        _autoSetHeadOnSave
            ? 'Saved new version and set head (${_shortId(flowDocId)} @ ${_shortId(flowVerId)})'
            : 'Saved new version (${_shortId(flowDocId)} @ ${_shortId(flowVerId)})',
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
      });
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

    final workspaceId = _selectedWorkspaceId;
    if (workspaceId == null) {
      _showSnack('Select or create a workspace first.');
      return;
    }

    final inputFile = _inputFileController.text.trim().isEmpty
        ? 'input.txt'
        : _inputFileController.text.trim();
    final outputFile = _outputFileController.text.trim().isEmpty
        ? 'output.txt'
        : _outputFileController.text.trim();

    setState(() {
      _isRunning = true;
      _lastRunStatus = 'running';
      _lastRunError = null;
      _lastRunId = null;
      _lastRunVerId = null;
      _lastOutputPath = null;
      _lastOutputContent = null;
    });

    final saved = await _saveNewFlowVersionToServer();
    if (!saved || _currentFlowDocId == null || _currentFlowVerId == null) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _lastRunStatus = 'failed';
          _lastRunError = 'Flow save failed; run aborted.';
        });
      }
      return;
    }

    try {
      await _apiClient.setHead(
        workspaceId: workspaceId,
        docId: _currentFlowDocId!,
        verId: _currentFlowVerId!,
      );
      final run = await _apiClient.createRun(
        workspaceId: workspaceId,
        flowDocId: _currentFlowDocId!,
        inputFile: inputFile,
        outputFile: outputFile,
      );

      final runDoc = await _apiClient.getDocument(
        docType: 'run',
        docId: run.runId,
        verId: run.runVerId,
      );
      final runBody = runDoc['body'] as Map<String, dynamic>?;
      final status = runBody?['status'] as String? ?? 'succeeded';
      final traceError = _traceErrorMessage(runBody);

      final outputPath = _joinPath(_workspaceDataRoot, workspaceId, outputFile);

      String? outputContent;
      String? runError = traceError;
      if (status == 'succeeded') {
        try {
          outputContent = await _localFileReader.readText(outputPath);
        } catch (error) {
          runError = 'Run succeeded, but failed to read output file: $error';
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
        _lastOutputPath = outputPath;
        _lastOutputContent = outputContent;
      });
    } on ApiError catch (error) {
      String status = 'failed';
      String? runId;
      String? runVerId;
      String? traceError;

      final body = error.responseBody;
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
          final runBody = runDoc['body'] as Map<String, dynamic>?;
          status = runBody?['status'] as String? ?? status;
          traceError = _traceErrorMessage(runBody);
        } on ApiError {
          traceError = null;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _lastRunStatus = status;
        _lastRunId = runId;
        _lastRunVerId = runVerId;
        _lastRunError = traceError ?? _formatApiError(error);
      });
      _showSnack(_formatApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
      await _loadRuns();
    }
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
          localFileReader: _localFileReader,
          workspaceId: workspaceId,
          workspaceDataRoot: _workspaceDataRoot,
          runItem: item,
          pathJoin: _joinPath,
          friendlyDate: _friendlyDate,
        ),
      ),
    );
  }

  Future<void> _openFlowFromLibrary(FlowListItem flow) async {
    try {
      final document = await _apiClient.getDocument(
        docType: 'flow',
        docId: flow.docId,
        verId: flow.verId,
      );
      _importFlowDocumentMap(document);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedTabIndex = 0;
      });
      _showSnack(
        'Loaded flow ${_shortId(flow.docId)} @ ${_shortId(flow.verId)}',
      );
    } on ApiError catch (error) {
      _showSnack(_formatApiError(error));
    } on FormatException catch (error) {
      _showSnack('Invalid flow document: ${error.message}');
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

  String? _traceErrorMessage(Map<String, dynamic>? runBody) {
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
    return message is String && message.trim().isNotEmpty ? message : null;
  }

  String _formatApiError(ApiError error) {
    if (error.isNetwork) {
      return 'server not reachable: ${error.message}';
    }
    if (error.statusCode != null) {
      return 'HTTP ${error.statusCode}: ${error.message}';
    }
    return error.message;
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
    _importFlowDocumentMap(decoded);
  }

  void _importFlowDocumentMap(Map<String, dynamic> decoded) {
    final parsed = parseFlowDocumentEnvelope(decoded);

    if (!_workspaceIds.contains(parsed.workspaceId)) {
      _workspaceIds.add(parsed.workspaceId);
    }
    _selectedWorkspaceId = parsed.workspaceId;
    _persistSettings();
    _refreshWorkspaceData();

    if (parsed.title.trim().isNotEmpty) {
      _flowTitleController.text = parsed.title;
    }

    _controller.clearGraph();

    final knownNodeIds = <String>{};
    for (final item in parsed.nodes) {
      final rawConfig = Map<String, dynamic>.from(item.config);
      final ui = rawConfig['_ui'];
      final uiMap = ui is Map<String, dynamic> ? ui : <String, dynamic>{};

      final position = Offset(
        (uiMap['x'] as num?)?.toDouble() ?? 120,
        (uiMap['y'] as num?)?.toDouble() ?? 120,
      );
      final size = Size(
        (uiMap['width'] as num?)?.toDouble() ?? 220,
        (uiMap['height'] as num?)?.toDouble() ?? 132,
      );

      final ports = <Port>[
        ..._buildPorts(item.inputs, PortPosition.left),
        ..._buildPorts(item.outputs, PortPosition.right),
      ];

      final node = Node<Map<String, dynamic>>(
        id: item.id,
        type: item.type,
        position: position,
        size: size,
        ports: ports,
        data: <String, dynamic>{
          'title': item.title,
          'config': rawConfig..remove('_ui'),
          'inputs': item.inputs.map((port) => port.toJson()).toList(),
          'outputs': item.outputs.map((port) => port.toJson()).toList(),
        },
      );
      _controller.addNode(node);
      knownNodeIds.add(item.id);
    }

    for (final edge in parsed.edges) {
      if (!knownNodeIds.contains(edge.sourceNode) ||
          !knownNodeIds.contains(edge.targetNode)) {
        continue;
      }
      _controller.addConnection(
        Connection<Map<String, dynamic>>(
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
    });
  }

  void _addNode(NodeKind kind) {
    final spec = kind.spec;
    final nodeId = _uuid.v4();
    final title = '${spec.label} $_nodeCounter';
    final position = Offset(
      120 + ((_nodeCounter - 1) % 4) * 70,
      100 + ((_nodeCounter - 1) ~/ 4) * 70,
    );
    _nodeCounter += 1;

    final ports = <Port>[
      ..._buildPorts(spec.inputs, PortPosition.left),
      ..._buildPorts(spec.outputs, PortPosition.right),
    ];

    final node = Node<Map<String, dynamic>>(
      id: nodeId,
      type: spec.type,
      position: position,
      size: const Size(220, 132),
      ports: ports,
      data: <String, dynamic>{
        'title': title,
        'config': Map<String, dynamic>.from(spec.defaultConfig),
        'inputs': spec.inputs.map((port) => port.toJson()).toList(),
        'outputs': spec.outputs.map((port) => port.toJson()).toList(),
      },
    );

    setState(() {
      _controller.addNode(node);
      _controller.selectNode(nodeId);
      _selectedNodeId = nodeId;
    });
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
  }

  void _updateNodeConfig(
    Node<Map<String, dynamic>>? node,
    String key,
    String value,
  ) {
    if (node == null) {
      return;
    }

    setState(() {
      final config = _readConfig(node.data);
      if (value.trim().isEmpty) {
        config.remove(key);
      } else {
        config[key] = value;
      }
      node.data['config'] = config;
    });
  }

  (List<FlowNodeSnapshot>, List<FlowEdgeSnapshot>)
  _collectCanvasFlowSnapshot() {
    final nodes = _controller.nodes.values
        .map((node) {
          final config = _readConfig(node.data)
            ..['_ui'] = <String, dynamic>{
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
            inputs: _readFlowPorts(node.data['inputs']),
            outputs: _readFlowPorts(node.data['outputs']),
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
}

class _TopControlsBar extends StatelessWidget {
  const _TopControlsBar({
    required this.settingsLoaded,
    required this.workspaceIds,
    required this.selectedWorkspaceId,
    required this.flowTitleController,
    required this.isCreatingWorkspace,
    required this.isSavingToServer,
    required this.isRunning,
    required this.onWorkspaceSelected,
    required this.onCreateWorkspace,
    required this.onSaveToServer,
    required this.onSetHead,
    required this.onDuplicate,
    required this.onRun,
  });

  final bool settingsLoaded;
  final List<String> workspaceIds;
  final String? selectedWorkspaceId;
  final TextEditingController flowTitleController;
  final bool isCreatingWorkspace;
  final bool isSavingToServer;
  final bool isRunning;
  final Future<void> Function(String?) onWorkspaceSelected;
  final Future<void> Function() onCreateWorkspace;
  final Future<bool> Function() onSaveToServer;
  final Future<void> Function() onSetHead;
  final Future<void> Function() onDuplicate;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 260,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Workspace',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: settingsLoaded
                    ? DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedWorkspaceId,
                          hint: const Text('Select workspace'),
                          items: workspaceIds
                              .map(
                                (id) => DropdownMenuItem<String>(
                                  value: id,
                                  child: Text(id),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            onWorkspaceSelected(value);
                          },
                        ),
                      )
                    : const Text('Loading...'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isCreatingWorkspace ? null : onCreateWorkspace,
              icon: isCreatingWorkspace
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('New Workspace'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 240,
              child: TextField(
                controller: flowTitleController,
                decoration: const InputDecoration(
                  labelText: 'Flow title',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: isSavingToServer ? null : onSaveToServer,
              icon: isSavingToServer
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Save New Version'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isSavingToServer ? null : onDuplicate,
              icon: const Icon(Icons.copy_all),
              label: const Text('Duplicate'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isSavingToServer ? null : onSetHead,
              icon: const Icon(Icons.push_pin),
              label: const Text('Set Head'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isRunning ? null : onRun,
              icon: isRunning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Run'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PalettePanel extends StatelessWidget {
  const _PalettePanel({
    required this.onAddFileRead,
    required this.onAddLlmChat,
    required this.onAddFileWrite,
  });

  final VoidCallback onAddFileRead;
  final VoidCallback onAddLlmChat;
  final VoidCallback onAddFileWrite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nodes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('add-file.read'),
              onPressed: onAddFileRead,
              icon: const Icon(Icons.file_open),
              label: const Text('Add file.read'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('add-llm.chat'),
              onPressed: onAddLlmChat,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Add llm.chat'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('add-file.write'),
              onPressed: onAddFileWrite,
              icon: const Icon(Icons.save),
              label: const Text('Add file.write'),
            ),
            const SizedBox(height: 24),
            Text(
              'Drag between ports to create edges. Click a node to edit fields.',
              style: Theme.of(context).textTheme.bodySmall,
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
    required this.onTitleChanged,
    required this.onConfigChanged,
  });

  final Node<Map<String, dynamic>>? selectedNode;
  final ValueChanged<String> onTitleChanged;
  final void Function(String key, String value) onConfigChanged;

  @override
  Widget build(BuildContext context) {
    if (selectedNode == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Inspector\n\nSelect a node on the canvas.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final node = selectedNode!;
    final title = (node.data['title'] as String?) ?? '';
    final config = _readConfigStatic(node.data);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(node.type, style: Theme.of(context).textTheme.bodySmall),
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
          if (node.type == 'file.read')
            TextFormField(
              key: Key('input-file-field-${node.id}'),
              initialValue: (config['input_file'] as String?) ?? '',
              decoration: const InputDecoration(
                labelText: 'input_file',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => onConfigChanged('input_file', value),
            ),
          if (node.type == 'file.write')
            TextFormField(
              key: Key('output-file-field-${node.id}'),
              initialValue: (config['output_file'] as String?) ?? '',
              decoration: const InputDecoration(
                labelText: 'output_file',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => onConfigChanged('output_file', value),
            ),
          if (node.type == 'llm.chat')
            TextFormField(
              key: Key('model-field-${node.id}'),
              initialValue: (config['model'] as String?) ?? '',
              decoration: const InputDecoration(
                labelText: 'model override (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => onConfigChanged('model', value),
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
    required this.status,
    required this.runId,
    required this.runVerId,
    required this.error,
    required this.outputPath,
    required this.outputContent,
    required this.isRunning,
  });

  final TextEditingController inputFileController;
  final TextEditingController outputFileController;
  final String status;
  final String? runId;
  final String? runVerId;
  final String? error;
  final String? outputPath;
  final String? outputContent;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Run Panel',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _RunStatusChip(status: status, isRunning: isRunning),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: inputFileController,
              decoration: const InputDecoration(
                labelText: 'input_file',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: outputFileController,
              decoration: const InputDecoration(
                labelText: 'output_file',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (runId != null) Text('run_id: $runId'),
            if (runVerId != null) Text('run_ver_id: $runVerId'),
            if (outputPath != null) Text('output_path: $outputPath'),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      case 'running':
        color = Colors.orange;
        break;
      default:
        color = Theme.of(context).colorScheme.outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
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
  const _ErrorState({required this.message, required this.onRetry});

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
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _RunDetailsScreen extends StatefulWidget {
  const _RunDetailsScreen({
    required this.apiClient,
    required this.localFileReader,
    required this.workspaceId,
    required this.workspaceDataRoot,
    required this.runItem,
    required this.pathJoin,
    required this.friendlyDate,
  });

  final ApiClient apiClient;
  final LocalFileReader localFileReader;
  final String workspaceId;
  final String workspaceDataRoot;
  final RunListItem runItem;
  final String Function(String first, String second, String third) pathJoin;
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
      final artifact = await widget.apiClient.getDocument(
        docType: 'artifact',
        docId: outputDocId,
        verId: outputVerId,
      );
      final body = artifact['body'];
      if (body is! Map<String, dynamic>) {
        throw const FormatException('artifact body missing');
      }
      final payload = body['payload'];
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('artifact payload missing');
      }
      final path = payload['path'];
      if (path is! String || path.trim().isEmpty) {
        throw const FormatException('artifact payload.path missing');
      }

      final fullPath = widget.pathJoin(
        widget.workspaceDataRoot,
        widget.workspaceId,
        path,
      );
      final contents = await widget.localFileReader.readText(fullPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _outputPath = fullPath;
        _outputPreview = contents.length > 2000
            ? '${contents.substring(0, 2000)}...'
            : contents;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _outputPreviewError = error.message;
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
          ? _ErrorState(message: _error!, onRetry: _load)
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
                  Text(
                    'message: ${traceErrorMap['message'] ?? ''}\nkind: ${traceErrorMap['kind'] ?? ''}\nnode_id: ${traceErrorMap['node_id'] ?? ''}',
                  ),
                const SizedBox(height: 16),
                Text('Outputs', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (outputList.isEmpty) const Text('(none)'),
                ...outputList.map((outputRef) {
                  final docId = outputRef['doc_id'] as String? ?? '';
                  final verId = outputRef['ver_id'] as String? ?? '';
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
                            child: const Text('Open output file'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (_outputPath != null) Text('output_path: $_outputPath'),
                if (_outputPreviewError != null)
                  Text(
                    _outputPreviewError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

enum NodeKind { fileRead, llmChat, fileWrite }

extension on NodeKind {
  NodeSpec get spec {
    switch (this) {
      case NodeKind.fileRead:
        return const NodeSpec(
          type: 'file.read',
          label: 'File Read',
          inputs: <FlowPort>[],
          outputs: <FlowPort>[FlowPort(port: 'out', schema: 'artifact/text')],
          defaultConfig: <String, dynamic>{'input_file': 'input.txt'},
        );
      case NodeKind.llmChat:
        return const NodeSpec(
          type: 'llm.chat',
          label: 'LLM Chat',
          inputs: <FlowPort>[FlowPort(port: 'in', schema: 'artifact/text')],
          outputs: <FlowPort>[FlowPort(port: 'out', schema: 'artifact/text')],
          defaultConfig: <String, dynamic>{'model': ''},
        );
      case NodeKind.fileWrite:
        return const NodeSpec(
          type: 'file.write',
          label: 'File Write',
          inputs: <FlowPort>[FlowPort(port: 'in', schema: 'artifact/text')],
          outputs: <FlowPort>[
            FlowPort(port: 'out', schema: 'artifact/output_file'),
          ],
          defaultConfig: <String, dynamic>{'output_file': 'output.txt'},
        );
    }
  }
}

class NodeSpec {
  const NodeSpec({
    required this.type,
    required this.label,
    required this.inputs,
    required this.outputs,
    required this.defaultConfig,
  });

  final String type;
  final String label;
  final List<FlowPort> inputs;
  final List<FlowPort> outputs;
  final Map<String, dynamic> defaultConfig;
}

import 'dart:convert';

import 'package:client/api/api_client.dart';
import 'package:client/src/flow/flow_document_builder.dart';
import 'package:client/src/io/local_file_reader.dart';
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

  String? _lastSavedFlowDocId;
  String? _lastSavedFlowVerId;

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
      _settingsLoaded = true;
    });
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerBaseUrl, _serverBaseUrl);
    await prefs.setString(_prefWorkspaceDataRoot, _workspaceDataRoot);
    await prefs.setStringList(_prefWorkspaceIds, _workspaceIds);
    if (_selectedWorkspaceId == null) {
      await prefs.remove(_prefSelectedWorkspaceId);
    } else {
      await prefs.setString(_prefSelectedWorkspaceId, _selectedWorkspaceId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedNode = _selectedNodeId == null
        ? null
        : _controller.getNode(_selectedNodeId!);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvasTheme = isDark ? NodeFlowTheme.dark : NodeFlowTheme.light;

    return Scaffold(
      appBar: AppBar(
        title: const Text('cyaichi flow client'),
        actions: [
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
          IconButton(
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: _TopControlsBar(
            settingsLoaded: _settingsLoaded,
            workspaceIds: _workspaceIds,
            selectedWorkspaceId: _selectedWorkspaceId,
            flowTitleController: _flowTitleController,
            isCreatingWorkspace: _isCreatingWorkspace,
            isSavingToServer: _isSavingToServer,
            isRunning: _isRunning,
            onWorkspaceSelected: (value) {
              setState(() {
                _selectedWorkspaceId = value;
              });
              _persistSettings();
            },
            onCreateWorkspace: _createWorkspace,
            onSaveToServer: _saveFlowToServer,
            onRun: _runFlow,
          ),
        ),
      ),
      body: Row(
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

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
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
    });
    _apiClient.close();
    _apiClient = ApiClient(baseUrl: _serverBaseUrl);
    await _persistSettings();
    _showSnack('Settings saved');
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

  Future<bool> _saveFlowToServer() async {
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

    final flowDocId = _uuid.v4();
    final flowVerId = _uuid.v4();

    final nodes = _controller.nodes.values.map((node) {
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
    }).toList();

    final edges = _controller.connections.map((connection) {
      return FlowEdgeSnapshot(
        sourceNode: connection.sourceNodeId,
        sourcePort: connection.sourcePortId,
        targetNode: connection.targetNodeId,
        targetPort: connection.targetPortId,
      );
    }).toList();

    final document = buildFlowDocumentEnvelope(
      workspaceId: workspaceId,
      docId: flowDocId,
      verId: flowVerId,
      createdAt: DateTime.now().toUtc(),
      title: _flowTitleController.text,
      nodes: nodes,
      edges: edges,
    );

    try {
      await _apiClient.putFlowDocument(
        docId: flowDocId,
        verId: flowVerId,
        document: document,
      );
      await _apiClient.setHead(
        workspaceId: workspaceId,
        docId: flowDocId,
        verId: flowVerId,
      );

      setState(() {
        _lastSavedFlowDocId = flowDocId;
        _lastSavedFlowVerId = flowVerId;
      });
      _showSnack('Flow saved and set as head (${_shortId(flowDocId)})');
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

    final saved = await _saveFlowToServer();
    if (!saved || _lastSavedFlowDocId == null) {
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
      final run = await _apiClient.createRun(
        workspaceId: workspaceId,
        flowDocId: _lastSavedFlowDocId!,
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
    }
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
    final docId = _uuid.v4();
    final verId = _uuid.v4();

    final nodes = _controller.nodes.values.map((node) {
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
        title: (node.data['title'] as String?) ?? node.type,
        inputs: _readFlowPorts(node.data['inputs']),
        outputs: _readFlowPorts(node.data['outputs']),
        config: config,
      );
    }).toList();

    final edges = _controller.connections
        .map(
          (connection) => FlowEdgeSnapshot(
            sourceNode: connection.sourceNodeId,
            sourcePort: connection.sourcePortId,
            targetNode: connection.targetNodeId,
            targetPort: connection.targetPortId,
          ),
        )
        .toList();

    final exported = buildFlowDocumentEnvelope(
      workspaceId: workspaceId,
      docId: docId,
      verId: verId,
      createdAt: DateTime.now().toUtc(),
      title: _flowTitleController.text,
      nodes: nodes,
      edges: edges,
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

    final body = decoded['body'];
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Missing body object.');
    }

    final nodesJson = body['nodes'];
    final edgesJson = body['edges'];
    if (nodesJson is! List) {
      throw const FormatException('body.nodes must be an array.');
    }
    if (edgesJson is! List) {
      throw const FormatException('body.edges must be an array.');
    }

    final importedWorkspaceId = decoded['workspace_id'];
    if (importedWorkspaceId is String &&
        importedWorkspaceId.trim().isNotEmpty) {
      if (!_workspaceIds.contains(importedWorkspaceId)) {
        _workspaceIds.add(importedWorkspaceId);
      }
      _selectedWorkspaceId = importedWorkspaceId;
      _persistSettings();
    }

    final meta = decoded['meta'];
    if (meta is Map<String, dynamic>) {
      final title = meta['title'];
      if (title is String && title.trim().isNotEmpty) {
        _flowTitleController.text = title;
      }
    }

    _controller.clearGraph();

    final knownNodeIds = <String>{};
    for (final item in nodesJson) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final nodeId = item['id'] as String?;
      final nodeType = item['type'] as String?;
      if (nodeId == null || nodeType == null) {
        continue;
      }

      final rawConfig = item['config'];
      final config = rawConfig is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawConfig)
          : <String, dynamic>{};
      final ui = config['_ui'];
      final uiMap = ui is Map<String, dynamic> ? ui : <String, dynamic>{};

      final position = Offset(
        (uiMap['x'] as num?)?.toDouble() ?? 120,
        (uiMap['y'] as num?)?.toDouble() ?? 120,
      );
      final size = Size(
        (uiMap['width'] as num?)?.toDouble() ?? 220,
        (uiMap['height'] as num?)?.toDouble() ?? 132,
      );

      final inputs = _readFlowPorts(item['inputs']);
      final outputs = _readFlowPorts(item['outputs']);

      final ports = <Port>[
        ..._buildPorts(inputs, PortPosition.left),
        ..._buildPorts(outputs, PortPosition.right),
      ];

      final node = Node<Map<String, dynamic>>(
        id: nodeId,
        type: nodeType,
        position: position,
        size: size,
        ports: ports,
        data: <String, dynamic>{
          'title': (item['title'] as String?) ?? nodeType,
          'config': config..remove('_ui'),
          'inputs': inputs.map((port) => port.toJson()).toList(),
          'outputs': outputs.map((port) => port.toJson()).toList(),
        },
      );
      _controller.addNode(node);
      knownNodeIds.add(nodeId);
    }

    for (final edge in edgesJson) {
      if (edge is! Map<String, dynamic>) {
        continue;
      }
      final from = edge['from'];
      final to = edge['to'];
      if (from is! Map<String, dynamic> || to is! Map<String, dynamic>) {
        continue;
      }

      final sourceNodeId = from['node'] as String?;
      final sourcePortId = from['port'] as String?;
      final targetNodeId = to['node'] as String?;
      final targetPortId = to['port'] as String?;

      if (sourceNodeId == null ||
          sourcePortId == null ||
          targetNodeId == null ||
          targetPortId == null) {
        continue;
      }
      if (!knownNodeIds.contains(sourceNodeId) ||
          !knownNodeIds.contains(targetNodeId)) {
        continue;
      }

      _controller.addConnection(
        Connection<Map<String, dynamic>>(
          id: _uuid.v4(),
          sourceNodeId: sourceNodeId,
          sourcePortId: sourcePortId,
          targetNodeId: targetNodeId,
          targetPortId: targetPortId,
        ),
      );
    }

    setState(() {
      _selectedNodeId = null;
      _lastExportJson = const JsonEncoder.withIndent('  ').convert(decoded);
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
    required this.onRun,
  });

  final bool settingsLoaded;
  final List<String> workspaceIds;
  final String? selectedWorkspaceId;
  final TextEditingController flowTitleController;
  final bool isCreatingWorkspace;
  final bool isSavingToServer;
  final bool isRunning;
  final ValueChanged<String?> onWorkspaceSelected;
  final Future<void> Function() onCreateWorkspace;
  final Future<bool> Function() onSaveToServer;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                        onChanged: onWorkspaceSelected,
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
          const Spacer(),
          FilledButton.icon(
            onPressed: isSavingToServer ? null : onSaveToServer,
            icon: isSavingToServer
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: const Text('Save to Server'),
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

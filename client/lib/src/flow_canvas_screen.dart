import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

class FlowCanvasScreen extends StatefulWidget {
  const FlowCanvasScreen({super.key});

  @override
  State<FlowCanvasScreen> createState() => _FlowCanvasScreenState();
}

class _FlowCanvasScreenState extends State<FlowCanvasScreen> {
  static const _uuid = Uuid();

  late final NodeFlowController<Map<String, dynamic>, Map<String, dynamic>>
  _controller;
  late String _workspaceId;
  String _lastExportJson = '';
  String? _selectedNodeId;
  int _nodeCounter = 1;

  @override
  void initState() {
    super.initState();
    _workspaceId = _uuid.v4();
    _controller =
        NodeFlowController<Map<String, dynamic>, Map<String, dynamic>>(
          config: NodeFlowConfig(scrollToZoom: false),
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        title: const Text('cyaichi node canvas spike'),
        actions: [
          TextButton.icon(
            onPressed: _onExportJson,
            icon: const Icon(Icons.upload_file),
            label: const Text('Export JSON'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _onImportJson,
            icon: const Icon(Icons.download),
            label: const Text('Import JSON'),
          ),
          const SizedBox(width: 12),
        ],
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
                    onSelected: (node) => setState(() {
                      _selectedNodeId = node?.id;
                    }),
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
            width: 340,
            child: _InspectorPanel(
              selectedNode: selectedNode,
              onTitleChanged: (value) => _updateNodeTitle(selectedNode, value),
              onConfigChanged: (key, value) =>
                  _updateNodeConfig(selectedNode, key, value),
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
                label: 'in ${_readPortDefs(data['inputs']).length}',
                color: Theme.of(context).colorScheme.secondaryContainer,
              ),
              _Pill(
                label: 'out ${_readPortDefs(data['outputs']).length}',
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
            ],
          ),
        ],
      ),
    );
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

    final inputs = spec.inputs.map((p) => p.toJson()).toList();
    final outputs = spec.outputs.map((p) => p.toJson()).toList();

    final ports = [
      ..._buildPorts(spec.inputs, PortPosition.left),
      ..._buildPorts(spec.outputs, PortPosition.right),
    ];

    final node = Node<Map<String, dynamic>>(
      id: nodeId,
      type: spec.type,
      position: position,
      size: const Size(220, 132),
      ports: ports,
      data: {
        'title': title,
        'config': Map<String, dynamic>.from(spec.defaultConfig),
        'inputs': inputs,
        'outputs': outputs,
      },
    );

    setState(() {
      _controller.addNode(node);
      _controller.selectNode(nodeId);
      _selectedNodeId = nodeId;
    });
  }

  List<Port> _buildPorts(List<PortDef> defs, PortPosition side) {
    if (defs.isEmpty) {
      return const [];
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

  Future<void> _onExportJson() async {
    final exported = _buildFlowDocumentJson();
    final prettyJson = const JsonEncoder.withIndent('  ').convert(exported);
    setState(() {
      _lastExportJson = prettyJson;
    });
    debugPrint(prettyJson);

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Flow imported')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  Map<String, dynamic> _buildFlowDocumentJson() {
    final now = DateTime.now().toUtc().toIso8601String();
    final flowDocId = _uuid.v4();
    final flowVerId = _uuid.v4();

    final nodes = _controller.nodes.values.map((node) {
      final config = _readConfig(node.data);
      config['_ui'] = <String, dynamic>{
        'x': node.position.value.dx,
        'y': node.position.value.dy,
        'width': node.size.value.width,
        'height': node.size.value.height,
      };
      return <String, dynamic>{
        'id': node.id,
        'type': node.type,
        'title': node.data['title'] ?? node.type,
        'inputs': _readPortDefs(
          node.data['inputs'],
        ).map((port) => port.toJson()).toList(),
        'outputs': _readPortDefs(
          node.data['outputs'],
        ).map((port) => port.toJson()).toList(),
        'config': config,
      };
    }).toList();

    final edges = _controller.connections.map((connection) {
      return <String, dynamic>{
        'from': <String, dynamic>{
          'node': connection.sourceNodeId,
          'port': connection.sourcePortId,
        },
        'to': <String, dynamic>{
          'node': connection.targetNodeId,
          'port': connection.targetPortId,
        },
      };
    }).toList();

    return <String, dynamic>{
      'doc_type': 'flow',
      'doc_id': flowDocId,
      'ver_id': flowVerId,
      'workspace_id': _workspaceId,
      'created_at': now,
      'body': <String, dynamic>{
        'nodes': nodes,
        'edges': edges,
        'subflows': const [],
      },
    };
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

      final inputs = _readPortDefs(item['inputs']);
      final outputs = _readPortDefs(item['outputs']);

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
          'inputs': inputs.map((p) => p.toJson()).toList(),
          'outputs': outputs.map((p) => p.toJson()).toList(),
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
}

enum NodeKind { fileRead, llmChat, fileWrite }

extension on NodeKind {
  NodeSpec get spec {
    switch (this) {
      case NodeKind.fileRead:
        return const NodeSpec(
          type: 'file.read',
          label: 'File Read',
          inputs: [],
          outputs: [PortDef(port: 'out', schema: 'artifact/text')],
          defaultConfig: {'input_file': 'input.txt'},
        );
      case NodeKind.llmChat:
        return const NodeSpec(
          type: 'llm.chat',
          label: 'LLM Chat',
          inputs: [PortDef(port: 'in', schema: 'artifact/text')],
          outputs: [PortDef(port: 'out', schema: 'artifact/text')],
          defaultConfig: {'model': ''},
        );
      case NodeKind.fileWrite:
        return const NodeSpec(
          type: 'file.write',
          label: 'File Write',
          inputs: [PortDef(port: 'in', schema: 'artifact/text')],
          outputs: [PortDef(port: 'out', schema: 'artifact/output_file')],
          defaultConfig: {'output_file': 'output.txt'},
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
  final List<PortDef> inputs;
  final List<PortDef> outputs;
  final Map<String, dynamic> defaultConfig;
}

class PortDef {
  const PortDef({required this.port, required this.schema});

  final String port;
  final String schema;

  Map<String, dynamic> toJson() => {'port': port, 'schema': schema};
}

List<PortDef> _readPortDefs(Object? value) {
  if (value is! List) {
    return const [];
  }
  final result = <PortDef>[];
  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final port = item['port'] as String?;
    final schema = item['schema'] as String?;
    if (port == null || schema == null) {
      continue;
    }
    result.add(PortDef(port: port, schema: schema));
  }
  return result;
}

Map<String, dynamic> _readConfig(Map<String, dynamic> data) {
  final config = data['config'];
  if (config is Map<String, dynamic>) {
    return Map<String, dynamic>.from(config);
  }
  return <String, dynamic>{};
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
    final config = _readConfig(node.data);

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

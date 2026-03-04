import 'package:client/src/flow/flow_document_builder.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';

enum NodeInspectorFieldKind { string, boolType }

enum NodeTypeRegistrySource { server, cached, fallback }

class NodePortDefinition {
  const NodePortDefinition({required this.name, this.schema});

  final String name;
  final String? schema;

  FlowPort toFlowPort() => FlowPort(port: name, schema: schema ?? '');
}

class NodeInspectorFieldDefinition {
  const NodeInspectorFieldDefinition({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.optionalHint = false,
    this.multiline = false,
  });

  final String key;
  final String label;
  final NodeInspectorFieldKind kind;
  final bool required;
  final bool optionalHint;
  final bool multiline;
}

class NodeTypeDefinition {
  const NodeTypeDefinition({
    required this.typeId,
    required this.displayName,
    required this.category,
    required this.icon,
    required this.inputs,
    required this.outputs,
    required this.inspectorFields,
    required this.defaultConfig,
  });

  final String typeId;
  final String displayName;
  final String category;
  final IconData icon;
  final List<NodePortDefinition> inputs;
  final List<NodePortDefinition> outputs;
  final List<NodeInspectorFieldDefinition> inspectorFields;
  final Map<String, dynamic> defaultConfig;

  factory NodeTypeDefinition.fromServer(NodeTypeDef def) {
    final fields = def.configSchema
        .map((field) {
          final kind = field.kind == 'bool'
              ? NodeInspectorFieldKind.boolType
              : NodeInspectorFieldKind.string;
          return NodeInspectorFieldDefinition(
            key: field.key,
            label: field.label,
            kind: kind,
            required: field.required,
            optionalHint: !field.required,
            multiline: field.key == 'system_prompt',
          );
        })
        .toList(growable: false);

    final defaults = <String, dynamic>{};
    for (final field in fields) {
      switch (field.kind) {
        case NodeInspectorFieldKind.string:
          defaults[field.key] = '';
          break;
        case NodeInspectorFieldKind.boolType:
          defaults[field.key] = false;
          break;
      }
    }

    return NodeTypeDefinition(
      typeId: def.type,
      displayName: def.displayName,
      category: def.category,
      icon: _iconFor(def.type, def.category),
      inputs: def.inputs
          .map(
            (port) => NodePortDefinition(name: port.port, schema: port.schema),
          )
          .toList(growable: false),
      outputs: def.outputs
          .map(
            (port) => NodePortDefinition(name: port.port, schema: port.schema),
          )
          .toList(growable: false),
      inspectorFields: fields,
      defaultConfig: defaults,
    );
  }
}

class NodeTemplate {
  const NodeTemplate({
    required this.typeId,
    required this.displayName,
    required this.inputs,
    required this.outputs,
    required this.config,
  });

  final String typeId;
  final String displayName;
  final List<FlowPort> inputs;
  final List<FlowPort> outputs;
  final Map<String, dynamic> config;
}

class NodeTypeRegistry {
  const NodeTypeRegistry({
    required this.all,
    required this.source,
    required this.rawServerDefs,
  });

  final List<NodeTypeDefinition> all;
  final NodeTypeRegistrySource source;
  final List<NodeTypeDef> rawServerDefs;

  static const List<NodeTypeDefinition> fallbackDefinitions =
      <NodeTypeDefinition>[
        NodeTypeDefinition(
          typeId: 'file.read',
          displayName: 'File Read',
          category: 'io',
          icon: Icons.file_open,
          inputs: <NodePortDefinition>[],
          outputs: <NodePortDefinition>[
            NodePortDefinition(name: 'out', schema: 'artifact/text'),
          ],
          inspectorFields: <NodeInspectorFieldDefinition>[
            NodeInspectorFieldDefinition(
              key: 'input_file',
              label: 'Input file',
              kind: NodeInspectorFieldKind.string,
              required: true,
            ),
          ],
          defaultConfig: <String, dynamic>{'input_file': ''},
        ),
        NodeTypeDefinition(
          typeId: 'file.write',
          displayName: 'File Write',
          category: 'io',
          icon: Icons.save,
          inputs: <NodePortDefinition>[
            NodePortDefinition(name: 'in', schema: 'artifact/text'),
          ],
          outputs: <NodePortDefinition>[
            NodePortDefinition(name: 'out', schema: 'artifact/output_file'),
          ],
          inspectorFields: <NodeInspectorFieldDefinition>[
            NodeInspectorFieldDefinition(
              key: 'output_file',
              label: 'Output file',
              kind: NodeInspectorFieldKind.string,
              required: true,
            ),
            NodeInspectorFieldDefinition(
              key: 'primary',
              label: 'Primary output',
              kind: NodeInspectorFieldKind.boolType,
            ),
          ],
          defaultConfig: <String, dynamic>{'output_file': '', 'primary': false},
        ),
        NodeTypeDefinition(
          typeId: 'llm.chat',
          displayName: 'LLM Chat',
          category: 'ai',
          icon: Icons.auto_awesome,
          inputs: <NodePortDefinition>[
            NodePortDefinition(name: 'in', schema: 'artifact/text'),
          ],
          outputs: <NodePortDefinition>[
            NodePortDefinition(name: 'out', schema: 'artifact/text'),
          ],
          inspectorFields: <NodeInspectorFieldDefinition>[
            NodeInspectorFieldDefinition(
              key: 'model',
              label: 'Model override',
              kind: NodeInspectorFieldKind.string,
              optionalHint: true,
            ),
            NodeInspectorFieldDefinition(
              key: 'system_prompt',
              label: 'System prompt',
              kind: NodeInspectorFieldKind.string,
              optionalHint: true,
              multiline: true,
            ),
          ],
          defaultConfig: <String, dynamic>{'model': '', 'system_prompt': ''},
        ),
      ];

  factory NodeTypeRegistry.fallback() {
    return const NodeTypeRegistry(
      all: fallbackDefinitions,
      source: NodeTypeRegistrySource.fallback,
      rawServerDefs: <NodeTypeDef>[],
    );
  }

  factory NodeTypeRegistry.fromServerNodeTypes(
    List<NodeTypeDef> defs, {
    required NodeTypeRegistrySource source,
  }) {
    final parsed = defs
        .map(NodeTypeDefinition.fromServer)
        .where((item) => item.typeId.trim().isNotEmpty)
        .toList(growable: false);
    if (parsed.isEmpty) {
      return NodeTypeRegistry.fallback();
    }
    return NodeTypeRegistry(
      all: parsed,
      source: source,
      rawServerDefs: List<NodeTypeDef>.unmodifiable(defs),
    );
  }

  NodeTypeDefinition? byType(String typeId) {
    for (final def in all) {
      if (def.typeId == typeId) {
        return def;
      }
    }
    return null;
  }

  NodeTemplate createTemplate(String typeId) {
    final def = byType(typeId);
    if (def == null) {
      throw ArgumentError('Unknown node type: $typeId');
    }
    return NodeTemplate(
      typeId: def.typeId,
      displayName: def.displayName,
      inputs: def.inputs
          .map((port) => port.toFlowPort())
          .toList(growable: false),
      outputs: def.outputs
          .map((port) => port.toFlowPort())
          .toList(growable: false),
      config: Map<String, dynamic>.from(def.defaultConfig),
    );
  }
}

IconData _iconFor(String type, String category) {
  switch (type) {
    case 'file.read':
      return Icons.file_open;
    case 'file.write':
      return Icons.save;
    case 'llm.chat':
      return Icons.auto_awesome;
    default:
      switch (category) {
        case 'ai':
          return Icons.smart_toy;
        case 'io':
          return Icons.cable;
        default:
          return Icons.widgets;
      }
  }
}

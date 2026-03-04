import 'package:client/src/flow/flow_document_builder.dart';
import 'package:flutter/material.dart';

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
    this.required = false,
    this.optionalHint = false,
    this.multiline = false,
  });

  final String key;
  final String label;
  final bool required;
  final bool optionalHint;
  final bool multiline;
}

class NodeTypeDefinition {
  const NodeTypeDefinition({
    required this.typeId,
    required this.displayName,
    required this.icon,
    required this.inputs,
    required this.outputs,
    required this.inspectorFields,
    required this.defaultConfig,
  });

  final String typeId;
  final String displayName;
  final IconData icon;
  final List<NodePortDefinition> inputs;
  final List<NodePortDefinition> outputs;
  final List<NodeInspectorFieldDefinition> inspectorFields;
  final Map<String, String> defaultConfig;
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
  static const List<NodeTypeDefinition> all = <NodeTypeDefinition>[
    NodeTypeDefinition(
      typeId: 'file.read',
      displayName: 'File Read',
      icon: Icons.file_open,
      inputs: <NodePortDefinition>[],
      outputs: <NodePortDefinition>[
        NodePortDefinition(name: 'out', schema: 'artifact/text'),
      ],
      inspectorFields: <NodeInspectorFieldDefinition>[
        NodeInspectorFieldDefinition(
          key: 'input_file',
          label: 'input_file',
          required: true,
        ),
      ],
      defaultConfig: <String, String>{'input_file': 'input.txt'},
    ),
    NodeTypeDefinition(
      typeId: 'llm.chat',
      displayName: 'LLM Chat',
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
          label: 'model override',
          optionalHint: true,
        ),
        NodeInspectorFieldDefinition(
          key: 'system_prompt',
          label: 'system_prompt',
          optionalHint: true,
          multiline: true,
        ),
      ],
      defaultConfig: <String, String>{'model': '', 'system_prompt': ''},
    ),
    NodeTypeDefinition(
      typeId: 'file.write',
      displayName: 'File Write',
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
          label: 'output_file',
          required: true,
        ),
      ],
      defaultConfig: <String, String>{'output_file': 'output.txt'},
    ),
  ];

  static NodeTypeDefinition? byType(String typeId) {
    for (final def in all) {
      if (def.typeId == typeId) {
        return def;
      }
    }
    return null;
  }

  static NodeTemplate createTemplate(String typeId) {
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

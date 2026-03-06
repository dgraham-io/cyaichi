import 'package:client/src/flow/flow_document_builder.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';

enum ProcessorInspectorFieldKind { string, boolType }

enum ProcessorTypeRegistrySource { server, cached, fallback }

class ProcessorPortDefinition {
  const ProcessorPortDefinition({required this.name, this.schema});

  final String name;
  final String? schema;

  FlowPort toFlowPort() => FlowPort(port: name, schema: schema ?? '');
}

class ProcessorInspectorFieldDefinition {
  const ProcessorInspectorFieldDefinition({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.optionalHint = false,
    this.multiline = false,
  });

  final String key;
  final String label;
  final ProcessorInspectorFieldKind kind;
  final bool required;
  final bool optionalHint;
  final bool multiline;
}

class ProcessorTypeDefinition {
  const ProcessorTypeDefinition({
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
  final List<ProcessorPortDefinition> inputs;
  final List<ProcessorPortDefinition> outputs;
  final List<ProcessorInspectorFieldDefinition> inspectorFields;
  final Map<String, dynamic> defaultConfig;

  factory ProcessorTypeDefinition.fromServer(NodeTypeDef def) {
    final fields = def.configSchema
        .map((field) {
          final kind = field.kind == 'bool'
              ? ProcessorInspectorFieldKind.boolType
              : ProcessorInspectorFieldKind.string;
          return ProcessorInspectorFieldDefinition(
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
        case ProcessorInspectorFieldKind.string:
          defaults[field.key] = '';
          break;
        case ProcessorInspectorFieldKind.boolType:
          defaults[field.key] = false;
          break;
      }
    }

    return ProcessorTypeDefinition(
      typeId: def.type,
      displayName: def.displayName,
      category: def.category,
      icon: _iconFor(def.type, def.category),
      inputs: def.inputs
          .map(
            (port) =>
                ProcessorPortDefinition(name: port.port, schema: port.schema),
          )
          .toList(growable: false),
      outputs: def.outputs
          .map(
            (port) =>
                ProcessorPortDefinition(name: port.port, schema: port.schema),
          )
          .toList(growable: false),
      inspectorFields: fields,
      defaultConfig: defaults,
    );
  }
}

class ProcessorTemplate {
  const ProcessorTemplate({
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

class ProcessorTypeRegistry {
  const ProcessorTypeRegistry({
    required this.all,
    required this.source,
    required this.rawServerDefs,
  });

  final List<ProcessorTypeDefinition> all;
  final ProcessorTypeRegistrySource source;
  final List<NodeTypeDef> rawServerDefs;

  static const List<ProcessorTypeDefinition> fallbackDefinitions =
      <ProcessorTypeDefinition>[
        ProcessorTypeDefinition(
          typeId: 'file.read',
          displayName: 'File Read',
          category: 'io',
          icon: Icons.file_open,
          inputs: <ProcessorPortDefinition>[],
          outputs: <ProcessorPortDefinition>[
            ProcessorPortDefinition(name: 'out', schema: 'artifact/text'),
          ],
          inspectorFields: <ProcessorInspectorFieldDefinition>[
            ProcessorInspectorFieldDefinition(
              key: 'input_file',
              label: 'Input file',
              kind: ProcessorInspectorFieldKind.string,
              required: true,
            ),
          ],
          defaultConfig: <String, dynamic>{'input_file': ''},
        ),
        ProcessorTypeDefinition(
          typeId: 'file.write',
          displayName: 'File Write',
          category: 'io',
          icon: Icons.save,
          inputs: <ProcessorPortDefinition>[
            ProcessorPortDefinition(name: 'in', schema: 'artifact/text'),
          ],
          outputs: <ProcessorPortDefinition>[
            ProcessorPortDefinition(
              name: 'out',
              schema: 'artifact/output_file',
            ),
          ],
          inspectorFields: <ProcessorInspectorFieldDefinition>[
            ProcessorInspectorFieldDefinition(
              key: 'output_file',
              label: 'Output file',
              kind: ProcessorInspectorFieldKind.string,
              required: true,
            ),
            ProcessorInspectorFieldDefinition(
              key: 'primary',
              label: 'Primary output',
              kind: ProcessorInspectorFieldKind.boolType,
            ),
          ],
          defaultConfig: <String, dynamic>{'output_file': '', 'primary': false},
        ),
        ProcessorTypeDefinition(
          typeId: 'llm.chat',
          displayName: 'LLM Chat',
          category: 'ai',
          icon: Icons.auto_awesome,
          inputs: <ProcessorPortDefinition>[
            ProcessorPortDefinition(name: 'in', schema: 'artifact/text'),
          ],
          outputs: <ProcessorPortDefinition>[
            ProcessorPortDefinition(name: 'out', schema: 'artifact/text'),
          ],
          inspectorFields: <ProcessorInspectorFieldDefinition>[
            ProcessorInspectorFieldDefinition(
              key: 'model',
              label: 'Model override',
              kind: ProcessorInspectorFieldKind.string,
              optionalHint: true,
            ),
            ProcessorInspectorFieldDefinition(
              key: 'system_prompt',
              label: 'System prompt',
              kind: ProcessorInspectorFieldKind.string,
              optionalHint: true,
              multiline: true,
            ),
          ],
          defaultConfig: <String, dynamic>{'model': '', 'system_prompt': ''},
        ),
      ];

  factory ProcessorTypeRegistry.fallback() {
    return const ProcessorTypeRegistry(
      all: fallbackDefinitions,
      source: ProcessorTypeRegistrySource.fallback,
      rawServerDefs: <NodeTypeDef>[],
    );
  }

  factory ProcessorTypeRegistry.fromServerProcessorTypes(
    List<NodeTypeDef> defs, {
    required ProcessorTypeRegistrySource source,
  }) {
    final parsed = defs
        .map(ProcessorTypeDefinition.fromServer)
        .where((item) => item.typeId.trim().isNotEmpty)
        .toList(growable: false);
    if (parsed.isEmpty) {
      return ProcessorTypeRegistry.fallback();
    }
    return ProcessorTypeRegistry(
      all: parsed,
      source: source,
      rawServerDefs: List<NodeTypeDef>.unmodifiable(defs),
    );
  }

  ProcessorTypeDefinition? byType(String typeId) {
    for (final def in all) {
      if (def.typeId == typeId) {
        return def;
      }
    }
    return null;
  }

  ProcessorTemplate createTemplate(String typeId) {
    final def = byType(typeId);
    if (def == null) {
      throw ArgumentError('Unknown node type: $typeId');
    }
    return ProcessorTemplate(
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

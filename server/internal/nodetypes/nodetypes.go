package nodetypes

type PortDef struct {
	Port   string `json:"port"`
	Schema string `json:"schema"`
}

type ConfigFieldDef struct {
	Key      string `json:"key"`
	Kind     string `json:"kind"`
	Required bool   `json:"required"`
	Label    string `json:"label"`
}

type NodeTypeDef struct {
	Type         string           `json:"type"`
	DisplayName  string           `json:"display_name"`
	Category     string           `json:"category"`
	Inputs       []PortDef        `json:"inputs"`
	Outputs      []PortDef        `json:"outputs"`
	ConfigSchema []ConfigFieldDef `json:"config_schema"`
}

const (
	TypeFileRead  = "file.read"
	TypeLLMChat   = "llm.chat"
	TypeFileWrite = "file.write"
)

var builtins = []NodeTypeDef{
	{
		Type:        TypeFileRead,
		DisplayName: "File Read",
		Category:    "io",
		Inputs:      []PortDef{},
		Outputs: []PortDef{
			{Port: "out", Schema: "artifact/text"},
		},
		ConfigSchema: []ConfigFieldDef{
			{Key: "input_file", Kind: "string", Required: true, Label: "Input file"},
		},
	},
	{
		Type:        TypeFileWrite,
		DisplayName: "File Write",
		Category:    "io",
		Inputs: []PortDef{
			{Port: "in", Schema: "artifact/text"},
		},
		Outputs: []PortDef{
			{Port: "out", Schema: "artifact/output_file"},
		},
		ConfigSchema: []ConfigFieldDef{
			{Key: "output_file", Kind: "string", Required: true, Label: "Output file"},
			{Key: "primary", Kind: "bool", Required: false, Label: "Primary output"},
		},
	},
	{
		Type:        TypeLLMChat,
		DisplayName: "LLM Chat",
		Category:    "ai",
		Inputs: []PortDef{
			{Port: "in", Schema: "artifact/text"},
		},
		Outputs: []PortDef{
			{Port: "out", Schema: "artifact/text"},
		},
		ConfigSchema: []ConfigFieldDef{
			{Key: "model", Kind: "string", Required: false, Label: "Model override"},
			{Key: "system_prompt", Kind: "string", Required: false, Label: "System prompt"},
		},
	},
}

func List() []NodeTypeDef {
	out := make([]NodeTypeDef, 0, len(builtins))
	for _, item := range builtins {
		copyItem := item
		copyItem.Inputs = append(make([]PortDef, 0, len(item.Inputs)), item.Inputs...)
		copyItem.Outputs = append(make([]PortDef, 0, len(item.Outputs)), item.Outputs...)
		copyItem.ConfigSchema = append(make([]ConfigFieldDef, 0, len(item.ConfigSchema)), item.ConfigSchema...)
		out = append(out, copyItem)
	}
	return out
}

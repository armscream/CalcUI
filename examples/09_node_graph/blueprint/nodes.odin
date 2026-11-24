#+feature global-context
package blueprint

import NG "../../../src/GUI/NodeGraph"
import "core:strings"

@(init)
register_core_nodes :: proc() {
	Register_Def(Node_Def{
		name = "Entry",
		flow = .Entry,
		type = NG.Graph_Node_Type_Desc{
			name = "Entry",
			category = "Flow",
			description = "The start of the execution",
			colour = DEFAULT_NODE_COLOUR,
			outputs = []NG.Graph_Port_Desc{Exec_Output("Exec")},
		},
	})
	Register_Def(Node_Def{
		name = "Branch",
		flow = .Branch,
		type = NG.Graph_Node_Type_Desc{
			name = "Branch",
			category = "Flow",
			description = "Chooses one of two execution paths",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Condition", TYPE_BOOL),
			},
			outputs = []NG.Graph_Port_Desc{
				Exec_Output("True"),
				Exec_Output("False"),
			},
		},
	})
	Register_Def(Node_Def{
		name = "Sequence",
		flow = .Sequence,
		type = NG.Graph_Node_Type_Desc{
			name = "Sequence",
			category = "Flow",
			description = "Runs every execution path in order",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{Exec_Input("Exec")},
			outputs = []NG.Graph_Port_Desc{
				Exec_Output("Exec 1"),
				Exec_Output("Exec 2"),
			},
			policy = NG.Graph_Port_Policy{
				add_outputs = true,
				max_outputs = 8,
				output_prefix = "Exec",
			},
		},
	})
	Register_Def(Node_Def{
		name = "Do Once",
		flow = .Do_Once,
		type = NG.Graph_Node_Type_Desc{
			name = "Do Once",
			category = "Flow",
			description = "Runs its output only on the first execution",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{Exec_Input("Exec")},
			outputs = []NG.Graph_Port_Desc{Exec_Output("Exec")},
		},
	})
	Register_Def(Node_Def{
		name = "Gate",
		flow = .Gate,
		type = NG.Graph_Node_Type_Desc{
			name = "Gate",
			category = "Flow",
			description = "Runs its output while the gate is open",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Open", TYPE_BOOL),
			},
			outputs = []NG.Graph_Port_Desc{Exec_Output("Exec")},
		},
	})
	Register_Def(Node_Def{
		name = "Flip Flop",
		flow = .Flip_Flop,
		type = NG.Graph_Node_Type_Desc{
			name = "Flip Flop",
			category = "Flow",
			description = "Alternates between two execution paths",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{Exec_Input("Exec")},
			outputs = []NG.Graph_Port_Desc{
				Exec_Output("A"),
				Exec_Output("B"),
			},
		},
	})
	Register_Def(Node_Def{
		name = "Multi Gate",
		flow = .Multi_Gate,
		type = NG.Graph_Node_Type_Desc{
			name = "Multi Gate",
			category = "Flow",
			description = "Runs every gate that has been opened",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Open 1", TYPE_BOOL),
				Data_Input("Open 2", TYPE_BOOL),
			},
			outputs = []NG.Graph_Port_Desc{
				Exec_Output("Out 1"),
				Exec_Output("Out 2"),
			},
		},
	})
	Register_Def(Node_Def{
		name = "For Loop",
		flow = .For_Loop,
		type = NG.Graph_Node_Type_Desc{
			name = "For Loop",
			category = "Loop",
			description = "Runs its body for every value of the range",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Start", TYPE_INT),
				Data_Input("End", TYPE_INT),
			},
			outputs = []NG.Graph_Port_Desc{
				Exec_Output("Body"),
				Exec_Output("Completed"),
				Data_Output("Index", TYPE_INT),
			},
		},
		evaluate = for_loop_index,
	})
	Register_Def(Node_Def{
		name = "While Loop",
		flow = .While_Loop,
		type = NG.Graph_Node_Type_Desc{
			name = "While Loop",
			category = "Loop",
			description = "Runs its body while the condition holds",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Condition", TYPE_BOOL),
			},
			outputs = []NG.Graph_Port_Desc{
				Exec_Output("Body"),
				Exec_Output("Completed"),
			},
		},
	})
	Register_Def(Node_Def{
		name = "Set Variable",
		flow = .Set_Variable,
		type = NG.Graph_Node_Type_Desc{
			name = "Set Variable",
			category = "Variable",
			description = "Stores a value in a graph variable",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Value", TYPE_FLOAT),
			},
			outputs = []NG.Graph_Port_Desc{Exec_Output("Exec")},
			config = []NG.Graph_Config_Entry{
				{key = "name", value = Config_Text("value")},
				{key = "type", value = Config_Text(TYPE_FLOAT)},
			},
		},
		configure = set_variable_configure,
	})
	Register_Def(Node_Def{
		name = "Get Variable",
		flow = .Get_Variable,
		type = NG.Graph_Node_Type_Desc{
			name = "Get Variable",
			category = "Variable",
			description = "Reads a value from a graph variable",
			colour = DEFAULT_NODE_COLOUR,
			outputs = []NG.Graph_Port_Desc{Data_Output("Value", TYPE_FLOAT)},
			config = []NG.Graph_Config_Entry{
				{key = "name", value = Config_Text("value")},
				{key = "type", value = Config_Text(TYPE_FLOAT)},
			},
		},
		configure = get_variable_configure,
		evaluate = get_variable_evaluate,
	})
	Register_Def(Node_Def{
		name = "Variable Input",
		flow = .Pure,
		type = NG.Graph_Node_Type_Desc{
			name = "Variable Input",
			category = "Input",
			description = "A named value whose type can be chosen",
			colour = DEFAULT_NODE_COLOUR,
			outputs = []NG.Graph_Port_Desc{Data_Output("Value", TYPE_FLOAT)},
			config = []NG.Graph_Config_Entry{
				{key = "name", value = Config_Text("value")},
				{key = "type", value = Config_Text(TYPE_FLOAT)},
				{key = "value", value = NG.Graph_Value(f32(0))},
			},
		},
		configure = variable_input_configure,
		evaluate = variable_input_evaluate,
	})
	Register_Def(Node_Def{
		name = "Print String",
		flow = .Print,
		type = NG.Graph_Node_Type_Desc{
			name = "Print String",
			category = "Debug",
			description = "Writes a value to the log",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Value", TYPE_STRING),
			},
			outputs = []NG.Graph_Port_Desc{Exec_Output("Exec")},
			config = []NG.Graph_Config_Entry{
				{key = "type", value = Config_Text(TYPE_STRING)},
			},
		},
		configure = print_configure,
	})
	Register_Def(Node_Def{
		name = "Output",
		flow = .Output,
		type = NG.Graph_Node_Type_Desc{
			name = "Output",
			category = "Output",
			description = "The result of the graph",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{
				Exec_Input("Exec"),
				Data_Input("Value", TYPE_FLOAT),
			},
			config = []NG.Graph_Config_Entry{
				{key = "type", value = Config_Text(TYPE_FLOAT)},
				{key = "result", value = NG.Graph_Value(f32(0)), read_only = true},
			},
		},
		configure = output_configure,
	})
	Register_Def(Node_Def{
		name = "Pass Through",
		flow = .Pass_Through,
		type = NG.Graph_Node_Type_Desc{
			name = "Pass Through",
			category = "Flow",
			description = "Forwards a value unchanged",
			colour = DEFAULT_NODE_COLOUR,
			inputs = []NG.Graph_Port_Desc{Data_Input("Value", TYPE_FLOAT)},
			outputs = []NG.Graph_Port_Desc{Data_Output("Value", TYPE_FLOAT)},
			config = []NG.Graph_Config_Entry{
				{key = "type", value = Config_Text(TYPE_FLOAT)},
			},
		},
		configure = pass_through_configure,
	})
	Register_Def(Node_Def{
		name = "Text",
		flow = .Pure,
		type = NG.Graph_Node_Type_Desc{
			name = "Text",
			category = "Input",
			description = "A constant text value",
			colour = DEFAULT_NODE_COLOUR,
			outputs = []NG.Graph_Port_Desc{Data_Output("Value", TYPE_STRING)},
			config = []NG.Graph_Config_Entry{
				{key = "value", value = Config_Text("")},
			},
		},
		evaluate = text_evaluate,
	})
}

config_type_of :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID, key: string) -> string {
	value, found := NG.Graph_Get_Config_Value(graph, node_id, key)
	if !found {return ""}
	text, ok := Value_As_String(value)
	if !ok {return ""}
	return text
}

configured_type :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID, key: string) -> string {
	configured := config_type_of(graph, node_id, key)
	if configured == "" {return TYPE_FLOAT}
	return configured
}

port_type_of :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> string {
	node := NG.Node_Graph_Node_Of(graph, node_id)
	if node == nil {return ""}
	for port in node.ports {
		if port.alive && port.direction == .Input && port.port_kind == .Data {return port.type}
	}
	return ""
}

source_type_of :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> string {
	for wire in graph.wires {
		if !wire.alive || wire.to_node != node_id {continue}
		port := NG.Node_Graph_Port_Of(graph, node_id, wire.to_port)
		if port == nil || port.port_kind != .Data {continue}
		return NG.Graph_Effective_Port_Type(graph, wire.from_node, wire.from_port)
	}
	return ""
}

output_configure :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> bool {
	node := NG.Node_Graph_Node_Of(graph, node_id)
	if node == nil {return false}
	type_name := strings.clone(configured_type(graph, node_id, "type"))
	defer delete(type_name)
	source_type := source_type_of(graph, node_id)
	if source_type != "" && !Can_Convert(source_type, type_name) {
		current := port_type_of(graph, node_id)
		NG.Graph_Set_Config_Value(graph, node_id, "type", NG.Graph_Value(current))
		return false
	}
	NG.Graph_Set_Ports(graph, node_id, []NG.Graph_Port_Desc{
		Exec_Input("Exec"),
		Data_Input("Value", type_name),
	})
	NG.Graph_Set_Config_Value(graph, node_id, "result", Value_Of_Type(type_name))
	return true
}

set_variable_configure :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> bool {
	type_name := strings.clone(configured_type(graph, node_id, "type"))
	defer delete(type_name)
	NG.Graph_Set_Ports(graph, node_id, []NG.Graph_Port_Desc{
		Exec_Input("Exec"),
		Data_Input("Value", type_name),
		Exec_Output("Exec"),
	})
	return true
}

get_variable_configure :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> bool {
	type_name := strings.clone(configured_type(graph, node_id, "type"))
	defer delete(type_name)
	NG.Graph_Set_Ports(graph, node_id, []NG.Graph_Port_Desc{
		Data_Output("Value", type_name),
	})
	return true
}

//* A variable input keeps its output type equal to the type in its
//* configuration, keeps its stored value in that type, and shows the
//* variable name as the title of the node. The value of the configuration
//* is reset only when the type changes, so an edit of the value survives a
//* rename.
variable_input_configure :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> bool {
	node := NG.Node_Graph_Node_Of(graph, node_id)
	if node == nil {return false}
	type_name := strings.clone(configured_type(graph, node_id, "type"))
	defer delete(type_name)
	NG.Graph_Set_Ports(graph, node_id, []NG.Graph_Port_Desc{
		Data_Output("Value", type_name),
	})
	value, found := NG.Graph_Get_Config_Value(graph, node_id, "value")
	if !found || NG.Graph_Value_Kind_Of(value) != Value_Kind_Of_Type(type_name) {
		NG.Graph_Set_Config_Value(graph, node_id, "value", Value_Of_Type(type_name))
	}
	name := config_type_of(graph, node_id, "name")
	if name == "" {name = "Variable"}
	if node.title != name {
		old := node.title
		node.title = strings.clone(name)
		if len(old) > 0 {delete(old)}
	}
	return true
}

variable_input_evaluate :: proc(ctx: ^Eval_Context, port: NG.Graph_Port_ID) -> (NG.Graph_Value, bool) {
	type_name := Ctx_Port_Type(ctx, port)
	value, found := ctx.config_value(ctx, "value")
	if !found {return Value_Of_Type(type_name), true}
	if converted, ok := Convert_Value(value, type_name); ok {return converted, true}
	return Value_Of_Type(type_name), true
}

print_configure :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> bool {
	type_name := strings.clone(configured_type(graph, node_id, "type"))
	defer delete(type_name)
	NG.Graph_Set_Ports(graph, node_id, []NG.Graph_Port_Desc{
		Exec_Input("Exec"),
		Data_Input("Value", type_name),
		Exec_Output("Exec"),
	})
	return true
}

pass_through_configure :: proc(graph: ^NG.Node_Graph, node_id: NG.Graph_Node_ID) -> bool {
	type_name := strings.clone(configured_type(graph, node_id, "type"))
	defer delete(type_name)
	NG.Graph_Set_Ports(graph, node_id, []NG.Graph_Port_Desc{
		Data_Input("Value", type_name),
		Data_Output("Value", type_name),
	})
	return true
}

for_loop_index :: proc(ctx: ^Eval_Context, port: NG.Graph_Port_ID) -> (NG.Graph_Value, bool) {
	rs := (^run_state)(ctx.state)
	if rs == nil {return NG.Graph_Value(i32(0)), true}
	state := state_ptr(rs.runtime, ctx.node)
	if state == nil {return NG.Graph_Value(i32(0)), true}
	return NG.Graph_Value(i32(state.index)), true
}

get_variable_evaluate :: proc(ctx: ^Eval_Context, port: NG.Graph_Port_ID) -> (NG.Graph_Value, bool) {
	name := Ctx_Config_Text(ctx, "name")
	rs := (^run_state)(ctx.state)
	if rs != nil {
		if value, found := Runtime_Variable_Get(rs.runtime, name); found {return value, true}
	}
	return Value_Of_Type(Ctx_Port_Type(ctx, port)), true
}

text_evaluate :: proc(ctx: ^Eval_Context, port: NG.Graph_Port_ID) -> (NG.Graph_Value, bool) {
	value, found := ctx.config_value(ctx, "value")
	if !found {return NG.Graph_Value(""), true}
	return value, true
}

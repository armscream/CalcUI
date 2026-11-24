package blueprint

import Core "../../../src/GUI/Core"
import GUI "../../../src/GUI"
import NG "../../../src/GUI/NodeGraph"
import "core:strings"

Flow_Kind :: enum {
	Pure,
	Entry,
	Branch,
	Sequence,
	Do_Once,
	Gate,
	Flip_Flop,
	Multi_Gate,
	For_Loop,
	While_Loop,
	Set_Variable,
	Get_Variable,
	Print,
	Output,
	Pass_Through,
}

TYPE_EXEC :: "exec"
TYPE_BOOL :: "bool"
TYPE_INT :: "int"
TYPE_FLOAT :: "float"
TYPE_VEC2 :: "vec2"
TYPE_VEC3 :: "vec3"
TYPE_STRING :: "string"
TYPE_NAME :: "name"

DEFAULT_STEP_BUDGET :: 10000
MAX_EXEC_DEPTH :: 256
DEFAULT_NODE_COLOUR :: Core.Colour{0.17, 0.19, 0.25, 1}

Data_Input :: proc(name, type_name: string) -> NG.Graph_Port_Desc {
	return NG.Graph_Port_Desc{
		name = name,
		direction = .Input,
		port_kind = .Data,
		type = type_name,
		capacity = 1,
		visible = true,
	}
}

Data_Output :: proc(name, type_name: string) -> NG.Graph_Port_Desc {
	return NG.Graph_Port_Desc{
		name = name,
		direction = .Output,
		port_kind = .Data,
		type = type_name,
		capacity = -1,
		visible = true,
	}
}

Exec_Input :: proc(name: string) -> NG.Graph_Port_Desc {
	return NG.Graph_Port_Desc{
		name = name,
		direction = .Input,
		port_kind = .Exec,
		type = TYPE_EXEC,
		capacity = -1,
		visible = true,
	}
}

Exec_Output :: proc(name: string) -> NG.Graph_Port_Desc {
	return NG.Graph_Port_Desc{
		name = name,
		direction = .Output,
		port_kind = .Exec,
		type = TYPE_EXEC,
		capacity = -1,
		visible = true,
	}
}

Value_Bool :: proc(value: bool) -> NG.Graph_Value {
	return NG.Graph_Value(value)
}

Value_Int :: proc(value: i32) -> NG.Graph_Value {
	return NG.Graph_Value(value)
}

Value_Float :: proc(value: f32) -> NG.Graph_Value {
	return NG.Graph_Value(value)
}

Value_Vec2 :: proc(value: Core.Vec2) -> NG.Graph_Value {
	return NG.Graph_Value(value)
}

Value_Vec3 :: proc(value: Core.Vec3) -> NG.Graph_Value {
	return NG.Graph_Value(value)
}

Value_String :: proc(value: string) -> NG.Graph_Value {
	return NG.Graph_Value(strings.clone(value))
}

Config_Text :: proc(value: string) -> NG.Graph_Value {
	return NG.Graph_Value(strings.clone(value))
}

Type_Matches :: proc(type_name, expected: string) -> bool {
	if len(type_name) != len(expected) {return false}
	for i in 0 ..< len(type_name) {
		left := type_name[i]
		right := expected[i]
		if left >= 'A' && left <= 'Z' {left += 'a' - 'A'}
		if right >= 'A' && right <= 'Z' {right += 'a' - 'A'}
		if left != right {return false}
	}
	return true
}

Value_Kind_Of_Type :: proc(type_name: string) -> NG.Graph_Value_Kind {
	if Type_Matches(type_name, "bool") || Type_Matches(type_name, "boolean") {return .Bool}
	if Type_Matches(type_name, "int") || Type_Matches(type_name, "integer") {return .Int}
	if Type_Matches(type_name, "float") || Type_Matches(type_name, "double") {return .Float}
	if Type_Matches(type_name, "vec2") || Type_Matches(type_name, "vector2") {return .Vec2}
	if Type_Matches(type_name, "vec3") || Type_Matches(type_name, "vector3") {return .Vec3}
	if Type_Matches(type_name, "string") || Type_Matches(type_name, "text") {return .String}
	if Type_Matches(type_name, "name") {return .String}
	return .Float
}

Value_Of_Type :: proc(type_name: string) -> NG.Graph_Value {
	#partial switch Value_Kind_Of_Type(type_name) {
	case .Bool:   return NG.Graph_Value(false)
	case .Int:    return NG.Graph_Value(i32(0))
	case .Float:  return NG.Graph_Value(f32(0))
	case .Vec2:   return NG.Graph_Value(Core.Vec2{})
	case .Vec3:   return NG.Graph_Value(Core.Vec3{})
	case .String: return NG.Graph_Value("")
	}
	return NG.Graph_Value(f32(0))
}

Value_As_Bool :: proc(value: NG.Graph_Value) -> (bool, bool) {
	#partial switch v in value {
	case bool:
		return v, true
	case i32:
		return v != 0, true
	case f32:
		return v != 0, true
	}
	return false, false
}

Value_As_Int :: proc(value: NG.Graph_Value) -> (i32, bool) {
	#partial switch v in value {
	case i32:
		return v, true
	case f32:
		return i32(v), true
	case bool:
		if v {return 1, true}
		return 0, true
	}
	return 0, false
}

Value_As_Float :: proc(value: NG.Graph_Value) -> (f32, bool) {
	#partial switch v in value {
	case f32:
		return v, true
	case i32:
		return f32(v), true
	case bool:
		if v {return 1, true}
		return 0, true
	}
	return 0, false
}

Value_As_String :: proc(value: NG.Graph_Value) -> (string, bool) {
	#partial switch v in value {
	case string:
		return v, true
	}
	return "", false
}

Value_As_Vec2 :: proc(value: NG.Graph_Value) -> (Core.Vec2, bool) {
	#partial switch v in value {
	case Core.Vec2:
		return v, true
	case Core.Vec3:
		return Core.Vec2{v.x, v.y}, true
	case f32:
		return Core.Vec2{v, v}, true
	}
	return Core.Vec2{}, false
}

Value_As_Vec3 :: proc(value: NG.Graph_Value) -> (Core.Vec3, bool) {
	#partial switch v in value {
	case Core.Vec3:
		return v, true
	case Core.Vec2:
		return Core.Vec3{v.x, v.y, 0}, true
	case f32:
		return Core.Vec3{v, v, v}, true
	}
	return Core.Vec3{}, false
}

Configure_Callback :: proc(graph: ^NG.Node_Graph, node: NG.Graph_Node_ID) -> bool

Evaluate_Callback :: proc(ctx: ^Eval_Context, port: NG.Graph_Port_ID) -> (NG.Graph_Value, bool)

Node_Def :: struct {
	name:      string,
	flow:      Flow_Kind,
	type:      NG.Graph_Node_Type_Desc,
	configure: Configure_Callback,
	evaluate:  Evaluate_Callback,
}

Kind_Def :: struct {
	name:         string,
	type:         NG.Graph_Kind_Desc,
	allowed_nodes: [dynamic]string,
}

Node_Def_Clone :: proc(def: Node_Def) -> Node_Def {
	clone := def
	clone.name = strings.clone(def.name)
	clone.type.name = strings.clone(def.type.name)
	clone.type.category = strings.clone(def.type.category)
	clone.type.description = strings.clone(def.type.description)
	clone.type.inputs = NG.Graph_Port_Desc_List_Clone(def.type.inputs)[:]
	clone.type.outputs = NG.Graph_Port_Desc_List_Clone(def.type.outputs)[:]
	clone.type.config = NG.Graph_Config_Clone(def.type.config)[:]
	clone.type.policy = def.type.policy
	clone.type.policy.input_type = strings.clone(def.type.policy.input_type)
	clone.type.policy.output_type = strings.clone(def.type.policy.output_type)
	clone.type.policy.input_prefix = strings.clone(def.type.policy.input_prefix)
	clone.type.policy.output_prefix = strings.clone(def.type.policy.output_prefix)
	return clone
}

Node_Def_Free :: proc(def: ^Node_Def) {
	if len(def.name) > 0 {delete(def.name)}
	if len(def.type.name) > 0 {delete(def.type.name)}
	if len(def.type.category) > 0 {delete(def.type.category)}
	if len(def.type.description) > 0 {delete(def.type.description)}
	for &desc in def.type.inputs {NG.Graph_Port_Desc_Free(&desc)}
	for &desc in def.type.outputs {NG.Graph_Port_Desc_Free(&desc)}
	delete(def.type.inputs)
	delete(def.type.outputs)
	for &entry in def.type.config {
		if len(entry.key) > 0 {delete(entry.key)}
		NG.Graph_Value_Free(entry.value)
	}
	delete(def.type.config)
	if len(def.type.policy.input_type) > 0 {delete(def.type.policy.input_type)}
	if len(def.type.policy.output_type) > 0 {delete(def.type.policy.output_type)}
	if len(def.type.policy.input_prefix) > 0 {delete(def.type.policy.input_prefix)}
	if len(def.type.policy.output_prefix) > 0 {delete(def.type.policy.output_prefix)}
	def^ = Node_Def{}
}

Kind_Def_Clone :: proc(def: Kind_Def) -> Kind_Def {
	clone := def
	clone.name = strings.clone(def.name)
	clone.type.name = strings.clone(def.type.name)
	clone.type.description = strings.clone(def.type.description)
	allowed := def.type.allowed_nodes
	if len(allowed) == 0 {allowed = def.allowed_nodes[:]}
	clone.allowed_nodes = make([dynamic]string)
	for name in allowed {append(&clone.allowed_nodes, strings.clone(name))}
	clone.type.allowed_nodes = clone.allowed_nodes[:]
	return clone
}

Kind_Def_Free :: proc(def: ^Kind_Def) {
	if len(def.name) > 0 {delete(def.name)}
	if len(def.type.name) > 0 {delete(def.type.name)}
	if len(def.type.description) > 0 {delete(def.type.description)}
	for &name in def.allowed_nodes {
		if len(name) > 0 {delete(name)}
	}
	delete(def.allowed_nodes)
	def^ = Kind_Def{}
}

Registry :: struct {
	defs:  [dynamic]Node_Def,
	kinds: [dynamic]Kind_Def,
}

global_registry: Registry

Registry_Global :: proc() -> ^Registry {
	return &global_registry
}

Register_Def :: proc(def: Node_Def) -> bool {
	registry := Registry_Global()
	if def.name == "" {return false}
	owned := Node_Def_Clone(def)
	low := 0
	high := len(registry.defs)
	for low < high {
		mid := (low + high) / 2
		if registry.defs[mid].name < def.name {
			low = mid + 1
		} else {
			high = mid
		}
	}
	if low < len(registry.defs) && registry.defs[low].name == def.name {
		Node_Def_Free(&registry.defs[low])
		registry.defs[low] = owned
		return true
	}
	append(&registry.defs, owned)
	copy(registry.defs[low + 1:], registry.defs[low:])
	registry.defs[low] = owned
	return true
}

Register_Kind :: proc(def: Kind_Def) -> bool {
	registry := Registry_Global()
	if def.name == "" {return false}
	owned := Kind_Def_Clone(def)
	low := 0
	high := len(registry.kinds)
	for low < high {
		mid := (low + high) / 2
		if registry.kinds[mid].name < def.name {
			low = mid + 1
		} else {
			high = mid
		}
	}
	if low < len(registry.kinds) && registry.kinds[low].name == def.name {
		Kind_Def_Free(&registry.kinds[low])
		registry.kinds[low] = owned
		return true
	}
	append(&registry.kinds, owned)
	copy(registry.kinds[low + 1:], registry.kinds[low:])
	registry.kinds[low] = owned
	return true
}

Find_Def :: proc(name: string) -> ^Node_Def {
	registry := Registry_Global()
	low := 0
	high := len(registry.defs)
	for low < high {
		mid := (low + high) / 2
		if registry.defs[mid].name < name {
			low = mid + 1
		} else {
			high = mid
		}
	}
	if low < len(registry.defs) && registry.defs[low].name == name {return &registry.defs[low]}
	return nil
}

Find_Kind :: proc(name: string) -> ^Kind_Def {
	registry := Registry_Global()
	low := 0
	high := len(registry.kinds)
	for low < high {
		mid := (low + high) / 2
		if registry.kinds[mid].name < name {
			low = mid + 1
		} else {
			high = mid
		}
	}
	if low < len(registry.kinds) && registry.kinds[low].name == name {return &registry.kinds[low]}
	return nil
}

Def_Count :: proc() -> int {
	return len(global_registry.defs)
}

Def_At :: proc(index: int) -> ^Node_Def {
	if index < 0 || index >= len(global_registry.defs) {return nil}
	return &global_registry.defs[index]
}

Registry_Free :: proc() {
	for &def in global_registry.defs {Node_Def_Free(&def)}
	delete(global_registry.defs)
	global_registry.defs = nil
	for &kind in global_registry.kinds {Kind_Def_Free(&kind)}
	delete(global_registry.kinds)
	global_registry.kinds = nil
}

Register_Defs_In_Graph :: proc(graph: ^NG.Node_Graph) -> int {
	if graph == nil {return 0}
	registry := Registry_Global()
	count := 0
	for &def in registry.defs {
		desc := def.type
		if def.configure != nil {desc.configure = def_configure_adapter}
		if NG.Graph_Register_Type(graph, desc) >= 0 {count += 1}
	}
	return count
}

Register_Kinds_In_Graph :: proc(graph: ^NG.Node_Graph) -> int {
	if graph == nil {return 0}
	registry := Registry_Global()
	count := 0
	for &kind in registry.kinds {
		desc := kind.type
		desc.allowed_nodes = kind.allowed_nodes[:]
		if NG.Graph_Register_Kind(graph, desc) >= 0 {count += 1}
	}
	return count
}

Set_Connection_Policy :: proc(graph: ^NG.Node_Graph) {
	if graph == nil {return}
	graph.policy.type_compatible = blueprint_type_compatible
	graph.policy.allow_cycles = true
}

//* A wire carries a value of one type to a pin of the same type. An empty
//* name is a wildcard, for the ports of a custom node that has not chosen a
//* type yet. Widening belongs to a conversion reroute: accepting it here
//* would let a text output feed a number pin and make the reroute pointless.
blueprint_type_compatible :: proc(user_data: rawptr, from_type, to_type: string) -> bool {
	if from_type == "" || to_type == "" {return true}
	return Type_Matches(from_type, to_type)
}

//* The configure callback of the graph type. The definitions of the
//* blueprint library carry their own signature, so the type gets a small
//* adapter that finds the definition again. This is what lets a node rebuild
//* its ports - and its title - when its configuration changes.
def_configure_adapter :: proc(g: ^GUI.GUI, graph: GUI.Widget_ID, node: NG.Graph_Node_ID) {
	state := NG.node_graph_model(g, graph)
	if state == nil {return}
	Configure_Node(state, node)
}

Configure_Node :: proc(graph: ^NG.Node_Graph, node: NG.Graph_Node_ID) -> bool {
	if graph == nil {return false}
	data := NG.Node_Graph_Node_Of(graph, node)
	if data == nil {return false}
	def := Find_Def(data.type_name)
	if def == nil || def.configure == nil {return false}
	return def.configure(graph, node)
}

Set_Type_Colours :: proc(graph: ^NG.Node_Graph) {
	if graph == nil {return}
	NG.Graph_Set_Type_Colour(graph, TYPE_EXEC, NG.GRAPH_TYPE_EXEC_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_BOOL, NG.GRAPH_TYPE_BOOL_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_INT, NG.GRAPH_TYPE_INT_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_FLOAT, NG.GRAPH_TYPE_FLOAT_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_VEC2, NG.GRAPH_TYPE_VECTOR_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_VEC3, NG.GRAPH_TYPE_VECTOR_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_STRING, NG.GRAPH_TYPE_STRING_COLOUR)
	NG.Graph_Set_Type_Colour(graph, TYPE_NAME, NG.GRAPH_TYPE_STRING_COLOUR)
}

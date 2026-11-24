package blueprint

import Core "../../../src/GUI/Core"
import NG "../../../src/GUI/NodeGraph"

Eval_Context :: struct {
	graph:        ^NG.Node_Graph,
	node:         NG.Graph_Node_ID,
	def:          ^Node_Def,
	state:        rawptr,
	input_value:  proc(ctx: ^Eval_Context, port: NG.Graph_Port_ID) -> (NG.Graph_Value, bool),
	config_value: proc(ctx: ^Eval_Context, key: string) -> (NG.Graph_Value, bool),
}

Ctx_Port_By_Name :: proc(ctx: ^Eval_Context, name: string) -> NG.Graph_Port_ID {
	if ctx == nil {return NG.INVALID_GRAPH_PORT_ID}
	node := NG.Node_Graph_Node_Of(ctx.graph, ctx.node)
	if node == nil {return NG.INVALID_GRAPH_PORT_ID}
	for port in node.ports {
		if port.alive && port.name == name {return port.id}
	}
	return NG.INVALID_GRAPH_PORT_ID
}

Ctx_Port_Type :: proc(ctx: ^Eval_Context, port_id: NG.Graph_Port_ID) -> string {
	if ctx == nil {return ""}
	port := NG.Node_Graph_Port_Of(ctx.graph, ctx.node, port_id)
	if port == nil {return ""}
	return port.type
}

Ctx_Input :: proc(ctx: ^Eval_Context, name: string) -> (NG.Graph_Value, bool) {
	if ctx == nil || ctx.input_value == nil {return nil, false}
	port_id := Ctx_Port_By_Name(ctx, name)
	if port_id.index == 0 {return nil, false}
	return ctx.input_value(ctx, port_id)
}

Ctx_Float :: proc(ctx: ^Eval_Context, name: string) -> (f32, bool) {
	value, found := Ctx_Input(ctx, name)
	if !found {return 0, false}
	return Value_As_Float(value)
}

Ctx_Int :: proc(ctx: ^Eval_Context, name: string) -> (i32, bool) {
	value, found := Ctx_Input(ctx, name)
	if !found {return 0, false}
	return Value_As_Int(value)
}

Ctx_Bool :: proc(ctx: ^Eval_Context, name: string) -> (bool, bool) {
	value, found := Ctx_Input(ctx, name)
	if !found {return false, false}
	return Value_As_Bool(value)
}

Ctx_String :: proc(ctx: ^Eval_Context, name: string) -> (string, bool) {
	value, found := Ctx_Input(ctx, name)
	if !found {return "", false}
	return Value_As_String(value)
}

Ctx_Vec2 :: proc(ctx: ^Eval_Context, name: string) -> (Core.Vec2, bool) {
	value, found := Ctx_Input(ctx, name)
	if !found {return Core.Vec2{}, false}
	return Value_As_Vec2(value)
}

Ctx_Vec3 :: proc(ctx: ^Eval_Context, name: string) -> (Core.Vec3, bool) {
	value, found := Ctx_Input(ctx, name)
	if !found {return Core.Vec3{}, false}
	return Value_As_Vec3(value)
}

Ctx_Config :: proc(ctx: ^Eval_Context, key: string) -> (NG.Graph_Value, bool) {
	if ctx == nil || ctx.config_value == nil {return nil, false}
	return ctx.config_value(ctx, key)
}

Ctx_Config_Text :: proc(ctx: ^Eval_Context, key: string) -> string {
	value, found := Ctx_Config(ctx, key)
	if !found {return ""}
	text, ok := Value_As_String(value)
	if !ok {return ""}
	return text
}

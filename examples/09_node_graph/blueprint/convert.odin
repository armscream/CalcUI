package blueprint

import Core "../../../src/GUI/Core"
import NG "../../../src/GUI/NodeGraph"
import "core:strconv"

Can_Convert :: proc(from_type, to_type: string) -> bool {
	if from_type == "" || to_type == "" {return true}
	if Type_Matches(from_type, to_type) {return true}
	if Type_Matches(from_type, "name") || Type_Matches(to_type, "name") {return false}
	from_kind := Value_Kind_Of_Type(from_type)
	to_kind := Value_Kind_Of_Type(to_type)
	if from_kind == to_kind {return true}
	#partial switch from_kind {
	case .Bool:
		#partial switch to_kind {
		case .Int, .Float: return true
		}
	case .Int:
		#partial switch to_kind {
		case .Bool, .Float: return true
		}
	case .Float:
		#partial switch to_kind {
		case .Bool, .Int, .Vec2, .Vec3: return true
		}
	case .Vec2:
		#partial switch to_kind {
		case .Vec3, .Float: return true
		}
	case .Vec3:
		#partial switch to_kind {
		case .Vec2, .Float: return true
		}
	case .String:
		#partial switch to_kind {
		case .Bool, .Int, .Float: return true
		}
	}
	return false
}

Convert_Value :: proc(value: NG.Graph_Value, target_type: string) -> (NG.Graph_Value, bool) {
	if target_type == "" {return value, true}
	target := Value_Kind_Of_Type(target_type)
	current := NG.Graph_Value_Kind_Of(value)
	if current == target {return value, true}
	#partial switch v in value {
	case bool:
		#partial switch target {
		case .Int:
			if v {return NG.Graph_Value(i32(1)), true}
			return NG.Graph_Value(i32(0)), true
		case .Float:
			if v {return NG.Graph_Value(f32(1)), true}
			return NG.Graph_Value(f32(0)), true
		}
	case i32:
		#partial switch target {
		case .Bool:
			return NG.Graph_Value(v != 0), true
		case .Float:
			return NG.Graph_Value(f32(v)), true
		}
	case f32:
		#partial switch target {
		case .Bool:
			return NG.Graph_Value(v != 0), true
		case .Int:
			return NG.Graph_Value(i32(v)), true
		case .Vec2:
			return NG.Graph_Value(Core.Vec2{v, v}), true
		case .Vec3:
			return NG.Graph_Value(Core.Vec3{v, v, v}), true
		}
	case Core.Vec2:
		#partial switch target {
		case .Vec3:
			return NG.Graph_Value(Core.Vec3{v.x, v.y, 0}), true
		case .Float:
			return NG.Graph_Value(v.x), true
		}
	case Core.Vec3:
		#partial switch target {
		case .Vec2:
			return NG.Graph_Value(Core.Vec2{v.x, v.y}), true
		case .Float:
			return NG.Graph_Value(v.x), true
		}
	case string:
		#partial switch target {
		case .Bool:
			return NG.Graph_Value(len(v) > 0), true
		case .Int:
			number, ok := strconv.parse_int(v)
			if !ok {return nil, false}
			return NG.Graph_Value(i32(number)), true
		case .Float:
			number, ok := strconv.parse_f32(v)
			if !ok {return nil, false}
			return NG.Graph_Value(number), true
		}
	}
	return nil, false
}

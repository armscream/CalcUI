//* == Widget Accessability ==
//* The metadata that says what a widget is to whatever reads the screen
//* for a person who cannot see it: its role, name, value, states and the
//* widgets it is tied to. The core keeps the metadata and hands it out;
//* the platform that talks to the window system does the rest.

package GUI

import "core:fmt"

Access_Role :: enum {
	None,
	Group,
	Panel,
	Label,
	Heading,
	Button,
	Toggle_Button,
	Check_Box,
	Radio_Button,
	Text_Input,
	Password_Input,
	Search_Input,
	Number_Input,
	Slider,
	Spin_Box,
	Progress_Bar,
	Combo_Box,
	List,
	List_Item,
	Tree,
	Tree_Item,
	Table,
	Menu,
	Menu_Bar,
	Menu_Item,
	Tab,
	Tab_List,
	Dialog,
	Window,
	Tooltip,
	Status,
	Image,
	Link,
	Separator,
	Scroll_Bar,
	Canvas,
	Chart,
	Custom,
}

Access_State :: enum {
	Disabled,
	Hidden,
	Focused,
	Selected,
	Expanded,
	Checked,
	Pressed,
	Required,
	Read_Only,
	Multiline,
	Has_Popup,
	Editable,
	Busy,
	Invalid,
}
Access_States :: bit_set[Access_State]

Access_Value :: struct {
	text:    string,
	number:  f64,
	min:     f64,
	max:     f64,
	step:    f64,
	percent: f32,
}

Access_Relation :: enum {
	Labelled_By,
	Described_By,
	Controls,
	Controlled_By,
	Flow_To,
	Flow_From,
	Required_By,
	Required_For,
	Details,
	Details_For,
}

//* A tie between two widgets.
Access_Relation_Entry :: struct {
	kind:   Access_Relation,
	target: Widget_ID,
}

//* How many ties a widget can have.
ACCESS_RELATIONS_MAX :: 8

Access_Info :: struct {
	role:           Access_Role,
	name:           string,
	description:    string,
	value:          Access_Value,
	states:         Access_States,
	role_set:       bool,
	name_set:       bool,
	value_set:      bool,
	relations:      [ACCESS_RELATIONS_MAX]Access_Relation_Entry,
	relation_count: int,
}

Access_Node :: struct {
	id:             Widget_ID,
	role:           Access_Role,
	name:           string,
	description:    string,
	value:          Access_Value,
	states:         Access_States,
	parent:         Widget_ID,
	depth:          int,
	relations:      [ACCESS_RELATIONS_MAX]Access_Relation_Entry,
	relation_count: int,
}

//* What the platform has to be told. The core calls these when the tree
//* of the widgets changes; a platform that has no accessibility of its
//* own leaves them nil.
Access_Bridge :: struct {
	ctx:           rawptr,
	node_added:    proc(ctx: rawptr, node: Access_Node),
	node_changed:  proc(ctx: rawptr, node: Access_Node),
	node_removed:  proc(ctx: rawptr, id: Widget_ID),
	focus_changed: proc(ctx: rawptr, focused: Widget_ID),
}

GUI_Set_Access_Bridge :: proc(g: ^GUI, bridge: Access_Bridge) {
	if g == nil { return }
	g.access_bridge = bridge
	g.access_epoch += 1
}

//* How many times the accessibility of the GUI changed. A platform that
//* has no bridge of its own can look at this number and rebuild when it went up.
GUI_Access_Epoch :: proc(g: ^GUI) -> int {
	if g == nil { return 0 }
	return g.access_epoch
}

access_changed :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	g.access_epoch += 1
	bridge := g.access_bridge
	if bridge.node_changed == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	bridge.node_changed(bridge.ctx, access_node_of(g, id, w))
}

access_focus_changed :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	g.access_epoch += 1
	bridge := g.access_bridge
	if bridge.focus_changed == nil { return }
	bridge.focus_changed(bridge.ctx, id)
}

//* The role a widget has when the program says nothing about it.
access_role_of :: proc(g: ^GUI, w: ^Widget) -> Access_Role {
	if w == nil { return .None }
	if w.access.role_set { return w.access.role }
	if w.class != INVALID_WIDGET_CLASS_ID {
		if c, ok := class_get(g, w.class); ok && c.access_role != .None {
			return c.access_role
		}
	}
	if kind := widget_kind(g, w); kind.access_role != .None {
		return kind.access_role
	}
	#partial switch w.type {
	case .Button: return .Button
	case .CheckBox: return .Check_Box
	case .CheckButton: return .Toggle_Button
	case .ToggleSwitch: return .Toggle_Button
	case .OptionButton: return .Combo_Box
	case .ComboBox: return .Combo_Box
	case .MenuButton: return .Menu_Bar
	case .LinkButton: return .Link
	case .Label: return .Label
	case .TextInput: return .Text_Input
	case .TextEdit: return .Text_Input
	case .SearchField: return .Search_Input
	case .NumberInput: return .Number_Input
	case .HSlider, .VSlider: return .Slider
	case .SpinBox: return .Spin_Box
	case .ProgressBar: return .Progress_Bar
	case .ItemList, .VirtualList: return .List
	case .Tree: return .Tree
	case .Tabs, .TabContainer: return .Tab_List
	case .PopupMenu, .ContextMenu: return .Menu
	case .AcceptDialog, .ConfirmationDialog, .FileDialog, .CommandPalette: return .Dialog
	case .Toast: return .Status
	case .Tooltip: return .Tooltip
	case .HSeparator, .VSeparator: return .Separator
	case .TextureRect: return .Image
	case .Chart: return .Chart
	case .Canvas: return .Canvas
	case .DataTable: return .Table
	}
	return .Group
}

access_default_name :: proc(w: ^Widget) -> string {
	if w == nil { return "" }
	#partial switch d in w.data {
	case Label_Data:
		if d.text != "" { return d.text }
	case Button_Data:
		if d.text != "" { return d.text }
	case Check_Box_Data:
		if d.text != "" { return d.text }
	case Check_Button_Data:
		if d.text != "" { return d.text }
	case Link_Button_Data:
		if d.text != "" { return d.text }
	case Menu_Button_Data:
		if d.text != "" { return d.text }
	case Toggle_Switch_Data:
		if d.text != "" { return d.text }
	case Rich_Text_Data:
		if d.text != "" { return d.text }
	case Rich_Text_Editor_Data:
		if d.state != nil && d.state.text != "" { return d.state.text }
	}
	return w.name
}

access_default_value :: proc(w: ^Widget) -> Access_Value {
	if w == nil { return {} }
	#partial switch d in w.data {
	case Text_Input_Data:
		return Access_Value{text = d.text}
	case Text_Edit_Data:
		return Access_Value{text = d.text}
	case Search_Field_Data:
		return Access_Value{text = d.text}
	case Slider_Data:
		return Access_Value{number = f64(d.value), min = f64(d.min), max = f64(d.max), step = f64(d.step)}
	case Progress_Bar_Data:
		percent := f32(0)
		if d.max > 0 { percent = d.value / d.max }
		return Access_Value{number = f64(d.value), max = f64(d.max), percent = percent}
	case Check_Box_Data:
		return Access_Value{text = bool_text(d.on)}
	case Check_Button_Data:
		return Access_Value{text = bool_text(d.on)}
	case Toggle_Switch_Data:
		return Access_Value{text = bool_text(d.on)}
	}
	return {}
}

bool_text :: proc(on: bool) -> string {
	return on ? "on" : "off"
}

Widget_Access_Info :: proc(g: ^GUI, id: Widget_ID) -> Access_Info {
	w := Widget_Get(g, id)
	if w == nil { return {} }
	info := w.access
	if !info.role_set { info.role = access_role_of(g, w) }
	if !info.name_set { info.name = access_default_name(w) }
	if !info.value_set { info.value = access_default_value(w) }
	if !(.Enabled in w.state) { info.states += Access_States{.Disabled} }
	if !(.Visible in w.state) { info.states += Access_States{.Hidden} }
	if g.focused == id { info.states += Access_States{.Focused} }
	if g.active == id { info.states += Access_States{.Pressed} }
	if kind := widget_kind(g, w); kind.access != nil {
		kind.access(g, id, w, &info)
	}
	return info
}

//* Sets the role of a widget: what it is to whatever reads the screen.
//* A role of .None takes the role of the program away, and the widget
//* falls back on the role of its kind.
Widget_Set_Access_Role :: proc(g: ^GUI, id: Widget_ID, role: Access_Role) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if role == .None {
		if !w.access.role_set { return }
		w.access.role = .None
		w.access.role_set = false
		access_changed(g, id)
		return
	}
	if w.access.role_set && w.access.role == role { return }
	w.access.role = role
	w.access.role_set = true
	access_changed(g, id)
}

//* Sets the name of a widget: the name it is known by. A widget without
//* a name of its own is known by its text.
Widget_Set_Access_Name :: proc(g: ^GUI, id: Widget_ID, name: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.access.name_set && w.access.name == name { return }
	w.access.name = name
	w.access.name_set = true
	access_changed(g, id)
}

//* Sets the text hint.
Widget_Set_Access_Description :: proc(g: ^GUI, id: Widget_ID, description: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.access.description == description { return }
	w.access.description = description
	access_changed(g, id)
}

Widget_Set_Access_Value :: proc(g: ^GUI, id: Widget_ID, value: Access_Value) {
	w := Widget_Get(g, id)
	if w == nil { return }
	w.access.value = value
	w.access.value_set = true
	access_changed(g, id)
}

Widget_Set_Access_State :: proc(g: ^GUI, id: Widget_ID, state: Access_State, on: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	before := w.access.states
	if on {
		w.access.states += Access_States{state}
	} else {
		w.access.states -= Access_States{state}
	}
	if before == w.access.states { return }
	access_changed(g, id)
}

//* Ties a widget to another one: the label of a widget, the widget a
//* dialog controls, the widget the focus goes to after this one.
Widget_Set_Access_Relation :: proc(g: ^GUI, id: Widget_ID, kind: Access_Relation, target: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	for i in 0 ..< w.access.relation_count {
		entry := w.access.relations[i]
		if entry.kind == kind && entry.target == target { return }
	}
	if w.access.relation_count >= ACCESS_RELATIONS_MAX { return }
	w.access.relations[w.access.relation_count] = Access_Relation_Entry{kind = kind, target = target}
	w.access.relation_count += 1
	access_changed(g, id)
}

Widget_Clear_Access_Relation :: proc(g: ^GUI, id: Widget_ID, kind: Access_Relation, target: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	for i := w.access.relation_count - 1; i >= 0; i -= 1 {
		entry := w.access.relations[i]
		if entry.kind != kind || entry.target != target { continue }
		for j := i; j < w.access.relation_count - 1; j += 1 {
			w.access.relations[j] = w.access.relations[j + 1]
		}
		w.access.relation_count -= 1
		w.access.relations[w.access.relation_count] = Access_Relation_Entry{}
	}
	access_changed(g, id)
}

access_node_of :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) -> Access_Node {
	info := Widget_Access_Info(g, id)
	node := Access_Node{
		id = id,
		role = info.role,
		name = info.name,
		description = info.description,
		value = info.value,
		states = info.states,
		parent = w.parent,
		relations = info.relations,
		relation_count = info.relation_count,
	}
	return node
}

//* The widgets of the tree, from the top down. A widget that is not
//* shown is left out, and so is everything under it.
Access_Collect :: proc(g: ^GUI, out: ^[dynamic]Access_Node) {
	if g == nil { return }
	access_walk(g, g.root, 0, out)
}

//* The widgets of a floating panel, from the top down.
Access_Collect_Float :: proc(g: ^GUI, float_index: int, out: ^[dynamic]Access_Node) {
	if g == nil { return }
	if float_index < 0 || float_index >= len(g.floats) { return }
	access_walk(g, g.floats[float_index].widget, 0, out)
}

access_walk :: proc(g: ^GUI, id: Widget_ID, depth: int, out: ^[dynamic]Access_Node) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if !(.Visible in w.state) { return }
	node := access_node_of(g, id, w)
	node.depth = depth
	append(out, node)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		next := c.next_sibling
		access_walk(g, child, depth + 1, out)
		child = next
	}
}

Access_Role_Name :: proc(role: Access_Role) -> string {
	name, ok := fmt.enum_value_to_string(role)
	if !ok { return "" }
	return name
}

Access_State_Name :: proc(state: Access_State) -> string {
	name, ok := fmt.enum_value_to_string(state)
	if !ok { return "" }
	return name
}

Access_Relation_Name :: proc(relation: Access_Relation) -> string {
	name, ok := fmt.enum_value_to_string(relation)
	if !ok { return "" }
	return name
}

//* The value of a widget as text.
Access_Value_Text :: proc(value: Access_Value) -> string {
	if value.text != "" { return value.text }
	if value.number != 0 { return fmt.tprintf("%g", value.number) }
	return ""
}

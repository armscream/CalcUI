//* == Widget Accessability ==
//* The metadata that says what a widget is to whatever reads the screen
//* for a person who cannot see it: its role, name, value, states and the
//* widgets it is tied to. The core keeps the metadata and hands it out;
//* the platform that talks to the window system does the rest.

package Core
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:sync"

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
	native:         rawptr,
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
	frame:         proc(ctx: rawptr),
}

Access_Native :: struct {
	available: bool,
	start:     proc(tree: ^Access_Tree) -> bool,
	stop:      proc(tree: ^Access_Tree),
	create:    proc(tree: ^Access_Tree, node: ^Access_Node) -> rawptr,
	update:    proc(tree: ^Access_Tree, node: ^Access_Node),
	destroy:   proc(tree: ^Access_Tree, node: ^Access_Node),
	focus:     proc(tree: ^Access_Tree, id: Widget_ID),
	frame:     proc(tree: ^Access_Tree),
}

access_bridge_ready :: proc(g: ^GUI) -> bool {
	if g == nil { return false }
	bridge := g.access_bridge
	return bridge.node_added != nil || bridge.node_changed != nil || bridge.node_removed != nil
}

access_queue :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.access_queued { return }
	w.access_queued = true
	append(&g.access_pending, id)
}

access_mark :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	if !access_bridge_ready(g) { return }
	access_queue(g, id)
	g.access_epoch += 1
}

access_removed :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if !w.access_in_bridge { return }
	w.access_in_bridge = false
	bridge := g.access_bridge
	if bridge.node_removed != nil { bridge.node_removed(bridge.ctx, id) }
	g.access_epoch += 1
}

Access_Sync :: proc(g: ^GUI) {
	if g == nil { return }
	bridge := g.access_bridge
	if len(g.access_pending) != 0 {
		pending := g.access_pending
		g.access_pending = g.access_spare
		g.access_spare = pending
		clear(&g.access_spare)
		for id in pending {
			w := Widget_Get(g, id)
			if w == nil { continue }
			w.access_queued = false
			node := access_node_of(g, id, w)
			if !w.access_in_bridge {
				w.access_in_bridge = true
				if bridge.node_added != nil { bridge.node_added(bridge.ctx, node) }
			} else if bridge.node_changed != nil {
				bridge.node_changed(bridge.ctx, node)
			}
		}
	}
	if bridge.frame != nil { bridge.frame(bridge.ctx) }
}

GUI_Set_Access_Bridge :: proc(g: ^GUI, bridge: Access_Bridge) {
	if g == nil { return }
	g.access_bridge = bridge
	g.access_epoch += 1
	for w in g.widgets {
		if w == nil { continue }
		w.access_in_bridge = false
		w.access_queued = false
	}
	clear(&g.access_pending)
	for w in g.widgets {
		if w == nil { continue }
		access_queue(g, w.id)
	}
}

//* has no bridge of its own can look at this number and rebuild when it went up.
GUI_Access_Epoch :: proc(g: ^GUI) -> int {
	if g == nil { return 0 }
	return g.access_epoch
}

access_changed :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	access_mark(g, id)
}

access_mark_subtree :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil || !access_bridge_ready(g) { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	access_mark(g, id)
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		next := c.next_sibling
		access_mark_subtree(g, child)
		child = next
	}
}

access_focus_changed :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	g.access_epoch += 1
	bridge := g.access_bridge
	if bridge.focus_changed == nil { return }
	bridge.focus_changed(bridge.ctx, id)
}


widget_access :: proc(g: ^GUI, w: ^Widget) -> ^Access_Info {
	if w == nil { return nil }
	if w.access == nil {
		if g == nil { return nil }
		w.access = new(Access_Info)
		if w.access == nil { return nil }
	}
	return w.access
}

access_role_of :: proc(g: ^GUI, w: ^Widget) -> Access_Role {
	if w == nil { return .None }
	if w.access != nil && w.access.role_set { return w.access.role }
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
	case .ToggleSwitch: return .Toggle_Button
	case .OptionButton: return .Combo_Box
	case .ComboBox: return .Combo_Box
	case .MenuButton: return .Menu_Bar
	case .LinkButton: return .Link
	case .Label: return .Label
	case .TextBox: return .Text_Input
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
	case Text_Box_Data:
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
	case Toggle_Switch_Data:
		return Access_Value{text = bool_text(d.on)}
	case Spin_Box_Data:
		return Access_Value{number = f64(d.value), min = f64(d.min), max = f64(d.max), step = f64(d.step)}
	case Number_Input_Data:
		return Access_Value{number = f64(d.value), min = f64(d.min), max = f64(d.max), step = f64(d.step)}
	case Rating_Data:
		return Access_Value{number = f64(d.value), max = f64(d.max)}
	case Combo_Box_Data:
		if d.selected >= 0 && d.selected < len(d.items) {
			return Access_Value{text = d.items[d.selected].text}
		}
	case Option_Button_Data:
		if d.active >= 0 && d.active < len(d.items) {
			return Access_Value{text = d.items[d.active]}
		}
	case Segmented_Data:
		if d.selected >= 0 && d.selected < len(d.items) {
			return Access_Value{text = d.items[d.selected].text}
		}
	case Item_List_Data:
		if d.selected >= 0 && d.selected < len(d.items) {
			return Access_Value{text = d.items[d.selected].text}
		}
	case Tree_Data:
		if d.selected >= 0 && d.selected < len(d.items) {
			return Access_Value{text = d.items[d.selected].text}
		}
	case Popup_Menu_Data:
		if d.selected >= 0 && d.selected < len(d.items) {
			return Access_Value{text = d.items[d.selected].text}
		}
	case Context_Menu_Data:
		if d.selected >= 0 && d.selected < len(d.items) {
			return Access_Value{text = d.items[d.selected].text}
		}
	case Color_Picker_Data:
		return Access_Value{text = fmt.tprintf("#%02X%02X%02X", u8(d.colour.r * 255), u8(d.colour.g * 255), u8(d.colour.b * 255))}
	case Date_Picker_Data:
		return Access_Value{text = fmt.tprintf("%04d-%02d-%02d", d.year, d.month, d.day)}
	case Time_Picker_Data:
		return Access_Value{text = fmt.tprintf("%02d:%02d", d.hour, d.minute)}
	}
	return {}
}

access_apply_state :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, info: ^Access_Info) {
	if w == nil || info == nil { return }
	#partial switch d in w.data {
	case Check_Box_Data:
		if d.on { info.states += Access_States{.Checked} }
	case Toggle_Switch_Data:
		if d.on { info.states += Access_States{.Checked} }
	case Combo_Box_Data:
		info.states += Access_States{.Has_Popup}
		if d.selected >= 0 { info.states += Access_States{.Selected} }
	case Option_Button_Data:
		info.states += Access_States{.Has_Popup}
		if d.active >= 0 { info.states += Access_States{.Selected} }
	case Menu_Button_Data:
		info.states += Access_States{.Has_Popup}
	case Segmented_Data:
		if d.selected >= 0 { info.states += Access_States{.Selected} }
	case Item_List_Data:
		if d.selected >= 0 { info.states += Access_States{.Selected} }
	case Tree_Data:
		if d.selected >= 0 { info.states += Access_States{.Selected} }
	case Popup_Menu_Data:
		if d.selected >= 0 { info.states += Access_States{.Selected} }
	case Context_Menu_Data:
		if d.selected >= 0 { info.states += Access_States{.Selected} }
	case Tabs_Data:
		if d.active >= 0 { info.states += Access_States{.Selected} }
	case Tab_Container_Data:
		if d.active >= 0 { info.states += Access_States{.Selected} }
	case Accordion_Data:
		if d.open >= 0 { info.states += Access_States{.Expanded} }
	case Text_Box_Data:
		if .Multiline in d.flags { info.states += Access_States{.Multiline} }
		info.states += Access_States{.Editable}
	case Search_Field_Data:
		info.states += Access_States{.Editable}
	case Number_Input_Data:
		if d.editing { info.states += Access_States{.Editable} }
	case Chat_Input_Data:
		info.states += Access_States{.Editable, .Multiline}
	case Rich_Text_Editor_Data:
		info.states += Access_States{.Editable, .Multiline}
	case Command_Palette_Data:
		info.states += Access_States{.Editable}
	}
}

bool_text :: proc(on: bool) -> string {
	return on ? "on" : "off"
}

Widget_Access_Info :: proc(g: ^GUI, id: Widget_ID) -> Access_Info {
	w := Widget_Get(g, id)
	if w == nil { return {} }
	info: Access_Info
	if w.access != nil { info = w.access^ }
	if !info.role_set { info.role = access_role_of(g, w) }
	if !info.name_set { info.name = access_default_name(w) }
	if !info.value_set { info.value = access_default_value(w) }
	if !(.Enabled in w.state) { info.states += Access_States{.Disabled} }
	if !widget_is_shown(g, id) { info.states += Access_States{.Hidden} }
	if g.focused == id { info.states += Access_States{.Focused} }
	if g.active == id && w.interactive { info.states += Access_States{.Pressed} }
	access_apply_state(g, id, w, &info)
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
		if w.access == nil || !w.access.role_set { return }
		w.access.role = .None
		w.access.role_set = false
		access_changed(g, id)
		return
	}
	if w.access != nil && w.access.role_set && w.access.role == role { return }
	a := widget_access(g, w)
	if a == nil { return }
	a.role = role
	a.role_set = true
	access_changed(g, id)
}

//* Sets the name of a widget: the name it is known by. A widget without
//* a name of its own is known by its text.
Widget_Set_Access_Name :: proc(g: ^GUI, id: Widget_ID, name: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.access != nil && w.access.name_set && w.access.name == name { return }
	a := widget_access(g, w)
	if a == nil { return }
	a.name = name
	a.name_set = true
	access_changed(g, id)
}

//* Sets the text hint.
Widget_Set_Access_Description :: proc(g: ^GUI, id: Widget_ID, description: string) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.access != nil && w.access.description == description { return }
	a := widget_access(g, w)
	if a == nil { return }
	a.description = description
	access_changed(g, id)
}

Widget_Set_Access_Value :: proc(g: ^GUI, id: Widget_ID, value: Access_Value) {
	w := Widget_Get(g, id)
	if w == nil { return }
	a := widget_access(g, w)
	if a == nil { return }
	a.value = value
	a.value_set = true
	access_changed(g, id)
}

Widget_Set_Access_State :: proc(g: ^GUI, id: Widget_ID, state: Access_State, on: bool) {
	w := Widget_Get(g, id)
	if w == nil { return }
	a := widget_access(g, w)
	if a == nil { return }
	before := a.states
	if on {
		a.states += Access_States{state}
	} else {
		a.states -= Access_States{state}
	}
	if before == a.states { return }
	access_changed(g, id)
}

//* Ties a widget to another one: the label of a widget, the widget a
//* dialog controls, the widget the focus goes to after this one.
Widget_Set_Access_Relation :: proc(g: ^GUI, id: Widget_ID, kind: Access_Relation, target: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if w.access != nil {
		for i in 0 ..< w.access.relation_count {
			entry := w.access.relations[i]
			if entry.kind == kind && entry.target == target { return }
		}
		if w.access.relation_count >= ACCESS_RELATIONS_MAX { return }
	}
	a := widget_access(g, w)
	if a == nil { return }
	a.relations[a.relation_count] = Access_Relation_Entry{kind = kind, target = target}
	a.relation_count += 1
	access_changed(g, id)
}

Widget_Clear_Access_Relation :: proc(g: ^GUI, id: Widget_ID, kind: Access_Relation, target: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil || w.access == nil { return }
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

Access_Children :: proc(g: ^GUI, id: Widget_ID, out: ^[dynamic]Widget_ID) {
	if g == nil || out == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	child := w.first_child
	for child != INVALID_WIDGET_ID {
		c := Widget_Get(g, child)
		if c == nil { break }
		append(out, child)
		child = c.next_sibling
	}
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

//* == The platform tree ==
//* The tree the platform reads: a copy of the metadata of the widgets that
//* the core keeps in step, and the actions the platform asks for.

Access_Action_Kind :: enum {
	Focus,
	Set_Value,
	Toggle,
	Invoke,
	Set_Range_Value,
}

Access_Action :: struct {
	kind:  Access_Action_Kind,
	id:    Widget_ID,
	text:  string,
	value: f64,
}

Access_Tree :: struct {
	gui:       ^GUI,
	window:    rawptr,
	nodes:     map[Widget_ID]^Access_Node,
	order:     [dynamic]Widget_ID,
	focused:   Widget_ID,
	bridge:    Access_Bridge,
	hooks:     Access_Native,
	mutex:     sync.Mutex,
	native:    rawptr,
	allocator: mem.Allocator,
	origin:    Rect,
	scale:     f32,
	actions:   [dynamic]Access_Action,
}

Access_Tree_Create :: proc(g: ^GUI, window: rawptr, hooks: Access_Native) -> ^Access_Tree {
	tree := new(Access_Tree)
	tree.gui = g
	tree.window = window
	tree.hooks = hooks
	tree.nodes = make(map[Widget_ID]^Access_Node)
	tree.order = make([dynamic]Widget_ID)
	tree.focused = INVALID_WIDGET_ID
	tree.allocator = context.allocator
	if g != nil {
		tree.origin = g.window_rect
		tree.scale = g.scale
	}
	tree.bridge = Access_Bridge {
		ctx           = cast(rawptr) tree,
		node_added    = access_bridge_node_added,
		node_changed  = access_bridge_node_changed,
		node_removed  = access_bridge_node_removed,
		focus_changed = access_bridge_focus_changed,
		frame         = access_bridge_frame,
	}
	return tree
}

Access_Tree_Destroy :: proc(tree: ^Access_Tree) {
	if tree == nil { return }
	previous := context
	context = runtime.default_context()
	context.allocator = access_tree_allocator(tree)
	defer context = previous
	hooks := tree.hooks
	sync.mutex_lock(&tree.mutex)
	for id in tree.order {
		entry := access_tree_node_find_locked(tree, id)
		if entry == nil { continue }
		if hooks.destroy != nil { hooks.destroy(tree, entry) }
		free(entry, access_tree_allocator(tree))
	}
	for action in tree.actions {
		if action.text != "" { free(raw_data(action.text), access_tree_allocator(tree)) }
	}
	sync.mutex_unlock(&tree.mutex)
	delete(tree.nodes)
	delete(tree.order)
	delete(tree.actions)
	free(tree)
}

access_tree_allocator :: proc(tree: ^Access_Tree) -> mem.Allocator {
	if tree != nil && tree.allocator.procedure != nil { return tree.allocator }
	return context.allocator
}


access_tree_node_count :: proc(tree: ^Access_Tree) -> int {
	if tree == nil { return 0 }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	return len(tree.order)
}

access_tree_node_info :: proc(tree: ^Access_Tree, id: Widget_ID) -> Access_Node {
	if tree == nil { return Access_Node{} }
	sync.mutex_lock(&tree.mutex)
	node := access_tree_node_find_locked(tree, id)
	if node == nil {
		sync.mutex_unlock(&tree.mutex)
		return Access_Node{}
	}
	result := node^
	result.native = nil
	sync.mutex_unlock(&tree.mutex)
	result.parent = access_tree_parent_of(tree, id)
	return result
}

access_tree_node_upsert :: proc(tree: ^Access_Tree, node: Access_Node) {
	if tree == nil { return }
	hooks := tree.hooks
	sync.mutex_lock(&tree.mutex)
	entry := access_tree_node_find_locked(tree, node.id)
	if entry == nil {
		entry = new(Access_Node, access_tree_allocator(tree))
		entry.id = node.id
		tree.nodes[node.id] = entry
		append(&tree.order, node.id)
	}
	access_tree_node_copy(entry, node)
	created := entry.native == nil && hooks.create != nil
	if created {
		entry.native = hooks.create(tree, entry)
	}
	sync.mutex_unlock(&tree.mutex)
	if hooks.update != nil && !created { hooks.update(tree, entry) }
}

access_bridge_node_added :: proc(ctx: rawptr, node: Access_Node) {
	access_tree_node_upsert(cast(^Access_Tree)ctx, node)
}

access_bridge_node_changed :: proc(ctx: rawptr, node: Access_Node) {
	access_tree_node_upsert(cast(^Access_Tree)ctx, node)
}

access_bridge_node_removed :: proc(ctx: rawptr, id: Widget_ID) {
	tree := cast(^Access_Tree)ctx
	if tree == nil { return }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	entry := access_tree_node_find_locked(tree, id)
	if entry == nil { return }
	if tree.hooks.destroy != nil { tree.hooks.destroy(tree, entry) }
	free(entry, access_tree_allocator(tree))
	delete_key(&tree.nodes, id)
	for i := len(tree.order) - 1; i >= 0; i -= 1 {
		if tree.order[i] == id {
			ordered_remove(&tree.order, i)
			break
		}
	}
}

access_bridge_frame :: proc(ctx: rawptr) {
	tree := cast(^Access_Tree)ctx
	if tree == nil { return }
	if tree.hooks.frame != nil { tree.hooks.frame(tree) }
}

access_bridge_focus_changed :: proc(ctx: rawptr, focused: Widget_ID) {
	tree := cast(^Access_Tree)ctx
	if tree == nil { return }
	sync.mutex_lock(&tree.mutex)
	tree.focused = focused
	sync.mutex_unlock(&tree.mutex)
	if tree.hooks.focus != nil { tree.hooks.focus(tree, focused) }
}

access_tree_node_find_locked :: proc(tree: ^Access_Tree, id: Widget_ID) -> ^Access_Node {
	if tree == nil { return nil }
	entry, found := tree.nodes[id]
	if !found { return nil }
	return entry
}

access_tree_node_find :: proc(tree: ^Access_Tree, id: Widget_ID) -> ^Access_Node {
	if tree == nil { return nil }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	return access_tree_node_find_locked(tree, id)
}

access_tree_node_of :: proc(tree: ^Access_Tree, id: Widget_ID) -> ^Access_Node {
	return access_tree_node_find(tree, id)
}

access_tree_node_copy :: proc(entry: ^Access_Node, node: Access_Node) {
	if entry == nil { return }
	entry.role = node.role
	entry.name = node.name
	entry.description = node.description
	entry.value = node.value
	entry.states = node.states
	entry.relation_count = node.relation_count
	if node.relation_count > 0 {
		entry.relations = node.relations
	}
}

access_tree_parent_of :: proc(tree: ^Access_Tree, id: Widget_ID) -> Widget_ID {
	if tree == nil || tree.gui == nil { return INVALID_WIDGET_ID }
	w := Widget_Get(tree.gui, id)
	if w == nil { return INVALID_WIDGET_ID }
	return w.parent
}

access_tree_children_of :: proc(tree: ^Access_Tree, id: Widget_ID, out: ^[dynamic]Widget_ID) -> int {
	if tree == nil || tree.gui == nil || out == nil { return 0 }
	clear(out)
	Access_Children(tree.gui, id, out)
	return len(out)
}

//* == The platform bridge ==
//* A platform registers its hooks once, then the program uses these callables.

access_native_hooks: Access_Native

Access_Use_Native :: proc(hooks: Access_Native) {
	access_native_hooks = hooks
}

Access_Available :: proc() -> bool {
	return access_native_hooks.available
}

Access_Install :: proc(g: ^GUI, window: rawptr) -> bool {
	if g == nil { return false }
	hooks := access_native_hooks
	if !hooks.available { return false }
	Access_Remove(g)
	tree := Access_Tree_Create(g, window, hooks)
	g.access_tree = tree
	if hooks.start != nil && !hooks.start(tree) {
		g.access_tree = nil
		Access_Tree_Destroy(tree)
		return false
	}
	GUI_Set_Access_Bridge(g, tree.bridge)
	return true
}

Access_Remove :: proc(g: ^GUI) {
	if g == nil { return }
	tree := g.access_tree
	g.access_tree = nil
	if tree == nil { return }
	GUI_Set_Access_Bridge(g, Access_Bridge{})
	if tree.hooks.stop != nil { tree.hooks.stop(tree) }
	Access_Tree_Destroy(tree)
}

Access_Apply_Actions :: proc(g: ^GUI) {
	if g == nil || g.access_tree == nil { return }
	access_apply_actions(g.access_tree)
}

Access_Node_Count :: proc(g: ^GUI) -> int {
	if g == nil || g.access_tree == nil { return 0 }
	return access_tree_node_count(g.access_tree)
}

Access_Node_Info :: proc(g: ^GUI, id: Widget_ID) -> Access_Node {
	if g == nil || g.access_tree == nil { return Access_Node{} }
	return access_tree_node_info(g.access_tree, id)
}

access_queue_action :: proc(tree: ^Access_Tree, action: Access_Action) {
	if tree == nil { return }
	previous := context
	context = runtime.default_context()
	context.allocator = access_tree_allocator(tree)
	defer context = previous
	sync.mutex_lock(&tree.mutex)
	append(&tree.actions, action)
	sync.mutex_unlock(&tree.mutex)
}

access_apply_actions :: proc(tree: ^Access_Tree) {
	if tree == nil { return }
	tree_allocator := access_tree_allocator(tree)
	previous := context
	context = runtime.default_context()
	context.allocator = tree_allocator
	sync.mutex_lock(&tree.mutex)
	if tree.gui != nil {
		tree.origin = tree.gui.window_rect
		tree.scale = tree.gui.scale
	}
	pending := tree.actions
	tree.actions = make([dynamic]Access_Action)
	sync.mutex_unlock(&tree.mutex)
	context = previous
	if len(pending) > 0 {
		defer free(raw_data(pending), tree_allocator)
	}
	gui := tree.gui
	if gui == nil {
		for action in pending {
			if action.text != "" { free(raw_data(action.text), tree_allocator) }
		}
		return
	}
	for action in pending {
		switch action.kind {
		case .Focus:
			Focus_Set(gui, action.id)
		case .Set_Value:
			Widget_Set_Text(gui, action.id, action.text)
		case .Toggle:
			if w := Widget_Get(gui, action.id); w != nil {
				#partial switch d in w.data {
				case Check_Box_Data:
					check_box_set(gui, action.id, !d.on)
				case Toggle_Switch_Data:
					toggle_switch_set(gui, action.id, !d.on)
				}
			}
		case .Invoke:
			Widget_Activate(gui, action.id)
		case .Set_Range_Value:
			slider_set_value(gui, action.id, f32(action.value))
		}
		if action.text != "" { free(raw_data(action.text), tree_allocator) }
	}
}

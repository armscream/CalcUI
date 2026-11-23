#+build windows
package Accessibility

import "core:dynlib"
import "core:mem"
import "base:runtime"
import "core:strings"
import "core:sync"
import Core "../Core"
import sdl "vendor:sdl3"
import "core:sys/windows"

HRESULT :: i32

S_OK :: 0
S_FALSE :: 1
E_NOTIMPL :: -2147467263
E_NOINTERFACE :: -2147467262
E_POINTER :: -2147467261
E_FAIL :: -2147467259
E_INVALIDARG :: -2147024809
E_OUTOFMEMORY :: -2147024882

GUID :: struct {
	data1: u32,
	data2: u16,
	data3: u16,
	data4: [8]u8,
}

IID_IUnknown :: GUID{0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
IID_Raw_Provider :: GUID{0xD6DD68D1, 0x86FD, 0x4332, {0x86, 0x66, 0x9A, 0xBE, 0xDE, 0xA2, 0xD2, 0x4C}}
IID_Raw_Fragment :: GUID{0xF7063DA8, 0x8359, 0x439C, {0x92, 0x97, 0xBB, 0xC5, 0x29, 0x9A, 0x7D, 0x87}}
IID_Raw_Fragment_Root :: GUID{0x620CE2A5, 0xAB8F, 0x40A9, {0x86, 0xCB, 0xDE, 0x3C, 0x75, 0x59, 0x9B, 0x58}}
IID_Value_Provider :: GUID{0xC7935180, 0x6FB3, 0x4201, {0xB1, 0x74, 0x7D, 0xF7, 0x3A, 0xD8, 0xBF, 0x64}}
IID_Toggle_Provider :: GUID{0x56D00BD0, 0xC4F4, 0x433C, {0xA8, 0x36, 0x1A, 0x52, 0xA5, 0x7E, 0x08, 0x92}}
IID_Invoke_Provider :: GUID{0x54FCB24B, 0xE18E, 0x47A2, {0xB4, 0xD3, 0xEC, 0xCB, 0xE7, 0x75, 0x29, 0xA2}}
IID_Range_Provider :: GUID{0x36DC7AEF, 0x33E6, 0x4691, {0xAF, 0xE1, 0x2B, 0xE7, 0x27, 0x4B, 0x3D, 0x33}}

VT_EMPTY :: 0
VT_I4 :: 3
VT_R8 :: 5
VT_BSTR :: 8
VT_BOOL :: 11
VT_UNKNOWN :: 13

VARIANT_TRUE :: -1
VARIANT_FALSE :: 0

Variant_Value :: struct {
	double: f64,
	rest:   [8]u8,
}

VARIANT :: struct {
	vt:         u16,
	_reserved1: u16,
	_reserved2: u16,
	_reserved3: u16,
	value:      Variant_Value,
}

variant_int :: proc(v: ^VARIANT) -> ^i32 {
	return cast(^i32)(&v.value.double)
}

variant_bool :: proc(v: ^VARIANT) -> ^i16 {
	return cast(^i16)(&v.value.double)
}

variant_pointer :: proc(v: ^VARIANT) -> ^rawptr {
	return cast(^rawptr)(&v.value.double)
}

CP_UTF8 :: 65001

UIA_ButtonControlTypeId :: 50000
UIA_CheckBoxControlTypeId :: 50002
UIA_ComboBoxControlTypeId :: 50003
UIA_EditControlTypeId :: 50004
UIA_HyperlinkControlTypeId :: 50005
UIA_ImageControlTypeId :: 50006
UIA_ListItemControlTypeId :: 50007
UIA_ListControlTypeId :: 50008
UIA_MenuControlTypeId :: 50009
UIA_MenuBarControlTypeId :: 50010
UIA_MenuItemControlTypeId :: 50011
UIA_ProgressBarControlTypeId :: 50012
UIA_RadioButtonControlTypeId :: 50013
UIA_ScrollBarControlTypeId :: 50014
UIA_SliderControlTypeId :: 50015
UIA_SpinnerControlTypeId :: 50016
UIA_StatusBarControlTypeId :: 50017
UIA_TabControlTypeId :: 50018
UIA_TabItemControlTypeId :: 50019
UIA_TextControlTypeId :: 50020
UIA_ToolBarControlTypeId :: 50021
UIA_ToolTipControlTypeId :: 50022
UIA_TreeControlTypeId :: 50023
UIA_TreeItemControlTypeId :: 50024
UIA_CustomControlTypeId :: 50025
UIA_GroupControlTypeId :: 50026
UIA_DataGridControlTypeId :: 50028
UIA_DocumentControlTypeId :: 50030
UIA_WindowControlTypeId :: 50032
UIA_PaneControlTypeId :: 50033
UIA_TableControlTypeId :: 50036
UIA_SeparatorControlTypeId :: 50038

UIA_BoundingRectanglePropertyId :: 30001
UIA_ProcessIdPropertyId :: 30002
UIA_ControlTypePropertyId :: 30003
UIA_LocalizedControlTypePropertyId :: 30004
UIA_NamePropertyId :: 30005
UIA_HasKeyboardFocusPropertyId :: 30008
UIA_IsKeyboardFocusablePropertyId :: 30009
UIA_IsEnabledPropertyId :: 30010
UIA_AutomationIdPropertyId :: 30011
UIA_ClassNamePropertyId :: 30012
UIA_HelpTextPropertyId :: 30013
UIA_IsControlElementPropertyId :: 30016
UIA_IsContentElementPropertyId :: 30017
UIA_IsPasswordPropertyId :: 30019
UIA_NativeWindowHandlePropertyId :: 30020
UIA_IsOffscreenPropertyId :: 30022
UIA_FrameworkIdPropertyId :: 30024
UIA_IsRequiredForFormPropertyId :: 30025
UIA_IsInvokePatternAvailablePropertyId :: 30031
UIA_IsRangeValuePatternAvailablePropertyId :: 30033
UIA_IsSelectionItemPatternAvailablePropertyId :: 30036
UIA_IsTogglePatternAvailablePropertyId :: 30041
UIA_IsValuePatternAvailablePropertyId :: 30043
UIA_ValueValuePropertyId :: 30045
UIA_ValueIsReadOnlyPropertyId :: 30046
UIA_RangeValueValuePropertyId :: 30047
UIA_RangeValueIsReadOnlyPropertyId :: 30048
UIA_RangeValueMinimumPropertyId :: 30049
UIA_RangeValueMaximumPropertyId :: 30050
UIA_RangeValueLargeChangePropertyId :: 30051
UIA_RangeValueSmallChangePropertyId :: 30052
UIA_SelectionItemIsSelectedPropertyId :: 30079
UIA_ToggleToggleStatePropertyId :: 30086

UIA_InvokePatternId :: 10000
UIA_ValuePatternId :: 10002
UIA_RangeValuePatternId :: 10003
UIA_TogglePatternId :: 10015

UIA_AutomationFocusChangedEventId :: 20011
UIA_AutomationNameChangedEventId :: 20013
UIA_AutomationValueChangedEventId :: 20018

WM_GETOBJECT :: 0x003D
UIA_ROOT_OBJECT_ID :: -25


foreign import OleAut32 "system:OleAut32.lib"

@(default_calling_convention = "system")
foreign OleAut32 {
	SysAllocString :: proc(psz: rawptr) -> rawptr ---
	SysFreeString :: proc(bstr: rawptr) ---
}

Uia_Event :: proc "system" (provider: rawptr, id: i32) -> HRESULT
Uia_Property_Event :: proc "system" (provider: rawptr, property: i32, old: VARIANT, new: VARIANT) -> HRESULT

uia_event_ready: bool
uia_event: Uia_Event
uia_property_event_ready: bool
uia_property_event: Uia_Property_Event

Uia_Node :: struct {
	id:             Core.Widget_ID,
	role:           Core.Access_Role,
	name:           string,
	description:    string,
	value:          Core.Access_Value,
	states:         Core.Access_States,
	relations:      [Core.ACCESS_RELATIONS_MAX]Core.Access_Relation_Entry,
	relation_count: int,
	parent:         Core.Widget_ID,
	children:       []Core.Widget_ID,
	rect:           Core.Rect,
	can_focus:      bool,
	automation_id:  string,
	alive:          bool,
}

Uia_Object :: struct {
	tree:         ^Access_Tree,
	allocator:    mem.Allocator,
	node:         Uia_Node,
	refs:         i32,
	provider:     ^Uia_Provider,
	fragment:     ^Uia_Fragment,
	fragment_root: ^Uia_Fragment_Root,
	value:        ^Uia_Value,
	toggle:       ^Uia_Toggle,
	invoke:       ^Uia_Invoke,
	range:        ^Uia_Range,
}

Uia_Provider :: struct {
	vtbl:   ^Provider_Vtbl,
	object: ^Uia_Object,
}

Uia_Fragment :: struct {
	vtbl:   ^Fragment_Vtbl,
	object: ^Uia_Object,
}

Uia_Fragment_Root :: struct {
	vtbl:   ^Fragment_Root_Vtbl,
	object: ^Uia_Object,
}

Uia_Value :: struct {
	vtbl:   ^Value_Vtbl,
	object: ^Uia_Object,
}

Uia_Toggle :: struct {
	vtbl:   ^Toggle_Vtbl,
	object: ^Uia_Object,
}

Uia_Invoke :: struct {
	vtbl:   ^Invoke_Vtbl,
	object: ^Uia_Object,
}

Uia_Range :: struct {
	vtbl:   ^Range_Vtbl,
	object: ^Uia_Object,
}

Provider_Vtbl :: struct {
	QueryInterface:             proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:                     proc "system" (self: rawptr) -> u32,
	Release:                    proc "system" (self: rawptr) -> u32,
	get_ProviderOptions:        proc "system" (self: rawptr, out: ^u32) -> HRESULT,
	GetPatternProvider:         proc "system" (self: rawptr, pattern: i32, out: ^rawptr) -> HRESULT,
	GetPropertyValue:           proc "system" (self: rawptr, id: i32, out: ^VARIANT) -> HRESULT,
	get_HostRawElementProvider: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT,
}

Fragment_Vtbl :: struct {
	QueryInterface:           proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:                   proc "system" (self: rawptr) -> u32,
	Release:                  proc "system" (self: rawptr) -> u32,
	Navigate:                 proc "system" (self: rawptr, direction: i32, out: ^rawptr) -> HRESULT,
	GetRuntimeId:             proc "system" (self: rawptr, out: ^rawptr) -> HRESULT,
	get_BoundingRectangle:    proc "system" (self: rawptr, out: ^Uia_Rect) -> HRESULT,
	GetEmbeddedFragmentRoots: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT,
	SetFocus:                 proc "system" (self: rawptr) -> HRESULT,
	get_FragmentRoot:         proc "system" (self: rawptr, out: ^rawptr) -> HRESULT,
}

Fragment_Root_Vtbl :: struct {
	QueryInterface:           proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:                   proc "system" (self: rawptr) -> u32,
	Release:                  proc "system" (self: rawptr) -> u32,
	ElementProviderFromPoint: proc "system" (self: rawptr, x: f64, y: f64, out: ^rawptr) -> HRESULT,
	GetFocus:                 proc "system" (self: rawptr, out: ^rawptr) -> HRESULT,
}

Value_Vtbl :: struct {
	QueryInterface: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:         proc "system" (self: rawptr) -> u32,
	Release:        proc "system" (self: rawptr) -> u32,
	SetValue:       proc "system" (self: rawptr, value: rawptr) -> HRESULT,
	get_Value:      proc "system" (self: rawptr, out: ^rawptr) -> HRESULT,
	get_IsReadOnly: proc "system" (self: rawptr, out: ^i16) -> HRESULT,
}

Toggle_Vtbl :: struct {
	QueryInterface: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:         proc "system" (self: rawptr) -> u32,
	Release:        proc "system" (self: rawptr) -> u32,
	Toggle:         proc "system" (self: rawptr) -> HRESULT,
	get_ToggleState: proc "system" (self: rawptr, out: ^i32) -> HRESULT,
}

Invoke_Vtbl :: struct {
	QueryInterface: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:         proc "system" (self: rawptr) -> u32,
	Release:        proc "system" (self: rawptr) -> u32,
	Invoke:         proc "system" (self: rawptr) -> HRESULT,
}

Range_Vtbl :: struct {
	QueryInterface: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT,
	AddRef:         proc "system" (self: rawptr) -> u32,
	Release:        proc "system" (self: rawptr) -> u32,
	SetValue:       proc "system" (self: rawptr, value: f64) -> HRESULT,
	get_Value:      proc "system" (self: rawptr, out: ^f64) -> HRESULT,
	get_Minimum:    proc "system" (self: rawptr, out: ^f64) -> HRESULT,
	get_Maximum:    proc "system" (self: rawptr, out: ^f64) -> HRESULT,
	get_SmallChange: proc "system" (self: rawptr, out: ^f64) -> HRESULT,
	get_LargeChange: proc "system" (self: rawptr, out: ^f64) -> HRESULT,
}

provider_vtbl := Provider_Vtbl {
	QueryInterface = provider_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	get_ProviderOptions = provider_get_options,
	GetPatternProvider = provider_get_pattern,
	GetPropertyValue = provider_get_property,
	get_HostRawElementProvider = provider_get_host,
}

fragment_vtbl := Fragment_Vtbl {
	QueryInterface = fragment_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	Navigate = fragment_navigate,
	GetRuntimeId = fragment_runtime_id,
	get_BoundingRectangle = fragment_bounding_rectangle,
	GetEmbeddedFragmentRoots = fragment_embedded_roots,
	SetFocus = fragment_set_focus,
	get_FragmentRoot = fragment_root_of,
}

fragment_root_vtbl := Fragment_Root_Vtbl {
	QueryInterface = fragment_root_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	ElementProviderFromPoint = fragment_root_from_point,
	GetFocus = fragment_root_focus,
}

value_vtbl := Value_Vtbl {
	QueryInterface = value_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	SetValue = value_set_value,
	get_Value = value_get_value,
	get_IsReadOnly = value_get_read_only,
}

toggle_vtbl := Toggle_Vtbl {
	QueryInterface = toggle_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	Toggle = toggle_toggle,
	get_ToggleState = toggle_get_state,
}

invoke_vtbl := Invoke_Vtbl {
	QueryInterface = invoke_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	Invoke = invoke_invoke,
}

range_vtbl := Range_Vtbl {
	QueryInterface = range_query_interface,
	AddRef = uia_add_ref,
	Release = uia_release,
	SetValue = range_set_value,
	get_Value = range_get_value,
	get_Minimum = range_get_minimum,
	get_Maximum = range_get_maximum,
	get_SmallChange = range_get_small_change,
	get_LargeChange = range_get_large_change,
}

Uia_State :: struct {
	tree:      ^Access_Tree,
	hwnd:      windows.HWND,
	prev_proc: windows.WNDPROC,
	installed: bool,
}

uia_windows: [dynamic]Uia_Window_Entry
uia_windows_mutex: sync.Mutex

Uia_Window_Entry :: struct {
	hwnd:  windows.HWND,
	tree:  ^Access_Tree,
	state: ^Uia_State,
}

uia_start :: proc(tree: ^Access_Tree) -> bool {
	if tree == nil { return false }
	handle := tree.window
	if handle == nil { return false }
	sdl_window := cast(^sdl.Window)handle
	properties := sdl.GetWindowProperties(sdl_window)
	raw := sdl.GetPointerProperty(properties, sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)
	if raw == nil { return false }
	hwnd := cast(windows.HWND)raw

	if !uia_event_ready || !uia_property_event_ready {
		library, loaded := dynlib.load_library("UIAutomationCore.dll")
		if loaded {
			if address, found := dynlib.symbol_address(library, "UiaRaiseAutomationEvent"); found {
				uia_event = cast(Uia_Event)address
				uia_event_ready = true
			}
			if address, found := dynlib.symbol_address(library, "UiaRaiseAutomationPropertyChangedEvent"); found {
				uia_property_event = cast(Uia_Property_Event)address
				uia_property_event_ready = true
			}
		}
	}

	state := new(Uia_State)
	state.tree = tree
	state.hwnd = hwnd

	previous := windows.SetWindowLongPtrW(hwnd, windows.GWLP_WNDPROC, transmute(windows.LONG_PTR) uia_window_proc)
	if previous == 0 {
		free(state)
		return false
	}
	state.prev_proc = transmute(windows.WNDPROC) previous
	state.installed = true
	tree.native = cast(rawptr) state

	entry := Uia_Window_Entry{hwnd = hwnd, tree = tree, state = state}
	sync.mutex_lock(&uia_windows_mutex)
	append(&uia_windows, entry)
	sync.mutex_unlock(&uia_windows_mutex)
	return true
}

uia_stop :: proc(tree: ^Access_Tree) {
	if tree == nil { return }
	sync.mutex_lock(&tree.mutex)
	state := cast(^Uia_State)tree.native
	tree.native = nil
	sync.mutex_unlock(&tree.mutex)
	if state == nil { return }
	if state.installed && state.prev_proc != nil {
		windows.SetWindowLongPtrW(state.hwnd, windows.GWLP_WNDPROC, transmute(windows.LONG_PTR) state.prev_proc)
		state.installed = false
	}
	sync.mutex_lock(&uia_windows_mutex)
	for i := len(uia_windows) - 1; i >= 0; i -= 1 {
		if uia_windows[i].tree == tree {
			ordered_remove(&uia_windows, i)
		}
	}
	sync.mutex_unlock(&uia_windows_mutex)
	free(state)
}

uia_window_proc :: proc "system" (
	hwnd: windows.HWND,
	message: windows.UINT,
	wparam: windows.WPARAM,
	lparam: windows.LPARAM,
) -> windows.LRESULT {
	context = runtime.default_context()
	if message == WM_GETOBJECT && i32(lparam) == UIA_ROOT_OBJECT_ID {
		if provider := uia_root_provider_for(hwnd); provider != nil {
			address := cast(rawptr) provider
			return windows.LRESULT(cast(i64) uintptr(address))
		}
	}
	if state, found := uia_state_of(hwnd); found && state.prev_proc != nil {
		return windows.CallWindowProcW(state.prev_proc, hwnd, message, wparam, lparam)
	}
	return windows.DefWindowProcW(hwnd, message, wparam, lparam)
}

uia_root_provider_for :: proc(hwnd: windows.HWND) -> ^Uia_Provider {
	sync.mutex_lock(&uia_windows_mutex)
	defer sync.mutex_unlock(&uia_windows_mutex)
	for entry in uia_windows {
		if entry.hwnd != hwnd { continue }
		provider := uia_root_provider(entry.tree)
		if provider != nil { uia_add_ref(cast(rawptr) provider) }
		return provider
	}
	return nil
}

uia_state_of :: proc(hwnd: windows.HWND) -> (state: Uia_State, found: bool) {
	sync.mutex_lock(&uia_windows_mutex)
	defer sync.mutex_unlock(&uia_windows_mutex)
	for entry in uia_windows {
		if entry.hwnd == hwnd { return entry.state^, true }
	}
	return {}, false
}

uia_root_provider :: proc(tree: ^Access_Tree) -> ^Uia_Provider {
	if tree == nil || tree.gui == nil { return nil }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	node := access_node_find_locked(tree, tree.gui.root)
	if node == nil { return nil }
	object := cast(^Uia_Object)node.native
	if object == nil || !object.node.alive { return nil }
	return object.provider
}

uia_automation_id_of :: proc(tree: ^Access_Tree, node: ^Access_Node) -> string {
	if tree != nil && tree.gui != nil && node != nil {
		if w := Core.Widget_Get(tree.gui, node.id); w != nil && w.name != "" { return w.name }
	}
	if node == nil { return "" }
	return Core.Access_Role_Name(node.role)
}

uia_string_replace :: proc(dst: ^string, text: string, allocator: mem.Allocator) {
	if dst^ == text { return }
	if dst^ != "" { free(raw_data(dst^), allocator) }
	dst^ = text == "" ? "" : strings.clone(text, allocator)
}

uia_node_children :: proc(object: ^Uia_Object, tree: ^Access_Tree, w: ^Core.Widget) {
	if object == nil || tree == nil || tree.gui == nil || w == nil { return }
	allocator := object.allocator
	count := 0
	child := w.first_child
	for child != Core.INVALID_WIDGET_ID {
		c := Core.Widget_Get(tree.gui, child)
		if c == nil { break }
		if .Visible in c.state && !uia_child_hidden_locked(tree, child) { count += 1 }
		child = c.next_sibling
	}
	if count == 0 {
		if len(object.node.children) > 0 { free(raw_data(object.node.children), allocator) }
		object.node.children = nil
		return
	}
	if count != len(object.node.children) {
		if len(object.node.children) > 0 { free(raw_data(object.node.children), allocator) }
		object.node.children = make([]Core.Widget_ID, count, allocator)
	}
	i := 0
	child = w.first_child
	for child != Core.INVALID_WIDGET_ID {
		c := Core.Widget_Get(tree.gui, child)
		if c == nil { break }
		if .Visible in c.state && !uia_child_hidden_locked(tree, child) {
			object.node.children[i] = child
			i += 1
		}
		child = c.next_sibling
	}
}

uia_child_hidden_locked :: proc(tree: ^Access_Tree, id: Core.Widget_ID) -> bool {
	node := access_node_find_locked(tree, id)
	if node == nil { return false }
	return .Hidden in node.states
}

uia_node_shape :: proc(object: ^Uia_Object, tree: ^Access_Tree, id: Core.Widget_ID) {
	if object == nil || tree == nil || tree.gui == nil { return }
	w := Core.Widget_Get(tree.gui, id)
	if w == nil {
		object.node.alive = false
		return
	}
	object.node.id = id
	object.node.parent = w.parent
	object.node.rect = w.rect
	object.node.can_focus = w.focus_mode != .None && w.focus_mode != .Click
	object.node.alive = true
	uia_node_children(object, tree, w)
}

uia_node_copy :: proc(object: ^Uia_Object, tree: ^Access_Tree, node: ^Access_Node) {
	if object == nil || tree == nil || node == nil { return }
	allocator := object.allocator
	object.node.id = node.id
	object.node.role = node.role
	object.node.states = node.states
	object.node.relations = node.relations
	object.node.relation_count = node.relation_count
	uia_string_replace(&object.node.name, node.name, allocator)
	uia_string_replace(&object.node.description, node.description, allocator)
	uia_string_replace(&object.node.value.text, node.value.text, allocator)
	object.node.value.number = node.value.number
	object.node.value.min = node.value.min
	object.node.value.max = node.value.max
	object.node.value.step = node.value.step
	object.node.value.percent = node.value.percent
	uia_string_replace(&object.node.automation_id, uia_automation_id_of(tree, node), allocator)
	uia_node_shape(object, tree, node.id)
}

uia_object_create :: proc(tree: ^Access_Tree, node: ^Access_Node) -> rawptr {
	if tree == nil || node == nil { return nil }
	allocator := access_allocator(tree)
	object := new(Uia_Object, allocator)
	object.tree = tree
	object.allocator = allocator
	object.refs = 1
	uia_node_copy(object, tree, node)

	provider := new(Uia_Provider, allocator)
	provider.vtbl = &provider_vtbl
	provider.object = object
	object.provider = provider

	fragment := new(Uia_Fragment, allocator)
	fragment.vtbl = &fragment_vtbl
	fragment.object = object
	object.fragment = fragment

	if tree.gui != nil && node.id == tree.gui.root {
		fragment_root := new(Uia_Fragment_Root, allocator)
		fragment_root.vtbl = &fragment_root_vtbl
		fragment_root.object = object
		object.fragment_root = fragment_root
	}

	node.native = cast(rawptr) object
	return cast(rawptr) object
}

uia_object_destroy :: proc(tree: ^Access_Tree, node: ^Access_Node) {
	if node == nil { return }
	object := cast(^Uia_Object)node.native
	if object == nil { return }
	node.native = nil
	object.tree = nil
	object.node.alive = false
	uia_object_release(object)
}

uia_object_free :: proc(object: ^Uia_Object) {
	if object == nil { return }
	allocator := object.allocator
	if object.node.name != "" { free(raw_data(object.node.name), allocator) }
	if object.node.description != "" { free(raw_data(object.node.description), allocator) }
	if object.node.value.text != "" { free(raw_data(object.node.value.text), allocator) }
	if object.node.automation_id != "" { free(raw_data(object.node.automation_id), allocator) }
	if len(object.node.children) > 0 { free(raw_data(object.node.children), allocator) }
	if object.value != nil { free(object.value, allocator) }
	if object.toggle != nil { free(object.toggle, allocator) }
	if object.invoke != nil { free(object.invoke, allocator) }
	if object.range != nil { free(object.range, allocator) }
	if object.fragment != nil { free(object.fragment, allocator) }
	if object.fragment_root != nil { free(object.fragment_root, allocator) }
	if object.provider != nil { free(object.provider, allocator) }
	free(object, allocator)
}

uia_object_release :: proc(object: ^Uia_Object) {
	if object == nil { return }
	if sync.atomic_sub(&object.refs, 1) != 1 { return }
	uia_object_free(object)
}

uia_add_ref :: proc "system" (self: rawptr) -> u32 {
	context = runtime.default_context()
	any := cast(^Uia_Any)self
	if any == nil { return 0 }
	return u32(sync.atomic_add(&any.object.refs, 1)) + 1
}

uia_release :: proc "system" (self: rawptr) -> u32 {
	context = runtime.default_context()
	any := cast(^Uia_Any)self
	if any == nil { return 0 }
	object := any.object
	count := u32(sync.atomic_sub(&object.refs, 1))
	if count == 1 { uia_object_free(object) }
	return count - 1
}

Uia_Any :: struct {
	vtbl:   rawptr,
	object: ^Uia_Object,
}

uia_interface :: proc(
	self: rawptr,
	iid: ^GUID,
	out: ^rawptr,
	simple: rawptr,
	fragment: rawptr,
	fragment_root: rawptr,
) -> HRESULT {
	if self == nil || iid == nil || out == nil { return E_POINTER }
	out^ = nil
	if iid^ == IID_IUnknown {
		out^ = self
		uia_add_ref(self)
		return S_OK
	}
	if iid^ == IID_Raw_Provider {
		if simple == nil { return E_NOINTERFACE }
		out^ = simple
		uia_add_ref(simple)
		return S_OK
	}
	if iid^ == IID_Raw_Fragment {
		if fragment == nil { return E_NOINTERFACE }
		out^ = fragment
		uia_add_ref(fragment)
		return S_OK
	}
	if iid^ == IID_Raw_Fragment_Root {
		if fragment_root == nil { return E_NOINTERFACE }
		out^ = fragment_root
		uia_add_ref(fragment_root)
		return S_OK
	}
	return E_NOINTERFACE
}

provider_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	p := cast(^Uia_Provider)self
	if p == nil || p.object == nil { return E_POINTER }
	object := p.object
	return uia_interface(
		self,
		iid,
		out,
		self,
		cast(rawptr) object.fragment,
		cast(rawptr) object.fragment_root,
	)
}

fragment_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	f := cast(^Uia_Fragment)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	return uia_interface(
		self,
		iid,
		out,
		cast(rawptr) object.provider,
		self,
		cast(rawptr) object.fragment_root,
	)
}

fragment_root_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	f := cast(^Uia_Fragment_Root)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	return uia_interface(
		self,
		iid,
		out,
		cast(rawptr) object.provider,
		cast(rawptr) object.fragment,
		self,
	)
}

provider_get_options :: proc "system" (self: rawptr, out: ^u32) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0x2
	return S_OK
}

provider_get_host :: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	return S_OK
}

provider_get_pattern :: proc "system" (self: rawptr, pattern: i32, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	p := cast(^Uia_Provider)self
	if p == nil || p.object == nil { return E_POINTER }
	object := p.object
	if object.tree == nil || !object.node.alive { return S_OK }
	switch pattern {
	case UIA_ValuePatternId:
		if !uia_has_value(object.node.role) { return S_OK }
		if object.value == nil {
			value := new(Uia_Value, object.allocator)
			value.vtbl = &value_vtbl
			value.object = object
			object.value = value
		}
		out^ = cast(rawptr) object.value
		uia_add_ref(cast(rawptr) object.value)
	case UIA_TogglePatternId:
		if !uia_has_toggle(object.node.role) { return S_OK }
		if object.toggle == nil {
			toggle := new(Uia_Toggle, object.allocator)
			toggle.vtbl = &toggle_vtbl
			toggle.object = object
			object.toggle = toggle
		}
		out^ = cast(rawptr) object.toggle
		uia_add_ref(cast(rawptr) object.toggle)
	case UIA_InvokePatternId:
		if !uia_has_invoke(object.node.role) { return S_OK }
		if object.invoke == nil {
			invoke := new(Uia_Invoke, object.allocator)
			invoke.vtbl = &invoke_vtbl
			invoke.object = object
			object.invoke = invoke
		}
		out^ = cast(rawptr) object.invoke
		uia_add_ref(cast(rawptr) object.invoke)
	case UIA_RangeValuePatternId:
		if !uia_has_range(object.node.role) { return S_OK }
		if object.range == nil {
			range := new(Uia_Range, object.allocator)
			range.vtbl = &range_vtbl
			range.object = object
			object.range = range
		}
		out^ = cast(rawptr) object.range
		uia_add_ref(cast(rawptr) object.range)
	}
	return S_OK
}

provider_get_property :: proc "system" (self: rawptr, id: i32, out: ^VARIANT) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = VARIANT{}
	p := cast(^Uia_Provider)self
	if p == nil || p.object == nil { return E_POINTER }
	object := p.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }

	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	role := object.node.role
	name := object.node.name
	description := object.node.description
	value := object.node.value
	states := object.node.states

	switch id {
	case UIA_ControlTypePropertyId:
		out.vt = VT_I4
		variant_int(out)^ = uia_control_type(role)
	case UIA_LocalizedControlTypePropertyId:
		out.vt = VT_BSTR
		variant_pointer(out)^ = uia_bstr(uia_control_type_name(uia_control_type(role)), object.allocator)
	case UIA_NamePropertyId:
		out.vt = VT_BSTR
		variant_pointer(out)^ = uia_bstr(name, object.allocator)
	case UIA_HelpTextPropertyId:
		out.vt = VT_BSTR
		variant_pointer(out)^ = uia_bstr(description, object.allocator)
	case UIA_AutomationIdPropertyId:
		out.vt = VT_BSTR
		variant_pointer(out)^ = uia_bstr(object.node.automation_id, object.allocator)
	case UIA_ClassNamePropertyId:
		out.vt = VT_BSTR
		variant_pointer(out)^ = uia_bstr("CalcUI", object.allocator)
	case UIA_FrameworkIdPropertyId:
		out.vt = VT_BSTR
		variant_pointer(out)^ = uia_bstr("CalcUI", object.allocator)
	case UIA_IsEnabledPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(!(.Disabled in states))
	case UIA_IsOffscreenPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(uia_hidden_locked(tree, object))
	case UIA_HasKeyboardFocusPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(.Focused in states)
	case UIA_IsKeyboardFocusablePropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(object.node.can_focus)
	case UIA_IsControlElementPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(true)
	case UIA_IsContentElementPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(true)
	case UIA_IsPasswordPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(role == .Password_Input)
	case UIA_IsRequiredForFormPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(.Required in states)
	case UIA_ProcessIdPropertyId:
		out.vt = VT_I4
		variant_int(out)^ = i32(windows.GetCurrentProcessId())
	case UIA_NativeWindowHandlePropertyId:
		out.vt = VT_I4
		if tree.gui != nil && object.node.id == tree.gui.root {
			variant_int(out)^ = i32(uintptr(uia_hwnd_locked(tree)))
		} else {
			variant_int(out)^ = 0
		}
	case UIA_ValueValuePropertyId:
		out.vt = VT_BSTR
		context = runtime.default_context()
		variant_pointer(out)^ = uia_bstr(Core.Access_Value_Text(value), object.allocator)
	case UIA_ValueIsReadOnlyPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(.Read_Only in states)
	case UIA_RangeValueValuePropertyId:
		out.vt = VT_R8
		out.value.double = value.number
	case UIA_RangeValueMinimumPropertyId:
		out.vt = VT_R8
		out.value.double = value.min
	case UIA_RangeValueMaximumPropertyId:
		out.vt = VT_R8
		out.value.double = value.max
	case UIA_RangeValueSmallChangePropertyId:
		out.vt = VT_R8
		out.value.double = value.step
	case UIA_RangeValueLargeChangePropertyId:
		out.vt = VT_R8
		out.value.double = value.step
	case UIA_ToggleToggleStatePropertyId:
		out.vt = VT_I4
		variant_int(out)^ = uia_toggle_state(states)
	case UIA_IsValuePatternAvailablePropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(uia_has_value(role))
	case UIA_IsTogglePatternAvailablePropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(uia_has_toggle(role))
	case UIA_IsInvokePatternAvailablePropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(uia_has_invoke(role))
	case UIA_IsRangeValuePatternAvailablePropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(uia_has_range(role))
	case UIA_IsSelectionItemPatternAvailablePropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(false)
	case UIA_SelectionItemIsSelectedPropertyId:
		out.vt = VT_BOOL
		variant_bool(out)^ = uia_bool(.Selected in states)
	}
	return S_OK
}

Uia_Rect :: struct {
	left:   f64,
	top:    f64,
	width:  f64,
	height: f64,
}

fragment_navigate :: proc "system" (
	self: rawptr,
	direction: i32,
	out: ^rawptr,
) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	f := cast(^Uia_Fragment)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }

	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	next := Core.INVALID_WIDGET_ID
	switch direction {
	case 0: //* the parent
		next = object.node.parent
	case 1, 2: //* the brothers, in the order of the parent
		if parent := access_node_find_locked(tree, object.node.parent); parent != nil {
			if parent_object := cast(^Uia_Object)parent.native; parent_object != nil {
				for child, i in parent_object.node.children {
					if child != object.node.id { continue }
					if direction == 1 && i + 1 < len(parent_object.node.children) {
						next = parent_object.node.children[i + 1]
					} else if direction == 2 && i > 0 {
						next = parent_object.node.children[i - 1]
					}
					break
				}
			}
		}
	case 3: //* the first child
		if len(object.node.children) > 0 { next = object.node.children[0] }
	case 4: //* the last child
		if len(object.node.children) > 0 { next = object.node.children[len(object.node.children) - 1] }
	}
	if next == Core.INVALID_WIDGET_ID { return S_OK }
	provider := uia_provider_of_locked(tree, next)
	if provider == nil { return S_OK }
	out^ = cast(rawptr) provider
	uia_add_ref(cast(rawptr) provider)
	return S_OK
}

fragment_runtime_id :: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	return E_NOTIMPL
}

fragment_bounding_rectangle :: proc "system" (self: rawptr, out: ^Uia_Rect) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = Uia_Rect{}
	f := cast(^Uia_Fragment)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	sync.mutex_lock(&tree.mutex)
	rect := object.node.rect
	origin := tree.origin
	scale := tree.scale
	sync.mutex_unlock(&tree.mutex)
	if !(scale > 0) { scale = 1 }
	out^ = Uia_Rect {
		left   = f64((origin.x + rect.x) * scale),
		top    = f64((origin.y + rect.y) * scale),
		width  = f64(rect.w * scale),
		height = f64(rect.h * scale),
	}
	return S_OK
}

fragment_embedded_roots :: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	return S_OK
}

fragment_set_focus :: proc "system" (self: rawptr) -> HRESULT {
	context = runtime.default_context()
	f := cast(^Uia_Fragment)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	access_queue_action(tree, Access_Action{kind = .Focus, id = object.node.id})
	return S_OK
}

fragment_root_of :: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	f := cast(^Uia_Fragment)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	tree := object.tree
	if tree == nil { return S_OK }
	root := uia_root_fragment(tree)
	if root == nil { return S_OK }
	out^ = cast(rawptr) root
	uia_add_ref(cast(rawptr) root)
	return S_OK
}

fragment_root_from_point :: proc "system" (self: rawptr, x: f64, y: f64, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	f := cast(^Uia_Fragment_Root)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	tree := object.tree
	if tree == nil || tree.gui == nil || !object.node.alive { return S_OK }

	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	scale := tree.scale
	if !(scale > 0) { scale = 1 }
	origin := tree.origin
	point := Core.Vec2{x = f32(x) / scale - origin.x, y = f32(y) / scale - origin.y}
	id := uia_widget_at_locked(tree, tree.gui.root, point)
	if id == Core.INVALID_WIDGET_ID { return S_OK }
	provider := uia_provider_of_locked(tree, id)
	if provider == nil { return S_OK }
	out^ = cast(rawptr) provider
	uia_add_ref(cast(rawptr) provider)
	return S_OK
}

fragment_root_focus :: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = nil
	f := cast(^Uia_Fragment_Root)self
	if f == nil || f.object == nil { return E_POINTER }
	object := f.object
	tree := object.tree
	if tree == nil { return S_OK }

	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	id := tree.focused
	if id == Core.INVALID_WIDGET_ID { return S_OK }
	provider := uia_provider_of_locked(tree, id)
	if provider == nil { return S_OK }
	out^ = cast(rawptr) provider
	uia_add_ref(cast(rawptr) provider)
	return S_OK
}

value_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	v := cast(^Uia_Value)self
	if v == nil || v.object == nil { return E_POINTER }
	object := v.object
	if iid^ == IID_Value_Provider {
		out^ = self
		uia_add_ref(self)
		return S_OK
	}
	return uia_interface(self, iid, out, cast(rawptr) object.provider, cast(rawptr) object.fragment, cast(rawptr) object.fragment_root)
}

value_set_value :: proc "system" (self: rawptr, value: rawptr) -> HRESULT {
	context = runtime.default_context()
	v := cast(^Uia_Value)self
	if v == nil || v.object == nil { return E_POINTER }
	object := v.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	text := uia_text_of(value, object.allocator)
	access_queue_action(tree, Access_Action{kind = .Set_Value, id = object.node.id, text = text})
	return S_OK
}

value_get_value :: proc "system" (self: rawptr, out: ^rawptr) -> HRESULT {
	if out == nil { return E_POINTER }
	out^ = nil
	v := cast(^Uia_Value)self
	if v == nil || v.object == nil { return E_POINTER }
	object := v.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	context = runtime.default_context()
	sync.mutex_lock(&tree.mutex)
	out^ = uia_bstr(Core.Access_Value_Text(object.node.value), object.allocator)
	sync.mutex_unlock(&tree.mutex)
	return S_OK
}

value_get_read_only :: proc "system" (self: rawptr, out: ^i16) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = VARIANT_TRUE
	v := cast(^Uia_Value)self
	if v == nil || v.object == nil { return E_POINTER }
	object := v.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_bool(.Read_Only in uia_states_of(object))
	return S_OK
}

toggle_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	t := cast(^Uia_Toggle)self
	if t == nil || t.object == nil { return E_POINTER }
	object := t.object
	if iid^ == IID_Toggle_Provider {
		out^ = self
		uia_add_ref(self)
		return S_OK
	}
	return uia_interface(self, iid, out, cast(rawptr) object.provider, cast(rawptr) object.fragment, cast(rawptr) object.fragment_root)
}

toggle_toggle :: proc "system" (self: rawptr) -> HRESULT {
	context = runtime.default_context()
	t := cast(^Uia_Toggle)self
	if t == nil || t.object == nil { return E_POINTER }
	object := t.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	access_queue_action(tree, Access_Action{kind = .Toggle, id = object.node.id})
	return S_OK
}

toggle_get_state :: proc "system" (self: rawptr, out: ^i32) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0
	t := cast(^Uia_Toggle)self
	if t == nil || t.object == nil { return E_POINTER }
	object := t.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_toggle_state(uia_states_of(object))
	return S_OK
}

invoke_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	i := cast(^Uia_Invoke)self
	if i == nil || i.object == nil { return E_POINTER }
	object := i.object
	if iid^ == IID_Invoke_Provider {
		out^ = self
		uia_add_ref(self)
		return S_OK
	}
	return uia_interface(self, iid, out, cast(rawptr) object.provider, cast(rawptr) object.fragment, cast(rawptr) object.fragment_root)
}

invoke_invoke :: proc "system" (self: rawptr) -> HRESULT {
	context = runtime.default_context()
	i := cast(^Uia_Invoke)self
	if i == nil || i.object == nil { return E_POINTER }
	object := i.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	access_queue_action(tree, Access_Action{kind = .Invoke, id = object.node.id})
	return S_OK
}

range_query_interface :: proc "system" (self: rawptr, iid: ^GUID, out: ^rawptr) -> HRESULT {
	context = runtime.default_context()
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	if iid^ == IID_Range_Provider {
		out^ = self
		uia_add_ref(self)
		return S_OK
	}
	return uia_interface(self, iid, out, cast(rawptr) object.provider, cast(rawptr) object.fragment, cast(rawptr) object.fragment_root)
}

range_set_value :: proc "system" (self: rawptr, value: f64) -> HRESULT {
	context = runtime.default_context()
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	tree := object.tree
	if tree == nil || !object.node.alive { return S_OK }
	access_queue_action(tree, Access_Action{kind = .Set_Range_Value, id = object.node.id, value = value})
	return S_OK
}

range_get_value :: proc "system" (self: rawptr, out: ^f64) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_value_of(object).number
	return S_OK
}

range_get_minimum :: proc "system" (self: rawptr, out: ^f64) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_value_of(object).min
	return S_OK
}

range_get_maximum :: proc "system" (self: rawptr, out: ^f64) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_value_of(object).max
	return S_OK
}

range_get_small_change :: proc "system" (self: rawptr, out: ^f64) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_value_of(object).step
	return S_OK
}

range_get_large_change :: proc "system" (self: rawptr, out: ^f64) -> HRESULT {
	context = runtime.default_context()
	if out == nil { return E_POINTER }
	out^ = 0
	r := cast(^Uia_Range)self
	if r == nil || r.object == nil { return E_POINTER }
	object := r.object
	if object.tree == nil || !object.node.alive { return S_OK }
	out^ = uia_value_of(object).step
	return S_OK
}

uia_hidden_locked :: proc(tree: ^Access_Tree, object: ^Uia_Object) -> bool {
	if object == nil { return true }
	if .Hidden in object.node.states { return true }
	parent := object.node.parent
	for parent != Core.INVALID_WIDGET_ID {
		node := access_node_find_locked(tree, parent)
		if node == nil { break }
		p := cast(^Uia_Object)node.native
		if p == nil { break }
		if .Hidden in p.node.states { return true }
		parent = p.node.parent
	}
	return false
}

//* The states and the value of an object, read where the object is kept.
uia_states_of :: proc(object: ^Uia_Object) -> Core.Access_States {
	if object == nil { return {} }
	if object.tree == nil { return object.node.states }
	sync.mutex_lock(&object.tree.mutex)
	states := object.node.states
	sync.mutex_unlock(&object.tree.mutex)
	return states
}

uia_value_of :: proc(object: ^Uia_Object) -> Core.Access_Value {
	if object == nil { return {} }
	if object.tree == nil { return object.node.value }
	sync.mutex_lock(&object.tree.mutex)
	value := object.node.value
	sync.mutex_unlock(&object.tree.mutex)
	return value
}

uia_control_type :: proc(role: Core.Access_Role) -> i32 {
	#partial switch role {
	case .Button: return UIA_ButtonControlTypeId
	case .Toggle_Button: return UIA_ButtonControlTypeId
	case .Check_Box: return UIA_CheckBoxControlTypeId
	case .Radio_Button: return UIA_RadioButtonControlTypeId
	case .Text_Input: return UIA_EditControlTypeId
	case .Password_Input: return UIA_EditControlTypeId
	case .Search_Input: return UIA_EditControlTypeId
	case .Number_Input: return UIA_EditControlTypeId
	case .Slider: return UIA_SliderControlTypeId
	case .Spin_Box: return UIA_SpinnerControlTypeId
	case .Progress_Bar: return UIA_ProgressBarControlTypeId
	case .Combo_Box: return UIA_ComboBoxControlTypeId
	case .List: return UIA_ListControlTypeId
	case .List_Item: return UIA_ListItemControlTypeId
	case .Tree: return UIA_TreeControlTypeId
	case .Tree_Item: return UIA_TreeItemControlTypeId
	case .Table: return UIA_TableControlTypeId
	case .Menu: return UIA_MenuControlTypeId
	case .Menu_Bar: return UIA_MenuBarControlTypeId
	case .Menu_Item: return UIA_MenuItemControlTypeId
	case .Tab: return UIA_TabItemControlTypeId
	case .Tab_List: return UIA_TabControlTypeId
	case .Dialog: return UIA_WindowControlTypeId
	case .Window: return UIA_WindowControlTypeId
	case .Tooltip: return UIA_ToolTipControlTypeId
	case .Status: return UIA_TextControlTypeId
	case .Image: return UIA_ImageControlTypeId
	case .Link: return UIA_HyperlinkControlTypeId
	case .Separator: return UIA_SeparatorControlTypeId
	case .Scroll_Bar: return UIA_ScrollBarControlTypeId
	case .Canvas: return UIA_CustomControlTypeId
	case .Chart: return UIA_CustomControlTypeId
	case .Custom: return UIA_CustomControlTypeId
	case .Group: return UIA_GroupControlTypeId
	case .Panel: return UIA_PaneControlTypeId
	case .Label: return UIA_TextControlTypeId
	case .Heading: return UIA_TextControlTypeId
	case .None: return UIA_CustomControlTypeId
	}
	return UIA_CustomControlTypeId
}

uia_control_type_name :: proc(control_type: i32) -> string {
	switch control_type {
	case UIA_ButtonControlTypeId: return "Button"
	case UIA_CheckBoxControlTypeId: return "CheckBox"
	case UIA_ComboBoxControlTypeId: return "ComboBox"
	case UIA_EditControlTypeId: return "Edit"
	case UIA_HyperlinkControlTypeId: return "Hyperlink"
	case UIA_ImageControlTypeId: return "Image"
	case UIA_ListItemControlTypeId: return "ListItem"
	case UIA_ListControlTypeId: return "List"
	case UIA_MenuControlTypeId: return "Menu"
	case UIA_MenuBarControlTypeId: return "MenuBar"
	case UIA_MenuItemControlTypeId: return "MenuItem"
	case UIA_ProgressBarControlTypeId: return "ProgressBar"
	case UIA_RadioButtonControlTypeId: return "RadioButton"
	case UIA_ScrollBarControlTypeId: return "ScrollBar"
	case UIA_SliderControlTypeId: return "Slider"
	case UIA_SpinnerControlTypeId: return "Spinner"
	case UIA_StatusBarControlTypeId: return "StatusBar"
	case UIA_TabControlTypeId: return "Tab"
	case UIA_TabItemControlTypeId: return "TabItem"
	case UIA_TextControlTypeId: return "Text"
	case UIA_ToolBarControlTypeId: return "ToolBar"
	case UIA_ToolTipControlTypeId: return "ToolTip"
	case UIA_TreeControlTypeId: return "Tree"
	case UIA_TreeItemControlTypeId: return "TreeItem"
	case UIA_CustomControlTypeId: return "Custom"
	case UIA_GroupControlTypeId: return "Group"
	case UIA_DataGridControlTypeId: return "DataGrid"
	case UIA_DocumentControlTypeId: return "Document"
	case UIA_WindowControlTypeId: return "Window"
	case UIA_PaneControlTypeId: return "Pane"
	case UIA_TableControlTypeId: return "Table"
	case UIA_SeparatorControlTypeId: return "Separator"
	}
	return "Custom"
}

uia_has_value :: proc(role: Core.Access_Role) -> bool {
	#partial switch role {
	case .Text_Input, .Password_Input, .Search_Input, .Number_Input:
		return true
	}
	return false
}

uia_has_toggle :: proc(role: Core.Access_Role) -> bool {
	#partial switch role {
	case .Check_Box, .Toggle_Button:
		return true
	}
	return false
}

uia_has_invoke :: proc(role: Core.Access_Role) -> bool {
	#partial switch role {
	case .Button, .Link, .Menu_Item:
		return true
	}
	return false
}

uia_has_range :: proc(role: Core.Access_Role) -> bool {
	#partial switch role {
	case .Slider, .Spin_Box:
		return true
	}
	return false
}

uia_toggle_state :: proc(states: Core.Access_States) -> i32 {
	if .Checked in states { return 1 }
	return 0
}

uia_bool :: proc(value: bool) -> i16 {
	return value ? VARIANT_TRUE : VARIANT_FALSE
}

uia_hwnd_locked :: proc(tree: ^Access_Tree) -> rawptr {
	if tree == nil { return nil }
	state := cast(^Uia_State)tree.native
	if state == nil { return nil }
	return cast(rawptr) state.hwnd
}

uia_widget_at_locked :: proc(tree: ^Access_Tree, id: Core.Widget_ID, point: Core.Vec2) -> Core.Widget_ID {
	node := access_node_find_locked(tree, id)
	if node == nil { return Core.INVALID_WIDGET_ID }
	object := cast(^Uia_Object)node.native
	if object == nil || !object.node.alive { return Core.INVALID_WIDGET_ID }
	if .Hidden in object.node.states { return Core.INVALID_WIDGET_ID }
	rect := object.node.rect
	if point.x < rect.x || point.y < rect.y { return Core.INVALID_WIDGET_ID }
	if point.x >= rect.x + rect.w || point.y >= rect.y + rect.h { return Core.INVALID_WIDGET_ID }
	found := Core.INVALID_WIDGET_ID
	for child in object.node.children {
		inside := uia_widget_at_locked(tree, child, point)
		if inside != Core.INVALID_WIDGET_ID { found = inside }
	}
	if found != Core.INVALID_WIDGET_ID { return found }
	return id
}

uia_provider_of_locked :: proc(tree: ^Access_Tree, id: Core.Widget_ID) -> ^Uia_Provider {
	node := access_node_find_locked(tree, id)
	if node == nil { return nil }
	object := cast(^Uia_Object)node.native
	if object == nil || !object.node.alive { return nil }
	return object.provider
}

uia_provider_of :: proc(tree: ^Access_Tree, id: Core.Widget_ID) -> ^Uia_Provider {
	if tree == nil { return nil }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	return uia_provider_of_locked(tree, id)
}

//* The object of the root of the tree.
uia_root_fragment :: proc(tree: ^Access_Tree) -> ^Uia_Fragment_Root {
	if tree == nil || tree.gui == nil { return nil }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	node := access_node_find_locked(tree, tree.gui.root)
	if node == nil { return nil }
	object := cast(^Uia_Object)node.native
	if object == nil || !object.node.alive { return nil }
	if object.fragment_root == nil {
		fragment_root := new(Uia_Fragment_Root, object.allocator)
		fragment_root.vtbl = &fragment_root_vtbl
		fragment_root.object = object
		object.fragment_root = fragment_root
	}
	return object.fragment_root
}

uia_bstr :: proc(text: string, allocator := context.allocator) -> rawptr {
	if text == "" {
		return SysAllocString(nil)
	}
	source := cast(^u8) raw_data(text)
	length := windows.MultiByteToWideChar(CP_UTF8, 0, source, i32(len(text)), nil, 0)
	if length <= 0 { return SysAllocString(nil) }
	buffer := make([]u16, length + 1, allocator)
	defer free(raw_data(buffer), allocator)
	written := windows.MultiByteToWideChar(CP_UTF8, 0, source, i32(len(text)), &buffer[0], length)
	if written <= 0 { return SysAllocString(nil) }
	buffer[written] = 0
	return SysAllocString(cast(rawptr) &buffer[0])
}

uia_text_of :: proc(text: rawptr, allocator := context.allocator) -> string {
	if text == nil { return "" }
	length := windows.WideCharToMultiByte(CP_UTF8, 0, cast(windows.LPCWSTR) text, -1, nil, 0, nil, nil)
	if length <= 1 { return "" }
	buffer := make([]u8, length, allocator)
	defer free(raw_data(buffer), allocator)
	written := windows.WideCharToMultiByte(
		CP_UTF8,
		0,
		cast(windows.LPCWSTR) text,
		-1,
		&buffer[0],
		length,
		nil,
		nil,
	)
	if written <= 1 { return "" }
	return strings.clone(string(buffer[:written-1]), allocator)
}

access_native :: proc() -> Access_Native {
	return Access_Native {
		available = true,
		start = uia_start,
		stop = uia_stop,
		create = uia_native_create,
		update = uia_native_update,
		destroy = uia_native_destroy,
		focus = uia_native_focus,
		frame = uia_native_frame,
	}
}

uia_native_create :: proc(tree: ^Access_Tree, node: ^Access_Node) -> rawptr {
	return uia_object_create(tree, node)
}

uia_native_update :: proc(tree: ^Access_Tree, node: ^Access_Node) {
	if tree == nil || node == nil { return }
	object := cast(^Uia_Object)node.native
	if object == nil { return }

	sync.mutex_lock(&tree.mutex)
	name_changed := object.node.name != node.name
	value_changed := object.node.value.text != node.value.text ||
		object.node.value.number != node.value.number ||
		object.node.value.min != node.value.min ||
		object.node.value.max != node.value.max ||
		object.node.value.step != node.value.step ||
		object.node.value.percent != node.value.percent
	old_checked := .Checked in object.node.states
	old_selected := .Selected in object.node.states
	new_checked := .Checked in node.states
	new_selected := .Selected in node.states
	uia_node_copy(object, tree, node)
	sync.mutex_unlock(&tree.mutex)

	if name_changed { uia_raise_event(object, UIA_AutomationNameChangedEventId) }
	if value_changed { uia_raise_event(object, UIA_AutomationValueChangedEventId) }
	if old_checked != new_checked {
		uia_raise_toggle(object, old_checked, new_checked)
	}
	if old_selected != new_selected {
		uia_raise_property(object, UIA_SelectionItemIsSelectedPropertyId, old_selected, new_selected)
	}
}

uia_native_frame :: proc(tree: ^Access_Tree) {
	if tree == nil || tree.gui == nil { return }
	sync.mutex_lock(&tree.mutex)
	defer sync.mutex_unlock(&tree.mutex)
	tree.origin = tree.gui.window_rect
	tree.scale = tree.gui.scale
	for id in tree.order {
		entry := access_node_find_locked(tree, id)
		if entry == nil { continue }
		object := cast(^Uia_Object)entry.native
		if object == nil { continue }
		uia_node_shape(object, tree, id)
	}
}

uia_raise_event :: proc(object: ^Uia_Object, id: i32) {
	if object == nil || object.provider == nil { return }
	if !uia_event_ready { return }
	uia_event(cast(rawptr) object.provider, id)
}

uia_raise_property :: proc(object: ^Uia_Object, property: i32, old: bool, new: bool) {
	if object == nil || object.provider == nil { return }
	if !uia_property_event_ready { return }
	old_v := VARIANT{vt = VT_BOOL}
	new_v := VARIANT{vt = VT_BOOL}
	variant_bool(&old_v)^ = uia_bool(old)
	variant_bool(&new_v)^ = uia_bool(new)
	uia_property_event(cast(rawptr) object.provider, property, old_v, new_v)
}

uia_raise_toggle :: proc(object: ^Uia_Object, old: bool, new: bool) {
	if object == nil || object.provider == nil { return }
	if !uia_property_event_ready { return }
	old_v := VARIANT{vt = VT_I4}
	new_v := VARIANT{vt = VT_I4}
	variant_int(&old_v)^ = old ? 1 : 0
	variant_int(&new_v)^ = new ? 1 : 0
	uia_property_event(cast(rawptr) object.provider, UIA_ToggleToggleStatePropertyId, old_v, new_v)
}

uia_native_destroy :: proc(tree: ^Access_Tree, node: ^Access_Node) {
	uia_object_destroy(tree, node)
}

uia_native_focus :: proc(tree: ^Access_Tree, id: Core.Widget_ID) {
	if tree == nil { return }
	if !uia_event_ready { return }
	provider := uia_provider_of(tree, id)
	if provider == nil { return }
	uia_event(cast(rawptr) provider, UIA_AutomationFocusChangedEventId)
}

//* A class of widget says what a kind of widget does: how it is drawn,
//* how it lays its children out, what it does with the mouse and the
//* keyboard, and what it says when it changes. Every widget belongs to a
//* class; a program brings a widget of its own by registering a class.

package GUI

//* == The classes of the widgets ==
//* The class is the one place a program has to change to add a widget:
//* the core asks the class of the widget what to do, so nothing outside
//* the class has to know that the widget exists.
//
//*   class := GUI.Widget_Register_Class(g, GUI.Widget_Class_Desc{
//*       name = "MyGauge",
//*       kind = GUI.Widget_Kind{
//*           draw = my_gauge_draw,
//*           measure = my_gauge_measure,
//*       },
//*   })
//*   id := GUI.Make_Custom_Widget(g, parent, class, GUI.Base_Opts{name = "gauge"})
//
//* A class has:
//
//* | Part | What it is |
//* |---|---|
//* | `name` | The name of the class. A theme and a scene file use it. |
//* | `type` | The type of the widgets of the class. |
//* | `kind` | The hooks: how the widget is drawn, measured and so on. |
//* | `constructor` | How a scene file makes one. |
//* | `signals` | The names of the signals the class fires. |

import "core:fmt"
import "core:log"

//* The handle of a class of widget. It names a slot in the table of classes.
Widget_Class_ID :: distinct u32

//* The handle of a class that does not exist. It is also the zero value
//* of a handle, so a handle that was never set names nothing.
INVALID_WIDGET_CLASS_ID :: Widget_Class_ID(0)

//* The identity of a kind of widget, with the hooks that say what it does.
Widget_Class :: struct {
	//* The name of the class: "Button", "MyGauge". A theme and a scene
	//* file look it up by this name.
	name: string,
	//* The type of the widgets of the class. A class of its own is
	//* based on .Panel, so that it behaves like a plain control.
	type: Widget_Type,
	kind: Widget_Kind,
	//* The constructor of the class, for a scene file. A class without
	//* one cannot be used in a scene file.
	constructor: Scene_Constructor,
	signals: []string,
	//* The role of the widgets of the class: what they are to whatever
	//* reads the screen for a person who cannot see it.
	access_role: Access_Role,
}

Widget_Class_Desc :: struct {
	//* The name of the class. It is what a theme and a scene file use.
	//* A class without a name cannot be used in either.
	name: string,
	//* The type of the widgets of the class. The zero value is .Panel, a
	//* plain control that places its children by their anchors.
	type: Widget_Type,
	kind: Widget_Kind,
	constructor: Scene_Constructor,
	signals: []string,
	access_role: Access_Role,
}

//* Registers a class of widget and gives back its handle.
//
//* It is called once, when the program starts. Every widget of the class
//* is made with Make_Custom_Widget, and the core asks the class what to do.
//
//* A class with a name that is already taken is the class that is already
//* there: the hooks the new class does not have are taken from the old one.
Widget_Register_Class :: proc(g: ^GUI, desc: Widget_Class_Desc) -> Widget_Class_ID {
	if g == nil { return INVALID_WIDGET_CLASS_ID }

	if desc.name != "" {
		if id, found := g.class_by_name[desc.name]; found {
			c := &g.classes[int(id) - 1]
			before := c.kind.style
			kind_override(&c.kind, desc.kind)
			if desc.constructor != nil { c.constructor = desc.constructor }
			if desc.signals != nil { c.signals = desc.signals }
			if desc.access_role != .None { c.access_role = desc.access_role }
			//* The class has a look of its own now, so its widgets are looked at again.
			if c.kind.style != before { class_style_changed(g) }
			return id
		}
	}

	id := Widget_Class_ID(len(g.classes) + 1)
	append(
		&g.classes,
		Widget_Class {
			name = desc.name,
			type = desc.type,
			kind = desc.kind,
			constructor = desc.constructor,
			signals = desc.signals,
			access_role = desc.access_role,
		},
	)
	if desc.name != "" { g.class_by_name[desc.name] = id }
	//* The class has a look of its own: its widgets are looked at again.
	if desc.kind.style != (Style{}) { class_style_changed(g) }
	return id
}

//* The class with a handle.
class_get :: proc(g: ^GUI, id: Widget_Class_ID) -> (Widget_Class, bool) {
	if g == nil { return {}, false }
	if id == INVALID_WIDGET_CLASS_ID { return {}, false }
	index := int(id) - 1
	if index < 0 || index >= len(g.classes) { return {}, false }
	return g.classes[index], true
}

//* The class with a name, if there is one.
class_by_name :: proc(g: ^GUI, name: string) -> (Widget_Class_ID, bool) {
	if g == nil || name == "" { return INVALID_WIDGET_CLASS_ID, false }
	id, found := g.class_by_name[name]
	if !found { return INVALID_WIDGET_CLASS_ID, false }
	return id, true
}

//* The class of a kind of widget, if there is one.
class_of_type :: proc(g: ^GUI, widget_type: Widget_Type) -> Widget_Class_ID {
	if g == nil { return INVALID_WIDGET_CLASS_ID }
	id, found := g.class_by_type[widget_type]
	if !found { return INVALID_WIDGET_CLASS_ID }
	return id
}

//* Gives the widgets of a kind a class, so that a program that wants to
//* change what the kind does can find it by its name.
class_register_type :: proc(g: ^GUI, widget_type: Widget_Type, kind: Widget_Kind) {
	if g == nil { return }
	name := type_name_of(widget_type)

	//* A class with that name may already be there: a program that
	//* registered one before the widget was made keeps it.
	if name != "" {
		if id, taken := g.class_by_name[name]; taken {
			c := &g.classes[int(id) - 1]
			before := c.kind.style
			kind_merge(&c.kind, kind)
			if c.kind.style != before { class_style_changed(g) }
			g.class_by_type[widget_type] = id
			return
		}
	}

	if id, found := g.class_by_type[widget_type]; found {
		c := &g.classes[int(id) - 1]
		before := c.kind.style
		kind_merge(&c.kind, kind)
		if c.kind.style != before { class_style_changed(g) }
		return
	}

	id := Widget_Class_ID(len(g.classes) + 1)
	append(&g.classes, Widget_Class{name = name, type = widget_type, kind = kind})
	g.class_by_type[widget_type] = id
	if name != "" { g.class_by_name[name] = id }
	//* The class has a look of its own: the widgets of that kind are looked at again.
	if kind.style != (Style{}) { class_style_changed(g) }
}

//* Says that the look of the GUI changed: the widgets of the class have to
//* be measured and drawn again.
class_style_changed :: proc(g: ^GUI) {
	if g == nil { return }
	g.style_epoch += 1
	style_cache_drop(g)
	invalidate_all(g, Dirty_Flags{.Measure, .Visual})
}

//* The name of a kind of widget, as the theme and the scene files name
//* it.
type_name_of :: proc(widget_type: Widget_Type) -> string {
	name, ok := fmt.enum_value_to_string(widget_type)
	if !ok { return "" }
	return name
}

//* Puts the hooks that are not there yet into a kind. A program that registers
//* a class with the name of a built-in widget only says what it changes.
kind_merge :: proc(base: ^Widget_Kind, over: Widget_Kind) {
	if base == nil { return }
	if base.draw == nil { base.draw = over.draw }
	if base.layout == nil { base.layout = over.layout }
	if base.click == nil { base.click = over.click }
	if base.key == nil { base.key = over.key }
	if base.update == nil { base.update = over.update }
	if base.measure == nil { base.measure = over.measure }
	if base.construct == nil { base.construct = over.construct }
	if base.destroy == nil { base.destroy = over.destroy }
	if base.pointer == nil { base.pointer = over.pointer }
	if base.text_input == nil { base.text_input = over.text_input }
	if !base.uses_arrow_keys { base.uses_arrow_keys = over.uses_arrow_keys }
	if !base.owns_children { base.owns_children = over.owns_children }
	if base.style.set == (bit_set[Style_Field]{}) { base.style = over.style }
	if base.theme_name == "" { base.theme_name = over.theme_name }
	if base.access_role == .None { base.access_role = over.access_role }
	if base.access == nil { base.access = over.access }
}

//* Puts the hooks of a class over the hooks that are there. A hook the new
//* class does not have is left alone.
kind_override :: proc(base: ^Widget_Kind, over: Widget_Kind) {
	if base == nil { return }
	if over.draw != nil { base.draw = over.draw }
	if over.layout != nil { base.layout = over.layout }
	if over.click != nil { base.click = over.click }
	if over.key != nil { base.key = over.key }
	if over.update != nil { base.update = over.update }
	if over.measure != nil { base.measure = over.measure }
	if over.construct != nil { base.construct = over.construct }
	if over.destroy != nil { base.destroy = over.destroy }
	if over.pointer != nil { base.pointer = over.pointer }
	if over.text_input != nil { base.text_input = over.text_input }
	if over.uses_arrow_keys { base.uses_arrow_keys = true }
	if over.owns_children { base.owns_children = true }
	if over.style != (Style{}) { base.style = over.style }
	if over.theme_name != "" { base.theme_name = over.theme_name }
	if over.access_role != .None { base.access_role = over.access_role }
	if over.access != nil { base.access = over.access }
}

//* The hooks of a widget: the ones of its class when it has a class of its
//* own, or the ones of its type. Everything that used to switch on the type
//* of a widget goes through here, so a widget of a program's own works like
//* one of the built-in ones.
widget_kind :: proc(g: ^GUI, w: ^Widget) -> Widget_Kind {
	if g == nil || w == nil { return {} }
	if w.class != INVALID_WIDGET_CLASS_ID {
		if c, ok := class_get(g, w.class); ok { return c.kind }
	}
	return kind_of(g, w.type)
}

//* == Making a widget of a class of its own ==

//* Makes a widget of a class of its own. The options are the ones every
//* widget has.
//
//* The data of the program is put in the widget with Widget_Set_User_Data,
//* and the class is told about the widget by its construct hook.
Make_Custom_Widget :: proc(
	g: ^GUI,
	parent: Widget_ID,
	class: Widget_Class_ID,
	opts: Base_Opts,
) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	c, ok := class_get(g, class)
	if !ok {
		log.warnf("there is no widget class %d", int(class))
		return INVALID_WIDGET_ID
	}
	return new_widget(g, c.type, parent, base_widget_opts(opts), class)
}

//* Puts a widget in a class. A widget that is built in can be put in a
//* class of the program's own, so that it behaves like one of them.
Widget_Set_Class :: proc(g: ^GUI, id: Widget_ID, class: Widget_Class_ID) {
	if g == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	w.class = class
}

//* The class of a widget, or the handle of nothing.
Widget_Class_Of :: proc(g: ^GUI, id: Widget_ID) -> Widget_Class_ID {
	if g == nil { return INVALID_WIDGET_CLASS_ID }
	w := Widget_Get(g, id)
	if w == nil { return INVALID_WIDGET_CLASS_ID }
	return w.class
}

//* The name of a class, or the empty string.
Widget_Class_Name :: proc(g: ^GUI, class: Widget_Class_ID) -> string {
	c, ok := class_get(g, class)
	if !ok { return "" }
	return c.name
}

//* The names of the signals a class fires.
Widget_Class_Signals :: proc(g: ^GUI, class: Widget_Class_ID) -> []string {
	c, ok := class_get(g, class)
	if !ok { return nil }
	return c.signals
}

//* == The data of a program ==
//* A widget of a class of its own keeps whatever the program needs in it. The
//* data is a pointer: the program knows what it is, and the core never looks
//* inside it.

Custom_Data :: struct {
	user: rawptr,
	//* What gives the data back, when the widget is destroyed.
	destroy: proc(user: rawptr),
}

//* The data of a widget that a program brought of its own, or nil.
Widget_User_Data :: proc(g: ^GUI, id: Widget_ID) -> rawptr {
	if g == nil { return nil }
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch d in w.data {
	case Custom_Data:
		return d.user
	}
	return nil
}

//* Puts the data of a program in a widget. The data that was there is
//* given back first. `destroy` gives the new data back when the widget
//* is destroyed; it may be nil when the data needs no giving back.
Widget_Set_User_Data :: proc(
	g: ^GUI,
	id: Widget_ID,
	user: rawptr,
	destroy: proc(user: rawptr),
) {
	if g == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Custom_Data:
		if d.destroy != nil && d.user != nil { d.destroy(d.user) }
		d.user = user
		d.destroy = destroy
		return
	}
	w.data = Custom_Data{user = user, destroy = destroy}
}

//* == The signals of a class ==
//* Every widget has the same set of built-in signals, so a program can connect
//* to any of them without knowing what kind of widget it is. A widget of a
//* class of its own can have signals of its own: the class names them, the
//* widget fires them by name and a program connects to them by name.

//* A connection to a signal of a widget.
Signal_Conn :: struct {
	name: string,
	//* What to do when the signal fires. The value is what the widget
	//* put in the signal; the program knows what it means.
	callback: proc(g: ^GUI, id: Widget_ID, value: any),
}

//* A connection, and the widget it belongs to.
Signal_Conn_Entry :: struct {
	id:   Widget_ID,
	conn: Signal_Conn,
}

//* Connects to a signal of a widget. The signal is named: the class says
//* which signals it fires, and the program connects to them by name.
//* Connecting to a signal that is already connected replaces the old one.
Widget_Connect :: proc(
	g: ^GUI,
	id: Widget_ID,
	name: string,
	callback: proc(g: ^GUI, id: Widget_ID, value: any),
) {
	if g == nil || callback == nil { return }
	if Widget_Get(g, id) == nil { return }
	for &entry in g.signal_conns {
		if entry.id != id { continue }
		if entry.conn.name != name { continue }
		entry.conn.callback = callback
		return
	}
	append(&g.signal_conns, Signal_Conn_Entry{id = id, conn = Signal_Conn{name = name, callback = callback}})
}

//* Breaks the connection to a signal of a widget.
Widget_Disconnect :: proc(g: ^GUI, id: Widget_ID, name: string) {
	if g == nil { return }
	for i := len(g.signal_conns) - 1; i >= 0; i -= 1 {
		entry := g.signal_conns[i]
		if entry.id != id { continue }
		if entry.conn.name != name { continue }
		ordered_remove(&g.signal_conns, i)
	}
}

//* Fires a signal of a widget. A signal that nobody listens to costs
//* nothing but the look-up.
Signal_Emit :: proc(g: ^GUI, id: Widget_ID, name: string, value: any = nil) {
	if g == nil { return }
	//* The connections are taken out of the table before any of them is called:
	//* a callback that connects to the same signal, or that breaks a connection,
	//* does not change the ones that are called now.
	matches: [dynamic]Signal_Conn
	defer delete(matches)
	for entry in g.signal_conns {
		if entry.id != id { continue }
		if entry.conn.name != name { continue }
		append(&matches, entry.conn)
	}
	for conn in matches {
		if conn.callback == nil { continue }
		conn.callback(g, id, value)
	}
}

//* == The life of a widget ==

//* Tells the class of a widget that the widget is going away. The class
//* gets its last chance to give back what it holds.
widget_notify_destroy :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	if g == nil || w == nil { return }
	kind := widget_kind(g, w)
	if kind.destroy != nil { kind.destroy(g, id, w) }
}

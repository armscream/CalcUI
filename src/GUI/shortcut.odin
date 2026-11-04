//* == The commands of the program ==
//* A command is a thing the program can do, with the key that does it.
//* The command palette shows the commands, and the keys of the
//* shortcuts are given to the command they belong to.

package GUI

Shortcut :: struct {
	key:    Key,
	mods:   Mods,
	//* Whether the command is done even when a widget that takes text
	//* has the keyboard.
	always: bool,
}

Command :: struct {
	name:     string,
	shortcut: Shortcut,
	action:   proc(g: ^GUI, id: Widget_ID),
	enabled:  bool,
}

Commands :: struct {
	list: [dynamic]Command,
}

//* Adds a command to the program and gives back its number.
Command_Add :: proc(
	g: ^GUI,
	name: string,
	shortcut: Shortcut,
	action: proc(g: ^GUI, id: Widget_ID),
) -> int {
	command := Command {
		name     = name,
		shortcut = shortcut,
		action   = action,
		enabled  = true,
	}
	append(&g.commands.list, command)
	return len(g.commands.list) - 1
}

//* Turns a command on or off.
Command_Set_Enabled :: proc(g: ^GUI, index: int, enabled: bool) {
	if index < 0 || index >= len(g.commands.list) {return}
	g.commands.list[index].enabled = enabled
}

//* The number of a command, by its name, or -1.
Command_Find :: proc(g: ^GUI, name: string) -> int {
	for command, i in g.commands.list {
		if command.name == name {return i}
	}
	return -1
}

//* True when the key and the modifiers are the shortcut of a command.
shortcut_matches :: proc(shortcut: Shortcut, key: Key, mods: Mods) -> bool {
	if shortcut.key != key {return false}
	//* The modifiers of the shortcut have to be there, and the ones
	//* that are not in it must not be.
	if (mods & shortcut.mods) != shortcut.mods {return false}
	if (mods & ~shortcut.mods) != (Mods{}) {return false}
	return true
}

//* The command of a key, if there is one. A command that is turned off
//* is passed over.
command_for_key :: proc(g: ^GUI, key: Key, mods: Mods, has_text: bool) -> int {
	for command, i in g.commands.list {
		if !command.enabled {continue}
		if !shortcut_matches(command.shortcut, key, mods) {continue}
		//* A widget that takes text has the keyboard: the keys that
		//* belong to it are not the keys of the program, unless the
		//* command says that it is always there.
		if has_text && !command.shortcut.always {continue}
		return i
	}
	return -1
}

//* Does the command of a key, if there is one. It says whether it was
//* done.
shortcut_fire :: proc(g: ^GUI, key: Key, mods: Mods) -> bool {
	has_text := widget_takes_text(g, g.focused)
	index := command_for_key(g, key, mods, has_text)
	if index < 0 {return false}
	command := g.commands.list[index]
	if command.action != nil {command.action(g, g.focused)}
	return true
}

//* Whether the widget takes the text that is typed: a field of text, a
//* search field, a chat field, a field of numbers or the palette.
widget_takes_text :: proc(g: ^GUI, id: Widget_ID) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	#partial switch d in w.data {
	case Text_Input_Data, Text_Edit_Data, Search_Field_Data, Chat_Input_Data,
		Number_Input_Data, Command_Palette_Data:
		return true
	}
	return false
}

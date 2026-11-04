//* == The sound ==
//* The GUI knows nothing about SDL, so the sound is a state and a set
//* of procs: the program drives it, and a platform binding tells the
//* state what is really happening.
//
//* The state of the sound belongs to the GUI, but the GUI itself
//* belongs to the core and cannot grow a field for it, so the sound is
//* kept here: one for every GUI that has one.
//
//* Without a binding the sound does not play, but everything else
//* works: the state says what is playing and how far it has come, and
//* the widget shows it.

package GUI

import virt "core:mem/virtual"
import "core:path/filepath"
import "core:strings"

//* What a platform binding has to be able to do for the sound to be
//* heard. A GUI without a binding keeps the state and nothing else.
Audio_Binding :: struct {
	//* Starts a sound and says how long it is, in seconds.
	play:     proc(g: ^GUI, path: string) -> f32,
	//* Stops the sound.
	stop:     proc(g: ^GUI),
	//* Says how far the sound has come, in seconds.
	position: proc(g: ^GUI) -> f32,
	//* Sets how loud the sound is.
	volume:   proc(g: ^GUI, volume: f32),
}

//* The sound of a GUI.
Audio_State :: struct {
	//* The file that is played.
	path:     string,
	//* Whether the sound is playing.
	playing:  bool,
	//* How loud it is, from 0 to 1.
	volume:   f32,
	//* How far the sound has come, in seconds.
	position: f32,
	//* How long the sound is, in seconds.
	length:   f32,
	//* Whether the sound is on and off.
	loops:    bool,
	//* The platform binding, when there is one.
	binding:  Audio_Binding,
	//* The frame the position was last moved in, so that the position
	//* is only moved once a frame.
	ticker:   i64,
}

//* The sound of every GUI that has one. The key is the GUI itself.
//* The map lives in the heap of the program: it is kept for as long
//* as the program runs, and the GUIs come and go.
audio_of: map[rawptr]^Audio_State

//* The sound of a GUI. It is made when it is asked for.
audio_state :: proc(g: ^GUI) -> ^Audio_State {
	if g == nil {return nil}
	if g.audio != nil {return g.audio}
	//* The state is in the arena of the GUI, so it lives as long as
	//* the GUI does.
	state, err := virt.new(&g.arena, Audio_State)
	if err != nil {return nil}
	state^ = Audio_State {
		volume = 1,
	}
	g.audio = state
	return state
}

//* Throws the sound of a GUI away. The program calls this before the
//* GUI is shut down.
audio_free :: proc(g: ^GUI) {
	if g == nil {return}
	g.audio = nil
}

//* Puts the platform binding in the sound of a GUI. Without it the
//* sound does not play, but the state of it is still kept.
audio_set_binding :: proc(g: ^GUI, binding: Audio_Binding) {
	state := audio_state(g)
	if state == nil {return}
	state.binding = binding
}

//* Starts a sound. The file is remembered, and the sound plays until it
//* is stopped or it is over.
audio_play :: proc(g: ^GUI, path: string) {
	state := audio_state(g)
	if state == nil {return}
	if path != "" && state.path != path {
		state.path = audio_clone(g, path)
	}
	state.position = 0
	state.length = 0
	state.playing = true
	if state.binding.play != nil {
		state.length = state.binding.play(g, path)
	}
}

//* Stops the sound.
audio_stop :: proc(g: ^GUI) {
	state := audio_state(g)
	if state == nil {return}
	state.playing = false
	state.position = 0
	if state.binding.stop != nil {state.binding.stop(g)}
}

//* Sets how loud the sound is, from 0 to 1.
audio_set_volume :: proc(g: ^GUI, volume: f32) {
	state := audio_state(g)
	if state == nil {return}
	state.volume = clamp(volume, 0, 1)
	if state.binding.volume != nil {state.binding.volume(g, state.volume)}
}

//* How far the sound has come, in seconds.
audio_position :: proc(g: ^GUI) -> f32 {
	state := audio_state(g)
	if state == nil {return 0}
	if state.binding.position != nil {return state.binding.position(g)}
	return state.position
}

//* How long the sound is, in seconds.
audio_length :: proc(g: ^GUI) -> f32 {
	state := audio_state(g)
	if state == nil {return 0}
	return state.length
}

//* Whether the sound is playing.
audio_is_playing :: proc(g: ^GUI) -> bool {
	state := audio_state(g)
	if state == nil {return false}
	return state.playing
}

//* The file that is played.
audio_path :: proc(g: ^GUI) -> string {
	state := audio_state(g)
	if state == nil {return ""}
	return state.path
}

//* Whether the sound is on and off.
audio_set_loops :: proc(g: ^GUI, loops: bool) {
	state := audio_state(g)
	if state == nil {return}
	state.loops = loops
}

//* Moves the sound on. The program calls this once a frame, or the
//* widget of the sound does it.
audio_update :: proc(g: ^GUI, rt: f32) {
	state := audio_state(g)
	if state == nil {return}
	if !state.playing {return}
	//* The position is only moved once a frame, however many widgets
	//* ask for it.
	if state.ticker == g.last_frame {return}
	state.ticker = g.last_frame
	state.position += rt
	if state.length > 0 && state.position >= state.length {
		if state.loops {
			state.position = 0
		} else {
			state.position = state.length
			state.playing = false
		}
	}
}

//* A copy of a string in the arena of the GUI, so that it lives as
//* long as the GUI does.
audio_clone :: proc(g: ^GUI, text: string) -> string {
	if text == "" {return ""}
	copied, err := strings.clone(text, virt.arena_allocator(&g.arena))
	if err != nil {return text}
	return copied
}

//* == The audio player ==

//* The options of the audio player.
Audio_Player_Opts :: struct {
	Base_Opts: Base_Opts,
	//* The file that is played.
	path:      string,
	//* How loud it is, from 0 to 1. Zero means that the sound of the
	//* GUI keeps the loudness it has.
	volume:    f32,
	//* Whether the sound is on and off.
	loops:     bool,
}

//* The height of the row of the audio player.
AUDIO_PLAYER_ROW :: 22
//* The width of a button of the audio player.
AUDIO_PLAYER_BUTTON :: 56
//* The height of the bar of the audio player.
AUDIO_PLAYER_BAR :: 6

//* Makes the audio player. It shows the file, how far the sound has
//* come, and the two buttons that start and stop it.
Make_Audio_Player :: proc(g: ^GUI, parent: Widget_ID, opts: Audio_Player_Opts) -> Widget_ID {
	kind_register(g, .AudioPlayer, audio_player_kind())
	id := New_Widget(g, .AudioPlayer, parent, base_widget_opts(opts.Base_Opts))
	w := Widget_Get(g, id)
	w.data = Audio_Player_Data {
		path   = opts.path,
		volume = opts.volume,
		loops  = opts.loops,
	}
	//* The look of the widget, unless the program brings a look of its
	//* own.
	if w.style == (Style{}) {
		kind := audio_player_kind()
		w.style = kind.style
	}

	//* The sound of the GUI is the sound the widget shows.
	state := audio_state(g)
	if state != nil {
		if opts.path != "" {state.path = audio_clone(g, opts.path)}
		if opts.volume > 0 {audio_set_volume(g, opts.volume)}
		state.loops = opts.loops
	}
	return id
}

//* The hooks of the audio player: how it is drawn, what it does when
//* it is clicked and how it moves the sound on.
audio_player_kind :: proc() -> Widget_Kind {
	return Widget_Kind {
		draw = draw_audio_player,
		click = click_audio_player,
		update = update_audio_player,
		style = Style {
			box = StyleBox{bg_color = RGBA(0.11, 0.12, 0.15, 1), content_margin = {6, 6, 6, 6}},
		},
		theme_name = "AudioPlayer",
	}
}

//* The data of the audio player.
audio_player_data :: proc(g: ^GUI, id: Widget_ID) -> ^Audio_Player_Data {
	w := Widget_Get(g, id)
	if w == nil {return nil}
	#partial switch &r in w.data {
	case Audio_Player_Data:
		return &r
	}
	return nil
}

//* The file the audio player plays.
audio_player_path :: proc(g: ^GUI, id: Widget_ID) -> string {
	data := audio_player_data(g, id)
	if data == nil {return ""}
	return data.path
}

//* Puts the file the audio player plays in. The sound starts from the
//* beginning.
audio_player_set_path :: proc(g: ^GUI, id: Widget_ID, path: string) {
	data := audio_player_data(g, id)
	if data == nil {return}
	data.path = path
	audio_play(g, path)
}

//* Whether the sound of the audio player is playing.
audio_player_is_playing :: proc(g: ^GUI, id: Widget_ID) -> bool {
	data := audio_player_data(g, id)
	if data == nil {return false}
	return data.playing
}

//* How far the sound of the audio player has come, in seconds.
audio_player_position :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	data := audio_player_data(g, id)
	if data == nil {return 0}
	return data.position
}

//* How long the sound of the audio player is, in seconds.
audio_player_length :: proc(g: ^GUI, id: Widget_ID) -> f32 {
	data := audio_player_data(g, id)
	if data == nil {return 0}
	return data.length
}

//* The buttons of the audio player: the one that starts the sound and
//* the one that stops it.
audio_player_buttons :: proc(content: Rect) -> (play, stop: Rect) {
	play = Rect {
		x = content.x + content.w - AUDIO_PLAYER_BUTTON * 2 - 4,
		y = content.y,
		w = AUDIO_PLAYER_BUTTON,
		h = AUDIO_PLAYER_ROW,
	}
	stop = Rect {
		x = content.x + content.w - AUDIO_PLAYER_BUTTON,
		y = content.y,
		w = AUDIO_PLAYER_BUTTON,
		h = AUDIO_PLAYER_ROW,
	}
	return
}

//* The name of the file that is player: the last piece of its path.
audio_player_name :: proc(path: string) -> string {
	if path == "" {return "no file"}
	return filepath.base(path)
}

//* The drawing of the audio player: the name of the file, the bar that
//* shows how far the sound has come, and the two buttons.
draw_audio_player :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, content: Rect) {
	//* The widget is the face of the sound of the GUI.
	state := audio_state(g)
	#partial switch &r in w.data {
	case Audio_Player_Data:
		if state != nil {
			r.path = state.path
			r.playing = state.playing
			r.volume = state.volume
			r.position = state.position
			r.length = state.length
			r.loops = state.loops
		}
	}

	style := resolved_style(g, w)
	colour := resolved_text_colour(g, id, w)
	play, stop := audio_player_buttons(content)

	//* The name of the file.
	name := ""
	#partial switch r in w.data {
	case Audio_Player_Data:
		name = audio_player_name(r.path)
	}
	label := Rect {
		x = content.x,
		y = content.y,
		w = play.x - content.x - 8,
		h = AUDIO_PLAYER_ROW,
	}
	draw_text(g, style.text, name, label, colour)

	//* The two buttons.
			draw_audio_button(g, style^, play, "Play", colour)
			draw_audio_button(g, style^, stop, "Stop", colour)

	//* The bar that shows how far the sound has come.
	bar := Rect {
		x = content.x,
		y = content.y + AUDIO_PLAYER_ROW + 6,
		w = content.w,
		h = AUDIO_PLAYER_BAR,
	}
	draw_rect(g, bar, RGBA(0.16, 0.17, 0.21, 1), 3)
	#partial switch r in w.data {
	case Audio_Player_Data:
		if r.length > 0 {
			filled := Rect {
				x = bar.x,
				y = bar.y,
				w = bar.w * clamp(r.position / r.length, 0, 1),
				h = bar.h,
			}
			draw_rect(g, filled, RGBA(0.20, 0.62, 1.0, 1), 3)
		}
	}
}

//* A button of the audio player.
draw_audio_button :: proc(g: ^GUI, style: Style, rect: Rect, text: string, colour: Colour) {
	draw_rect(g, rect, RGBA(0.19, 0.20, 0.24, 1), 4)
	label := Rect {
		x = rect.x,
		y = rect.y,
		w = rect.w,
		h = rect.h,
	}
	draw_text(g, style.text, text, label, colour)
}

//* The buttons of the audio player start and stop the sound.
click_audio_player :: proc(g: ^GUI, id: Widget_ID, w: ^Widget) {
	content := content_rect(g, w)
	play, stop := audio_player_buttons(content)
	path := audio_player_path(g, id)
	if path == "" {path = audio_path(g)}
	if rect_contains(play, g.pointer.x, g.pointer.y) {
		audio_play(g, path)
		return
	}
	if rect_contains(stop, g.pointer.x, g.pointer.y) {
		audio_stop(g)
	}
}

//* The sound moves on, and the widget shows where it is.
update_audio_player :: proc(g: ^GUI, id: Widget_ID, w: ^Widget, rt: f32) {
	audio_update(g, rt)
}

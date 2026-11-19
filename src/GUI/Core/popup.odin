//* The windows that come up over the rest of the UI: a menu, palette, dialog etc.
// events propagate to popups first.
package Core
import "core:slice"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
//* A popup that is open, and prev focused widget.
Popup_Entry :: struct {
	id:             Widget_ID,
	previous_focus: Widget_ID,
}

is_popup :: proc(w: ^Widget) -> bool {
	if w == nil { return false }
	#partial switch w.type {
	case .PopupMenu, .PopupPanel, .AcceptDialog, .ConfirmationDialog, .FileDialog,
		.ContextMenu, .CommandPalette:
		return true
	}
	return false
}

//* The place of an overlay in the order of the drawing: the overlays
//* come up over the ordinary widgets.
POPUP_Z_INDEX :: 100

//* Puts a popup under the root of the window, so that it comes up over
//* the scroll container and over the other parts of the UI. The popup
//* keeps its identity, so the handles of the program stay good.
Popup_Attach_To_Root :: proc(g: ^GUI, id: Widget_ID) {
	if g == nil { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	if g.root == INVALID_WIDGET_ID { return }
	Widget_Set_Parent(g, g.root, id)
	Widget_Set_Z_Index(g, id, POPUP_Z_INDEX)
	Widget_Set_Clip_Contents(g, id, false)
	Widget_Set_Anchors(g, id, Anchor{0, 0, 0, 0})
}

//* Opens a popup. A popup of a kind that has an open of its own is
//* opened by the open of that kind: a palette gets its commands and its
//* filter, and a dialog is reset before it comes up.
Popup_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch w.type {
	case .CommandPalette:
		Command_Palette_Open(g, id)
		return
	case .AcceptDialog, .ConfirmationDialog:
		Dialog_Open(g, id)
		return
	case .FileDialog:
		File_Dialog_Open(g, id)
		return
	case:
	}
	popup_open_core(g, id)
}

//* The work of opening a popup: the popup comes up, it takes the mouse
//* and the keyboard, and it is put on the stack of the open popups. The
//* openers of the kinds of popup call this, so that a popup is never
//* opened by itself.
popup_open_core :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if popup_index(g, id) >= 0 { return }
	w.state += Widget_State{.Visible}
	w.mouse_filter = .Stop
	append(&g.popups, Popup_Entry{id = id, previous_focus = g.focused})
	if can_focus_now(g, id) { focus_set(g, id) }
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Closes a popup and gives the keyboard back.
Popup_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w != nil {
		w.state -= Widget_State{.Visible}
		w.mouse_filter = .Ignore
	}
	popup_forget(g, id)
	invalidate(g, id, Dirty_Flags{.Visual, .Hit})
}

//* Takes a popup out of the stack of the open popups and gives the
//* keyboard back to the widget that had it.
popup_forget :: proc(g: ^GUI, id: Widget_ID) {
	for i := len(g.popups) - 1; i >= 0; i -= 1 {
		if g.popups[i].id != id { continue }
		previous := g.popups[i].previous_focus
		ordered_remove(&g.popups, i)
		if g.focused == id { focus_clear(g) }
		if previous != INVALID_WIDGET_ID && Widget_Alive(g, previous) {
			focus_set(g, previous)
		}
		return
	}
}

//* The place of a popup in the stack of the open popups, or -1.
popup_index :: proc(g: ^GUI, id: Widget_ID) -> int {
	for i := len(g.popups) - 1; i >= 0; i -= 1 {
		if g.popups[i].id == id { return i }
	}
	return -1
}

Popup_Is_Open :: proc(g: ^GUI, id: Widget_ID) -> bool {
	return popup_index(g, id) >= 0
}

Popup_Top :: proc(g: ^GUI) -> Widget_ID {
	if g == nil { return INVALID_WIDGET_ID }
	if len(g.popups) == 0 { return INVALID_WIDGET_ID }
	return g.popups[len(g.popups) - 1].id
}

//* Closes the popup that is on top of the others. Returns true when a
//* popup was closed.
popup_close_top :: proc(g: ^GUI) -> bool {
	id := Popup_Top(g)
	if id == INVALID_WIDGET_ID { return false }
	if Widget_Get(g, id) == nil {
		popup_forget(g, id)
		return true
	}
	popup_close_one(g, id)
	return true
}

//* Closes a popup with the close of its own kind: the close of a menu
//* takes the menu out of the stack, and the close of a dialog tells the
//* dialog that it is shut.
popup_close_one :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch w.type {
	case .ContextMenu: Context_Menu_Close(g, id)
	case .CommandPalette: Command_Palette_Close(g, id)
	case .PopupMenu: Popup_Menu_Close(g, id)
	case .AcceptDialog, .ConfirmationDialog: Dialog_Close(g, id)
	case .FileDialog: File_Dialog_Close(g, id)
	case: Popup_Close(g, id)
	}
}

//* == The place of a popup ==
//* The rect of a widget is in the coordinates of the window the widget
//* is in: the place of the main window, or the place of the floating
//* panel. The rect of a popup on the screen is the rect of the widget
//* with the place of that window added to it.

//* The rect of a widget in the coordinates of the screen.
widget_global_rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	w := Widget_Get(g, id)
	if w == nil { return Rect{} }
	origin := Vec2{g.window_rect.x, g.window_rect.y}
	index := float_index_of(g, id)
	if index != FLOAT_NONE {
		origin = g.floats[index].pos
	}
	return Rect {
		x = origin.x + w.rect.x,
		y = origin.y + w.rect.y,
		w = w.rect.w,
		h = w.rect.h,
	}
}

//* The rect a popup really covers, in the coordinates of the screen. The
//* drop-down has the rect it was placed at, and the context menu has
//* the rect it is drawn at.
popup_rect :: proc(g: ^GUI, id: Widget_ID) -> Rect {
	return widget_global_rect(g, id)
}

//* Puts a popup widget where it belongs. The anchors of the widget go
//* to zero, the offsets are the place of the widget in its parent, and
//* the rect of the widget is written, so that the layout puts it in the
//* same place again.
popup_set_rect :: proc(g: ^GUI, id: Widget_ID, rect: Rect) {
	w := Widget_Get(g, id)
	if w == nil { return }
	parent := Widget_Get(g, w.parent)
	if parent == nil { return }
	left := rect.x - parent.rect.x
	top := rect.y - parent.rect.y
	Widget_Set_Anchors(g, id, Anchor{0, 0, 0, 0})
	Widget_Set_Offsets(g, id, Offset{
		left = left,
		top = top,
		right = left + rect.w,
		bottom = top + rect.h,
	})
	w.rect = rect
}

//* == The click outside a menu ==
//* A click outside a menu closes it, and the click goes to the widget
//* under the pointer. The rule is for the menus: the dialogs, the
//* command palette and the popup panel keep the behaviour they have.

//* A click outside the menu that is open closes it. The menu belongs to
//* the button it belongs to: a click on the button itself is left to
//* the button, which closes the menu when it is clicked again.
popup_close_outside :: proc(g: ^GUI, global: Vec2) {
	id := Popup_Top(g)
	if id == INVALID_WIDGET_ID { return }
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch w.type {
	case .PopupMenu, .ContextMenu:
		rect := popup_rect(g, id)
		if rect_contains(rect, global.x, global.y) { return }
		if popup_owner_hit(g, id, global) { return }
		popup_close_one(g, id)
	case .CommandPalette:
		//* A palette owned by a widget is a floating menu for that widget.
		d := command_palette_data(g, id)
		if d == nil || d.owner == INVALID_WIDGET_ID { return }
		rect := popup_rect(g, id)
		if rect_contains(rect, global.x, global.y) { return }
		popup_close_one(g, id)
	}
}

//* Whether a point is on the button a drop-down belongs to.
popup_owner_hit :: proc(g: ^GUI, id: Widget_ID, global: Vec2) -> bool {
	w := Widget_Get(g, id)
	if w == nil { return false }
	owner := INVALID_WIDGET_ID
	#partial switch d in w.data {
	case Popup_Menu_Data:
		owner = d.owner
	}
	if owner == INVALID_WIDGET_ID { return false }
	rect := widget_global_rect(g, owner)
	return rect_contains(rect, global.x, global.y)
}

command_palette_data :: proc(g: ^GUI, id: Widget_ID) -> ^Command_Palette_Data {
	w := Widget_Get(g, id)
	if w == nil { return nil }
	#partial switch &d in w.data {
	case Command_Palette_Data:
		return &d
	}
	return nil
}

palette_match_less :: proc(a, b: Palette_Match) -> bool {
	if a.score != b.score { return a.score > b.score }
	return a.index < b.index
}

command_palette_matches_build :: proc(d: ^Command_Palette_Data) {
	clear(&d.matches)
	for command, index in d.commands {
		score, matched := palette_command_score(command, d.text)
		if matched {
			append(&d.matches, Palette_Match{index = index, score = score})
		}
	}
	//* The insertion index breaks the ties, so the order is the one the
	//* commands were added in when their scores are equal.
	slice.stable_sort_by(d.matches[:], palette_match_less)
	d.matches_dirty = false
}

command_palette_matches :: proc(d: ^Command_Palette_Data) -> []Palette_Match {
	if d == nil { return nil }
	if d.matches_dirty { command_palette_matches_build(d) }
	return d.matches[:]
}

Command_Palette_Count :: proc(g: ^GUI, id: Widget_ID) -> int {
	d := command_palette_data(g, id)
	if d == nil { return 0 }
	return len(command_palette_matches(d))
}

//* The command at a row of the ranked matches, or -1 when the row is out of
//* range. The rows are the ones the palette draws and selects.
Command_Palette_Match_Index :: proc(g: ^GUI, id: Widget_ID, row: int) -> int {
	d := command_palette_data(g, id)
	if d == nil { return -1 }
	matches := command_palette_matches(d)
	if row < 0 || row >= len(matches) { return -1 }
	return matches[row].index
}

command_palette_reset :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }
	d.matches_dirty = true
	d.selected = Command_Palette_Count(g, id) > 0 ? 0 : -1
	d.scroll = 0
}

//* Adds enabled program commands without replacing existing entries.
command_palette_sync :: proc(g: ^GUI, id: Widget_ID) {
	d := command_palette_data(g, id)
	if d == nil { return }
	for command in g.commands.list {
		if !command.enabled { continue }
		found := false
		for existing in d.commands {
			if existing.label == command.name {
				found = true
				break
			}
		}
		if !found {
			append(&d.commands, Palette_Command{
				label    = command.name,
				action   = command.action,
				keywords = command.name,
			})
		}
	}
	d.matches_dirty = true
	invalidate(g, id, Dirty_Flags{.Visual})
}

Command_Palette_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	if d := command_palette_data(g, id); d == nil || d.owner == INVALID_WIDGET_ID {
		command_palette_sync(g, id)
	}
	#partial switch &d in w.data {
	case Command_Palette_Data:
		d.visible = true
		delete(d.text)
		d.text = strings.clone("")
		d.selected = -1
		d.scroll = 0
		d.matches_dirty = true
	}
	popup_open_core(g, id)
}

Command_Palette_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Command_Palette_Data:
		d.visible = false
		d.selected = -1
	}
	Popup_Close(g, id)
}

Context_Menu_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil { return }
	#partial switch &d in w.data {
	case Context_Menu_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

Popup_Menu_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Popup_Menu_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

Dialog_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Dialog_Data:
		d.visible = true
		d.accepted = false
	}
	popup_open_core(g, id)
}

Dialog_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case Dialog_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}

File_Dialog_Open :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case File_Dialog_Data:
		d.visible = true
	}
	popup_open_core(g, id)
}

File_Dialog_Close :: proc(g: ^GUI, id: Widget_ID) {
	w := Widget_Get(g, id)
	if w == nil {return}
	#partial switch &d in w.data {
	case File_Dialog_Data:
		d.visible = false
	}
	Popup_Close(g, id)
}


overlay_contains_fold :: proc(haystack, needle: string) -> bool {
	if needle == "" { return true }
	n := len(needle)
	if n > len(haystack) { return false }
	for i in 0 ..= len(haystack) - n {
		if strings.equal_fold(haystack[i:i+n], needle) { return true }
	}
	return false
}


//* The scoring of the command palette: a case-insensitive subsequence match
//* with bonuses for the places a person would call good, so that a prefix
//* and a word boundary come before characters that are merely in order.



PALETTE_SCORE_BASE            :: 4
PALETTE_SCORE_PREFIX          :: 40
PALETTE_SCORE_WORD            :: 32
PALETTE_SCORE_CONSECUTIVE     :: 16
PALETTE_SCORE_CONSECUTIVE_RUN :: 3
PALETTE_SCORE_EXACT           :: 200
PALETTE_SCORE_GAP_MAX         :: 24
PALETTE_SCORE_LABEL_BONUS     :: 4096
PALETTE_SCORE_KEYWORD_OFFSET  :: 1024

palette_rune_equal_fold :: proc(a, b: rune) -> bool {
	return a == b || unicode.to_lower(a) == unicode.to_lower(b)
}

palette_is_ascii :: proc(text: string) -> bool {
	for b in text {
		if b >= 0x80 { return false }
	}
	return true
}

palette_ascii_fold :: proc(b: u8) -> u8 {
	if b >= 'A' && b <= 'Z' { return b + ('a' - 'A') }
	return b
}

palette_ascii_alnum :: proc(b: u8) -> bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9')
}

palette_ascii_word_boundary :: proc(text: string, offset: int) -> bool {
	if offset <= 0 { return true }
	previous := text[offset - 1]
	if !palette_ascii_alnum(previous) { return true }
	return previous >= 'a' && previous <= 'z' && text[offset] >= 'A' && text[offset] <= 'Z'
}

//* Whether the rune at the byte offset starts a word: the start of the
//* text, a rune that follows a separator, or the upper rune of a camel case.
palette_word_boundary :: proc(text: string, offset: int) -> bool {
	if offset <= 0 { return true }
	previous, size := utf8.decode_last_rune_in_string(text[:offset])
	if size == 0 { return true }
	current, _ := utf8.decode_rune_in_string(text[offset:])
	if !unicode.is_letter(previous) && !unicode.is_digit(previous) { return true }
	return unicode.is_lower(previous) && unicode.is_upper(current)
}

//* The ASCII scan of one start. Labels and filters are ASCII nearly always,
//* so this path avoids the decoding of runes on every comparison.
palette_search_score_ascii_from :: proc(haystack, needle: string, start: int) -> (score: int, matched: bool) {
	needle_at := 0
	haystack_at := start
	previous_end := -1
	run := 0
	first := true

	for needle_at < len(needle) {
		needle_byte := palette_ascii_fold(needle[needle_at])
		needle_at += 1

		found := -1
		for haystack_at < len(haystack) {
			if palette_ascii_fold(haystack[haystack_at]) == needle_byte {
				found = haystack_at
				break
			}
			haystack_at += 1
		}
		if found < 0 { return 0, false }

		score += PALETTE_SCORE_BASE

		if first {
			if found == 0 { score += PALETTE_SCORE_PREFIX }
			score -= min(found, PALETTE_SCORE_GAP_MAX)
			first = false
		}

		if palette_ascii_word_boundary(haystack, found) {
			score += PALETTE_SCORE_WORD
		}

		if found == previous_end {
			run += 1
			score += PALETTE_SCORE_CONSECUTIVE + min(run, 4) * PALETTE_SCORE_CONSECUTIVE_RUN
		} else {
			run = 0
			if previous_end >= 0 && found > previous_end {
				score -= min(found - previous_end, PALETTE_SCORE_GAP_MAX)
			}
		}

		previous_end = found + 1
		haystack_at = previous_end
	}

	return score, true
}

palette_search_score_ascii :: proc(haystack, needle: string) -> (score: int, matched: bool) {
	first := palette_ascii_fold(needle[0])
	best := 0
	found := false

	for start := 0; start < len(haystack); start += 1 {
		if palette_ascii_fold(haystack[start]) != first { continue }
		if candidate, candidate_matched := palette_search_score_ascii_from(haystack, needle, start); candidate_matched {
			if !found || candidate > best {
				best = candidate
				found = true
			}
		}
	}
	if !found { return 0, false }

	if len(haystack) == len(needle) {
		best += PALETTE_SCORE_EXACT
	}
	return best, true
}

//* Scores a case-insensitive subsequence match of `needle` in `haystack`
//* when the first rune of the needle is taken at `start`. Larger scores
//* match better. The scan walks the runes of both strings once.
palette_search_score_from :: proc(haystack, needle: string, start: int) -> (score: int, matched: bool) {
	needle_at := 0
	haystack_at := start
	previous_end := -1
	run := 0
	first := true

	for needle_at < len(needle) {
		needle_rune, needle_size := utf8.decode_rune_in_string(needle[needle_at:])
		if needle_size == 0 { return 0, false }
		needle_at += needle_size

		found := -1
		found_size := 0
		for haystack_at < len(haystack) {
			haystack_rune, haystack_size := utf8.decode_rune_in_string(haystack[haystack_at:])
			if haystack_size == 0 { break }
			if palette_rune_equal_fold(haystack_rune, needle_rune) {
				found = haystack_at
				found_size = haystack_size
				break
			}
			haystack_at += haystack_size
		}
		if found < 0 { return 0, false }

		score += PALETTE_SCORE_BASE

		if first {
			if found == 0 { score += PALETTE_SCORE_PREFIX }
			score -= min(found, PALETTE_SCORE_GAP_MAX)
			first = false
		}

		if palette_word_boundary(haystack, found) {
			score += PALETTE_SCORE_WORD
		}

		if found == previous_end {
			run += 1
			score += PALETTE_SCORE_CONSECUTIVE + min(run, 4) * PALETTE_SCORE_CONSECUTIVE_RUN
		} else {
			run = 0
			if previous_end >= 0 && found > previous_end {
				score -= min(found - previous_end, PALETTE_SCORE_GAP_MAX)
			}
		}

		previous_end = found + found_size
		haystack_at = previous_end
	}

	return score, true
}

//* Scores a case-insensitive subsequence match of `needle` in `haystack`.
//* Every place where the first rune of the needle occurs is tried, so that
//* a word boundary is not missed because an earlier rune also matched.
palette_search_score :: proc(haystack, needle: string) -> (score: int, matched: bool) {
	if needle == "" { return 0, true }
	if haystack == "" { return 0, false }

	if palette_is_ascii(haystack) && palette_is_ascii(needle) {
		return palette_search_score_ascii(haystack, needle)
	}

	first_rune, first_size := utf8.decode_rune_in_string(needle)
	if first_size == 0 { return 0, false }

	best := 0
	found := false
	for start := 0; start < len(haystack); {
		haystack_rune, haystack_size := utf8.decode_rune_in_string(haystack[start:])
		if haystack_size == 0 { break }
		if palette_rune_equal_fold(haystack_rune, first_rune) {
			if candidate, candidate_matched := palette_search_score_from(haystack, needle, start); candidate_matched {
				if !found || candidate > best {
					best = candidate
					found = true
				}
			}
		}
		start += haystack_size
	}
	if !found { return 0, false }

	if len(haystack) == len(needle) {
		best += PALETTE_SCORE_EXACT
	}
	return best, true
}

//* Scores a command for the filter. A match of the label is worth more than
//* a match of the keywords, because the label is what the row shows.
palette_command_score :: proc(command: Palette_Command, filter: string) -> (score: int, matched: bool) {
	if filter == "" { return 0, true }

	label_score, label_match := palette_search_score(command.label, filter)
	if label_match {
		return label_score + PALETTE_SCORE_LABEL_BONUS, true
	}

	if command.keywords != "" {
		keyword_score, keyword_match := palette_search_score(command.keywords, filter)
		if keyword_match {
			return keyword_score / 2 - PALETTE_SCORE_KEYWORD_OFFSET, true
		}
	}

	return 0, false
}

//* == The pattern of a text box ==
//* A pattern says which characters may go into a text box. It is a small
//* regular expression: the characters of the pattern are the characters
//* that are allowed, a group of them in brackets is a set of characters,
//* a dot is any character, and `|`, `*`, `+`, `?` and `{n,m}` say how
//* many of them there may be.
//*
//* The pattern is matched against one character at a time, so a pattern
//* that says `[0-9]` lets the digits in and nothing else, and a pattern
//* that says `\d{1,3}` lets up to three digits in.

package GUI

import "core:mem"
import "core:unicode/utf8"
import virt "core:mem/virtual"

Pattern_Class :: struct {
	negate: bool,
	ranges: [dynamic][2]rune,
}

Pattern_Term_Kind :: enum {
	Char,
	Any,
	Class,
	Group,
	Begin,
	End,
}

Pattern_Term :: struct {
	kind:  Pattern_Term_Kind,
	ch:    rune,
	class: Pattern_Class,
	alts:  [dynamic][dynamic]Pattern_Term,
	min:   int,
	max:   int,
}

Pattern_Parser :: struct {
	source: string,
	index:  int,
	alloc:  mem.Allocator,
}

Text_Pattern :: struct {
	terms:     [dynamic]Pattern_Term,
	allocator: mem.Allocator,
	ok:        bool,
}

pattern_class_make :: proc(alloc: mem.Allocator) -> Pattern_Class {
	return Pattern_Class{ranges = make([dynamic][2]rune, 0, 8, alloc)}
}

pattern_class_add :: proc(class: ^Pattern_Class, lo, hi: rune) {
	append(&class.ranges, [2]rune{lo, hi})
}

pattern_class_add_named :: proc(class: ^Pattern_Class, name: rune) -> bool {
	switch name {
	case 'd':
		pattern_class_add(class, '0', '9')
	case 'w':
		pattern_class_add(class, '0', '9')
		pattern_class_add(class, 'a', 'z')
		pattern_class_add(class, 'A', 'Z')
		pattern_class_add(class, '_', '_')
	case 's':
		pattern_class_add(class, '\t', '\r')
		pattern_class_add(class, ' ', ' ')
	case:
		return false
	}
	return true
}

pattern_class_has :: proc(class: ^Pattern_Class, r: rune) -> bool {
	found := false
	for range in class.ranges {
		if r >= range[0] && r <= range[1] {
			found = true
			break
		}
	}
	return class.negate ? !found : found
}

pattern_parse_sequence :: proc(p: ^Pattern_Parser) -> [dynamic]Pattern_Term {
	terms := make([dynamic]Pattern_Term, 0, 8, p.alloc)
	for p.index < len(p.source) {
		c := p.source[p.index]
		if c == ')' || c == '|' {break}
		term, ok := pattern_parse_term(p)
		if !ok {break}
		append(&terms, term)
	}
	return terms
}

pattern_parse_alternatives :: proc(p: ^Pattern_Parser) -> [dynamic][dynamic]Pattern_Term {
	alts := make([dynamic][dynamic]Pattern_Term, 0, 2, p.alloc)
	for {
		seq := pattern_parse_sequence(p)
		append(&alts, seq)
		if p.index < len(p.source) && p.source[p.index] == '|' {
			p.index += 1
			continue
		}
		break
	}
	return alts
}

pattern_parse_term :: proc(p: ^Pattern_Parser) -> (Pattern_Term, bool) {
	term := Pattern_Term{min = 1, max = 1}
	c := p.source[p.index]
	switch c {
	case '(':
		p.index += 1
		alts := pattern_parse_alternatives(p)
		if p.index < len(p.source) && p.source[p.index] == ')' {p.index += 1}
		term.kind = .Group
		term.alts = alts
	case '[':
		class, ok := pattern_parse_class(p)
		if !ok {return term, false}
		term.kind = .Class
		term.class = class
	case '.':
		p.index += 1
		term.kind = .Any
	case '^':
		p.index += 1
		term.kind = .Begin
	case '$':
		p.index += 1
		term.kind = .End
	case '\\':
		p.index += 1
		if p.index >= len(p.source) {return term, false}
		name, size := utf8.decode_rune_in_string(p.source[p.index:])
		p.index += size
		term.class = pattern_class_make(p.alloc)
		if pattern_class_add_named(&term.class, name) {
			term.kind = .Class
		} else {
			term.kind = .Char
			term.ch = name
		}
	case:
		r, size := utf8.decode_rune_in_string(p.source[p.index:])
		p.index += size
		term.kind = .Char
		term.ch = r
	}
	pattern_parse_quantifier(p, &term)
	return term, true
}

pattern_parse_class :: proc(p: ^Pattern_Parser) -> (Pattern_Class, bool) {
	class := pattern_class_make(p.alloc)
	p.index += 1
	if p.index < len(p.source) && p.source[p.index] == '^' {
		class.negate = true
		p.index += 1
	}
	first := true
	for p.index < len(p.source) {
		if p.source[p.index] == ']' && !first {
			p.index += 1
			return class, true
		}
		first = false
		lo, ok := pattern_class_item(p, &class)
		if !ok {return class, false}
		if p.index + 1 < len(p.source) && p.source[p.index] == '-' && p.source[p.index + 1] != ']' {
			p.index += 1
			hi, ok2 := pattern_class_item(p, &class)
			if !ok2 {return class, false}
			pattern_class_add(&class, lo, hi)
		} else {
			pattern_class_add(&class, lo, lo)
		}
	}
	return class, false
}

pattern_class_item :: proc(p: ^Pattern_Parser, class: ^Pattern_Class) -> (rune, bool) {
	if p.index >= len(p.source) {return 0, false}
	if p.source[p.index] == '\\' {
		p.index += 1
		if p.index >= len(p.source) {return 0, false}
		name, size := utf8.decode_rune_in_string(p.source[p.index:])
		p.index += size
		if pattern_class_add_named(class, name) {return '0', true}
		return name, true
	}
	r, size := utf8.decode_rune_in_string(p.source[p.index:])
	p.index += size
	return r, true
}

pattern_parse_quantifier :: proc(p: ^Pattern_Parser, term: ^Pattern_Term) {
	if p.index >= len(p.source) {return}
	c := p.source[p.index]
	switch c {
	case '*':
		term.min = 0
		term.max = -1
		p.index += 1
	case '+':
		term.min = 1
		term.max = -1
		p.index += 1
	case '?':
		term.min = 0
		term.max = 1
		p.index += 1
	case '{':
		start := p.index
		p.index += 1
		low := 0
		has_low := false
		for p.index < len(p.source) && p.source[p.index] >= '0' && p.source[p.index] <= '9' {
			low = low * 10 + int(p.source[p.index] - '0')
			has_low = true
			p.index += 1
		}
		if !has_low {p.index = start; return}
		high := -1
		if p.index < len(p.source) && p.source[p.index] == '}' {
			high = low
			p.index += 1
		} else if p.index < len(p.source) && p.source[p.index] == ',' {
			p.index += 1
			high = 0
			has_high := false
			for p.index < len(p.source) && p.source[p.index] >= '0' && p.source[p.index] <= '9' {
				high = high * 10 + int(p.source[p.index] - '0')
				has_high = true
				p.index += 1
			}
			if !has_high {high = -1}
			if p.index < len(p.source) && p.source[p.index] == '}' {
				p.index += 1
			} else {
				p.index = start
				return
			}
		} else {
			p.index = start
			return
		}
		term.min = low
		term.max = high
	}
}

pattern_positions :: proc(
	terms: []Pattern_Term,
	index: int,
	text: string,
	pos: int,
	alloc: mem.Allocator,
) -> [dynamic]int {
	if index >= len(terms) {
		out := make([dynamic]int, 0, 1, alloc)
		append(&out, pos)
		return out
	}
	middles := pattern_repeat(&terms[index], text, pos, alloc)
	out := make([dynamic]int, 0, 4, alloc)
	for middle in middles {
		tail := pattern_positions(terms, index + 1, text, middle, alloc)
		for t in tail {append(&out, t)}
	}
	return out
}

pattern_repeat :: proc(
	term: ^Pattern_Term,
	text: string,
	pos: int,
	alloc: mem.Allocator,
) -> [dynamic]int {
	ends := make([dynamic]int, 0, 4, alloc)
	frontier := make([dynamic]int, 0, 4, alloc)
	append(&frontier, pos)
	count := 0
	for {
		if count >= term.min {
			for p in frontier {append(&ends, p)}
		}
		if term.max >= 0 && count >= term.max {break}
		next := make([dynamic]int, 0, 4, alloc)
		for p in frontier {
			for e in pattern_atom(term, text, p, alloc) {append(&next, e)}
		}
		if len(next) == 0 {break}
		if pattern_same_set(next[:], frontier[:]) {break}
		frontier = next
		count += 1
	}
	return ends
}

pattern_same_set :: proc(a, b: []int) -> bool {
	for x in a {
		found := false
		for y in b {
			if x == y {found = true; break}
		}
		if !found {return false}
	}
	return true
}

pattern_atom :: proc(
	term: ^Pattern_Term,
	text: string,
	pos: int,
	alloc: mem.Allocator,
) -> [dynamic]int {
	out := make([dynamic]int, 0, 1, alloc)
	switch term.kind {
	case .Char:
		if pos < len(text) {
			r, size := utf8.decode_rune_in_string(text[pos:])
			if r == term.ch {append(&out, pos + size)}
		}
	case .Any:
		if pos < len(text) {
			_, size := utf8.decode_rune_in_string(text[pos:])
			append(&out, pos + size)
		}
	case .Class:
		if pos < len(text) {
			r, size := utf8.decode_rune_in_string(text[pos:])
			if pattern_class_has(&term.class, r) {append(&out, pos + size)}
		}
	case .Group:
		for alt in term.alts {
			for e in pattern_positions(alt[:], 0, text, pos, alloc) {append(&out, e)}
		}
	case .Begin:
		if pos == 0 {append(&out, pos)}
	case .End:
		if pos == len(text) {append(&out, pos)}
	}
	return out
}

pattern_compile :: proc(g: ^GUI, source: string) -> Text_Pattern {
	out := Text_Pattern{}
	if g == nil || source == "" {return out}
	alloc := virt.arena_allocator(&g.frame_arena)
	p := Pattern_Parser{source = source, index = 0, alloc = alloc}
	alts := pattern_parse_alternatives(&p)
	if p.index < len(source) {return out}
	terms := make([dynamic]Pattern_Term, 0, 1, alloc)
	if len(alts) == 1 {
		terms = alts[0]
	} else {
		append(&terms, Pattern_Term{kind = .Group, alts = alts, min = 1, max = 1})
	}
	out.terms = terms
	out.allocator = alloc
	out.ok = true
	return out
}

pattern_matches :: proc(pattern: ^Text_Pattern, text: string) -> bool {
	if !pattern.ok {return false}
	if len(pattern.terms) == 0 {return text == ""}
	ends := pattern_positions(pattern.terms[:], 0, text, 0, pattern.allocator)
	for e in ends {
		if e == len(text) {return true}
	}
	return false
}

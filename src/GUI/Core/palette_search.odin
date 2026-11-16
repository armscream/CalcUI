//* The scoring of the command palette: a case-insensitive subsequence match
//* with bonuses for the places a person would call good, so that a prefix
//* and a word boundary come before characters that are merely in order.

package Core

import "core:unicode"
import "core:unicode/utf8"

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

package support

import "strings"

// Collapses each run of whitespace in `css` to one space, so expected and actual output compare
// regardless of layout, but copies quoted strings, comments and escapes byte for byte: whitespace
// inside `"x  y"` is part of the value, and collapsing it let a parser that corrupted a string's
// contents pass. An escape keeps the one whitespace that ends a hex escape, so `.a\2E  b` (class
// `a.`, then a descendant `b`) is not read as `.a\2E b` (class `a.b`). Only double quotes open a
// string: the parser writes every string with them. CSS only: in JavaScript a regex or template
// literal would throw the string tracking off, which is why ContainCode keeps its plain collapse.
func normalizeCss(css string) string {
	var b strings.Builder
	space := false

	for i := 0; i < len(css); i++ {
		c := css[i]

		switch {
		case c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f':
			space = true
			continue
		case space && b.Len() > 0:
			b.WriteByte(' ')
		}
		space = false

		end := i + 1
		switch {
		case c == '\\':
			// A hex escape's terminator is written as one space, whichever whitespace it was, so
			// `\2E\t` and the parser's `\2E ` compare equal while `\2E  b` stays a descendant.
			end = escapeEnd(css, i)
			if hexEnd := hexEscapeEnd(css, i); hexEnd > i+1 && hexEnd < end {
				b.WriteString(css[i:hexEnd])
				b.WriteByte(' ')
				i = end - 1
				continue
			}
		case c == '"':
			for end < len(css) && css[end] != c {
				if css[end] == '\\' {
					end++
				}
				end++
			}
			end = min(end+1, len(css))
		case c == '/' && strings.HasPrefix(css[i:], "/*"):
			if j := strings.Index(css[i+2:], "*/"); j >= 0 {
				end = i + 2 + j + 2
			} else {
				end = len(css)
			}
		}

		b.WriteString(css[i:end])
		i = end - 1
	}

	return b.String()
}

// The end of the hex digits of the escape starting with the backslash at `i`, before any
// terminator.
func hexEscapeEnd(css string, i int) int {
	end := i + 1
	for end < len(css) && end-i <= 6 && isHex(css[end]) {
		end++
	}

	return end
}

// The end of the escape starting with the backslash at `i`: up to six hex digits and the one
// whitespace that terminates them (CRLF counting as one, as in CSS), or else the single escaped
// character.
func escapeEnd(css string, i int) int {
	end := hexEscapeEnd(css, i)
	if end == i+1 {
		return min(end+1, len(css))
	}
	switch {
	case strings.HasPrefix(css[end:], "\r\n"):
		end += 2
	case end < len(css) && strings.IndexByte(" \t\n\r\f", css[end]) >= 0:
		end++
	}

	return end
}

func isHex(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F'
}

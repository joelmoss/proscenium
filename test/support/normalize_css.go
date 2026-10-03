package support

import "strings"

// Collapses each run of whitespace in `css` to one space, so expected and actual output compare
// regardless of layout, but copies quoted strings and comments byte for byte: whitespace inside
// `"x  y"` is part of the value, and collapsing it let a parser that corrupted a string's contents
// pass. Comments are copied whole so an apostrophe in one does not open a string. CSS only: in
// JavaScript a regex or template literal would throw the string tracking off, which is why
// ContainCode keeps its plain collapse.
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
		case c == '"' || c == '\'':
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

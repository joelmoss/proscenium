package css

import (
	"joelmoss/proscenium/internal/types"
	"testing"
	"time"
)

// No CSS reaches the stream-end path in next(): terminateBody gives every body the semicolon a
// trailing `@mixin` needs. So the bodies go into the parser directly here, unterminated, to keep
// the cycle detection that path relies on tested. Removing a finished mixin from the stack while
// the one it included expanded hid the cycle, and two mixins including each other never ended.
func TestUnterminatedMixinsIncludingEachOtherEndWithACycleWarning(t *testing.T) {
	p := newCssParser("x{@mixin a;}", "/foo.css", &types.ConfigT{})
	p.mixins = cssMixins{"/foo.css#a": "@mixin b", "/foo.css#b": "@mixin a"}

	done := make(chan []CssWarning, 1)
	go func() {
		_, warnings, _ := p.parse()
		done <- warnings
	}()

	select {
	case warnings := <-done:
		if len(warnings) != 1 || warnings[0].Text != `Mixin "a" includes itself` {
			t.Fatalf("expected one cycle warning, got %v", warnings)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the parse did not end")
	}
}

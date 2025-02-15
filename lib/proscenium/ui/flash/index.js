import domMutations from "dom-mutations";
import { Sourdough, toast } from "sourdough-toast";

export function foo() {
  console.log("foo");
}

class HueFlash extends HTMLElement {
  static observedAttributes = ["data-flash-alert", "data-flash-notice"];

  connectedCallback() {
    this.#initSourdough();
  }

  async #initSourdough() {
    if ("sourdoughBooted" in window) return;

    const sourdough = new Sourdough({
      richColors: true,
      yPosition: "bottom",
      xPosition: "center",
    });
    sourdough.boot();
    window.sourdoughBooted = true;

    // Watch for changes to htl:flashes meta tag
    const flashesSelector = "meta[name='rails:flashes']";
    for await (const mutation of domMutations(document.head, {
      childList: true,
      subtree: true,
      attributes: true,
    })) {
      let $ele = null;

      if (
        mutation.type === "attributes" &&
        mutation.target.nodeName == "META" &&
        mutation.attributeName == "content"
      ) {
        $ele = mutation.target;
      } else if (mutation.type === "childList") {
        for (const node of mutation.addedNodes) {
          if (node.matches(flashesSelector)) {
            $ele = node;
            break;
          }
        }
      }

      if ($ele) {
        const flashes = JSON.parse($ele.getAttribute("content"));
        for (const [type, message] of Object.entries(flashes)) {
          if (type === "alert") {
            toast.error(message);
          } else if (type === "notice") {
            toast.success(message);
          }
        }
      }
    }
  }

  attributeChangedCallback(name, _oldValue, newValue) {
    this.#initSourdough();

    if (newValue === null) return;

    if (name === "data-flash-alert") {
      toast.warning(newValue);
    } else if (name === "data-flash-notice") {
      toast.success(newValue);
    }
  }
}

!customElements.get("pui-flash") &&
  customElements.define("pui-flash", HueFlash);

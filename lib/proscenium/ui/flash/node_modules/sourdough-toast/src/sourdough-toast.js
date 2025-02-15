// vim: foldmethod=marker

const DEFAULT_OPTIONS = {
  maxToasts: 3,
  duration: 4000,
  width: 356,
  gap: 14,
  theme: "light",
  viewportOffset: 32,
  expandedByDefault: false,
  yPosition: "bottom",
  xPosition: "right",
};

let toastsCounter = 0;

// {{{ Helpers
const SVG_NS = "http://www.w3.org/2000/svg";

const svgTags = ["svg", "path", "line", "circle"];

const h = (tag, props = {}, children = [], isSvg = false) => {
  const element =
    svgTags.includes(tag) || isSvg
      ? document.createElementNS(SVG_NS, tag)
      : document.createElement(tag);

  for (const [key, value] of Object.entries(props)) {
    if (key === "style") {
      if (typeof value === "string") {
        element.style = value;
      } else {
        for (const [k, v] of Object.entries(value)) {
          element.style.setProperty(k, v);
        }
      }
    } else if (key === "dataset") {
      for (const [k, v] of Object.entries(value)) {
        element.dataset[k] = v;
      }
    } else {
      element.setAttribute(key, value);
    }
  }

  for (const child of children) {
    if (typeof child === "string") {
      element.appendChild(document.createTextNode(child));
      continue;
    } else if (Array.isArray(child)) {
      for (const c of child) {
        element.appendChild(c);
      }
      continue;
    } else if (child instanceof HTMLElement || child instanceof SVGElement) {
      element.appendChild(child);
    }
  }

  return element;
};

const svgAttrs = {
  xmlns: "http://www.w3.org/2000/svg",
  viewBox: "0 0 24 24",
  height: "20",
  width: "20",
  fill: "none",
  stroke: "currentColor",
  "stroke-width": "1.5",
  "stroke-linecap": "round",
  "stroke-linejoin": "round",
  dataset: { slot: "icon" },
};

const icons = {
  success: h("svg", svgAttrs, [h("path", { d: "M20 6 9 17l-5-5" })]),
  info: h("svg", svgAttrs, [
    h("circle", { cx: "12", cy: "12", r: "10" }),
    h("path", { d: "M12 16v-4" }),
    h("path", { d: "M12 8h.01" }),
  ]),
  warning: h("svg", svgAttrs, [
    h("path", {
      d: "m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3",
    }),
    h("path", { d: "M12 9v4" }),
    h("path", { d: "M12 17h.01" }),
  ]),
  error: h("svg", svgAttrs, [
    h("circle", { cx: "12", cy: "12", r: "10" }),
    h("path", { d: "m4.9 4.9 14.2 14.2" }),
  ]),
  spinner: h(
    "svg",
    {
      ...svgAttrs,
      viewBox: "0 0 2400 2400",
      stroke: "black",
      "data-sourdough-spinner": "",
      "stroke-width": "200",
      "stroke-linecap": "round",
    },
    [
      h("line", { x1: "1200", y1: "600", x2: "1200", y2: "100" }),
      h("line", {
        opacity: "0.5",
        x1: "1200",
        y1: "2300",
        x2: "1200",
        y2: "1800",
      }),
      h("line", {
        opacity: "0.917",
        x1: "900",
        y1: "680.4",
        x2: "650",
        y2: "247.4",
      }),
      h("line", {
        opacity: "0.417",
        x1: "1750",
        y1: "2152.6",
        x2: "1500",
        y2: "1719.6",
      }),
      h("line", {
        opacity: "0.833",
        x1: "680.4",
        y1: "900",
        x2: "247.4",
        y2: "650",
      }),
      h("line", {
        opacity: "0.333",
        x1: "2152.6",
        y1: "1750",
        x2: "1719.6",
        y2: "1500",
      }),
      h("line", {
        opacity: "0.75",
        x1: "600",
        y1: "1200",
        x2: "100",
        y2: "1200",
      }),
      h("line", {
        opacity: "0.25",
        x1: "2300",
        y1: "1200",
        x2: "1800",
        y2: "1200",
      }),
      h("line", {
        opacity: "0.667",
        x1: "680.4",
        y1: "1500",
        x2: "247.4",
        y2: "1750",
      }),
      h("line", {
        opacity: "0.167",
        x1: "2152.6",
        y1: "650",
        x2: "1719.6",
        y2: "900",
      }),
      h("line", {
        opacity: "0.583",
        x1: "900",
        y1: "1719.6",
        x2: "650",
        y2: "2152.6",
      }),
      h("line", {
        opacity: "0.083",
        x1: "1750",
        y1: "247.4",
        x2: "1500",
        y2: "680.4",
      }),
    ],
  ),
};

function getDocumentDirection() {
  if (typeof window === "undefined") return "ltr";

  const dirAttribute = document.documentElement.getAttribute("dir");

  if (dirAttribute === "auto" || !dirAttribute) {
    return window.getComputedStyle(document.documentElement).direction;
  }

  return dirAttribute;
}
// }}}

// {{{ class Store
class Store extends EventTarget {
  #subscribers = [];

  constructor() {
    super();

    this.data = {
      toasts: [],
      expanded: false,
      interacting: false,
    };
  }

  subscribe = (fn) => {
    this.#subscribers.push(fn);

    return () => {
      this.#subscribers = this.#subscribers.filter((f) => f !== fn);
    };
  };

  #publish = () => {
    this.#subscribers.forEach((fn) => fn(this.data));
  };

  #set = (fn) => {
    const change = fn({ ...this.data });
    this.data = { ...this.data, ...change };
    this.#publish(this.data);
  };

  touch = () => {
    this.#publish();
  };

  create = (opts) => {
    const id = (toastsCounter++).toString();
    const toast = { id, ...opts };

    this.#set((data) => ({
      toasts: [...data.toasts, toast],
    }));
  };

  remove = (id) => {
    this.#set((data) => ({
      toasts: data.toasts.filter((t) => t.id !== id),
    }));
  };

  expand = () => {
    this.#set(() => ({ expanded: true }));
  };

  collapse = () => {
    this.#set(() => ({ expanded: false }));
  };

  focus = () => {
    this.#set(() => ({ interacting: true }));
  };

  blur = () => {
    this.#set(() => ({ interacting: false }));
  };
} // }}}

// {{{ class Toast
class Toast {
  constructor(sourdough, opts = {}) {
    this.sourdough = sourdough;
    this.opts = opts;

    this.paused = false;

    const children = [];

    let icon = null;
    if (opts.type) {
      switch (opts.type) {
        case "success":
          icon = icons.success;
          break;
        case "info":
          icon = icons.info;
          break;
        case "warning":
          icon = icons.warning;
          break;
        case "error":
          icon = icons.error;
          break;
      }
    }

    if (icon) {
      children.push(
        h("div", { dataset: { icon: "" } }, [icon.cloneNode(true)]),
      );
    }

    const contentChildren = [];

    const title = h("div", { dataset: { title: "" } }, opts.title);

    contentChildren.push(title);

    if (opts.description) {
      const description = h(
        "div",
        { dataset: { description: "" } },
        opts.description,
      );
      contentChildren.push(description);
    }

    const content = h("div", { dataset: { content: "" } }, contentChildren);

    children.push(content);

    const li = h(
      "li",
      {
        dataset: {
          sourdoughToast: "",
          expanded: sourdough.opts.expanded,
          styled: true,
          swiping: false,
          swipeOut: false,
          type: opts.type,
          yPosition: sourdough.opts.yPosition,
          xPosition: sourdough.opts.xPosition,
        },
        style: {},
      },
      [children],
    );

    this.element = li;
  }

  mount = () => {
    this.element.dataset.mounted = "true";

    this.initialHeight = this.element.offsetHeight;

    state.touch();

    this.timeLeft = this.sourdough.opts.duration;
    this.resume();
  };

  remove = () => {
    this.element.dataset.removed = "true";

    setTimeout(() => {
      this.element.remove();
      state.remove(this.opts.id);
    }, 400);
  };

  pause = () => {
    this.paused = true;
    this.timeLeft = this.timeLeft - (Date.now() - this.startedAt);
    clearTimeout(this.timer);
  };

  resume = () => {
    this.paused = false;
    this.startedAt = Date.now();
    this.timer = setTimeout(this.remove, this.timeLeft);
  };
}
// }}}

class Sourdough {
  constructor(opts = {}) {
    this.opts = Object.assign({}, DEFAULT_OPTIONS, opts);

    this.expanded = this.opts.expandedByDefault;
    if (this.opts.expandedByDefault) setTimeout(state.expand);

    // Cache rendered toasts by id
    this.renderedToastsById = {};

    this.list = h("ol", {
      dir: getDocumentDirection(),
      dataset: {
        sourdoughToaster: "",
        expanded: this.expanded,
        theme: this.opts.theme,
        richColors: this.opts.richColors,
        yPosition: this.opts.yPosition,
        xPosition: this.opts.xPosition,
      },
      style: {
        "--width": `${this.opts.width}px`,
        "--gap": `${this.opts.gap}px`,
        "--offset": `${this.opts.viewportOffset}px`,
      },
    });

    this.list.addEventListener("mouseenter", state.focus);
    this.list.addEventListener("mouseleave", state.blur);

    this.element = h(
      "div",
      {
        dataset: {
          sourdough: "",
          ...opts.dataset,
        },
      },
      [this.list],
    );

    this.subscription = state.subscribe(this.update.bind(this));
  }

  boot = () => {
    if (document.querySelector("[data-sourdough]")) {
      return;
    }
    document.body.appendChild(this.element);
  };

  update = (state) => {
    this.expanded = state.expanded || state.interacting;
    this.list.dataset.expanded = this.expanded;

    // Get first X toasts
    const toasts = state.toasts.slice(-this.opts.maxToasts);

    // Render and cache toasts that haven't been rendered yet
    const renderedIds = [];
    const toastsToRender = toasts.reduce((coll, t) => {
      renderedIds.push(t.id);
      coll.push(this.renderedToastsById[t.id] || this.createToast(t));
      return coll;
    }, []);

    // Uncache and remove toast elements that are not to be rendered
    Object.keys(this.renderedToastsById).forEach((id) => {
      if (!renderedIds.includes(id)) {
        this.renderedToastsById[id].element.remove();
        delete this.renderedToastsById[id];
      }
    });

    const front = toastsToRender[toastsToRender.length - 1];

    if (front) {
      this.list.style.setProperty(
        "--front-toast-height",
        `${front.element.offsetHeight}px`,
      );
    }

    for (const [index, t] of toastsToRender.entries()) {
      if (t.paused && !state.interacting) {
        t.resume();
      } else if (!t.paused && state.interacting) {
        t.pause();
      }

      t.element.dataset.index = index;
      t.element.dataset.front = t === front;
      t.element.dataset.expanded = this.expanded;

      t.element.style.setProperty("--index", index);
      t.element.style.setProperty(
        "--toasts-before",
        toastsToRender.length - index - 1,
      );
      t.element.style.setProperty("--z-index", index);

      t.element.style.setProperty(
        "--initial-height",
        this.expanded ? "auto" : `${t.initialHeight}px`,
      );

      // Calculate offset by adding all the heights of the toasts before
      // the current one + the gap between them.
      // Note: We're calculating the total height once per loop which is
      // not ideal.
      const [heightBefore, totalHeight] = toastsToRender.reduce(
        ([before, total], t, i) => {
          const boxHeight = t.initialHeight + this.opts.gap;
          if (i < index) before += boxHeight;
          total += boxHeight;
          return [before, total];
        },
        [0, 0],
      );

      const offset =
        totalHeight - heightBefore - t.initialHeight - this.opts.gap;
      t.element.style.setProperty(
        "--offset",
        `${t.element.dataset.removed ? "0" : offset || 0}px`,
      );
    }
  };

  createToast = (opts) => {
    const toast = new Toast(this, opts);
    this.renderedToastsById[opts.id] = toast;
    this.list.appendChild(toast.element);

    setTimeout(toast.mount, 0);

    return toast;
  };
}

const state = new Store();

const toast = (title) => {
  state.create({ title });
};
toast.message = ({ title, description, ...opts }) => {
  state.create({ title, description, ...opts });
};
toast.success = (title, opts = {}) => {
  state.create({ title, type: "success", ...opts });
};
toast.info = (title, opts = {}) => {
  state.create({ title, type: "info", ...opts });
};
toast.warning = (title, opts = {}) => {
  state.create({ title, type: "warning", ...opts });
};
toast.error = (title, opts = {}) => {
  state.create({ title, type: "error", ...opts });
};

export { toast, Sourdough };

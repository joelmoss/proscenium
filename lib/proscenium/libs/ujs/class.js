import DataConfirm from "./data_confirm";
import DataDisableWith from "./data_disable_with";

export default class UJS {
  constructor() {
    this.dc = new DataConfirm();
    this.ddw = new DataDisableWith();

    document.addEventListener("submit", this, { capture: true });
  }

  handleEvent(event) {
    this.dc.onSubmit(event) && this.ddw.onSubmit(event);
  }
}

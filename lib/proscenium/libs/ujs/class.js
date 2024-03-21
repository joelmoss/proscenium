import DataConfirm from "./data_confirm";
import DataDisableWith from "./data_disable_with";

export default class UJS {
  constructor() {
    const dc = new DataConfirm();
    const ddw = new DataDisableWith();

    document.body.addEventListener(
      "submit",
      (event) => {
        dc.onSubmit(event) && ddw.onSubmit(event);
      },
      { capture: true }
    );
  }
}

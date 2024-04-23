export default class DataConfirm {
  onSubmit = (event) => {
    if (
      !event.target.matches("[data-turbo=true]") &&
      event.submitter &&
      "confirm" in event.submitter.dataset
    ) {
      const v = event.submitter.dataset.confirm;

      if (
        v !== "false" &&
        !confirm(v === "true" || v === "" ? "Are you sure?" : v)
      ) {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
        return false;
      }
    }

    return true;
  };
}

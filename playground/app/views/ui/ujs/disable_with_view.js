import startUJS from "@proscenium/ujs";
import CustomElement from "@proscenium/custom_element";
startUJS();

class UjsDisableWith extends CustomElement {
  static delegatedEvents = ["submit"];

  handleEvent(event) {
    event.preventDefault();

    if (event.target.id === "my-form") {
      setTimeout(() => {
        event.submitter.resetDisableWith();
      }, 1000);
    }
  }
}
UjsDisableWith.register();

import startUJS from "@proscenium/ujs";
import CustomElement from "@proscenium/custom_element";
startUJS();

class UjsConfirm extends CustomElement {
  static delegatedEvents = ["submit"];

  handleEvent(event) {
    event.preventDefault();
  }
}
UjsConfirm.register();

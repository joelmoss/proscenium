import { Maskito } from "https://esm.sh/@maskito/core@2.2.0";
import { maskitoPhoneOptionsGenerator } from "https://esm.sh/@maskito/phone@2.2.0";
import parsePhoneNumber from "https://esm.sh/libphonenumber-js@1.10.60/min";
import metadata from "https://esm.sh/libphonenumber-js@1.10.60/min/metadata";

class TelField extends HTMLElement {
  connectedCallback() {
    this.$country = this.querySelector("[part='country']");
    this.$select = this.querySelector("select");
    this.$input = this.querySelector("input");

    this.#initMask();
    this.#setFlag(this.$select.querySelector("option:checked").value);

    this.$select.addEventListener("change", this);
  }

  handleEvent(event) {
    event.type === "change" && this.#onSelectChange(event);
  }

  #onSelectChange = ({ target }) => {
    this.#setFlag(target.value);
    this.#resetMask();
  };

  #setFlag(country) {
    this.$country.style.setProperty(
      "--flag-position",
      `var(--flag-${country.toLowerCase()})`
    );
  }

  #initMask() {
    this.mask = new Maskito(
      this.$input,
      maskitoPhoneOptionsGenerator({
        countryIsoCode: this.$select.value,
        metadata,
      })
    );

    if (this.$input.value !== "") {
      const phone = parsePhoneNumber(this.$input.value, this.$select.value, {
        extract: false,
      });
      this.$input.value = phone.format("INTERNATIONAL");

      if (phone.country) {
        this.$select.value = phone.country;
        this.#setFlag(phone.country);
      }
    }
  }

  #resetMask() {
    this.mask.destroy();
    this.mask = new Maskito(
      this.$input,
      maskitoPhoneOptionsGenerator({
        countryIsoCode: this.$select.value,
        strict: true,
        metadata,
      })
    );

    // Update country prefix
    if (this.$input.value !== "") {
      let phone = parsePhoneNumber(this.$input.value, this.$select.value, {
        extract: false,
      });
      phone = parsePhoneNumber(phone.nationalNumber, this.$select.value);
      this.$input.value = phone.format("INTERNATIONAL");
    }
  }

  disconnectedCallback() {
    this.mask.destroy();
    this.$select.removeEventListener("change", this);
  }
}

customElements.define("pui-tel-field", TelField);

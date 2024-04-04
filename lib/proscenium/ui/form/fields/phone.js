import { Maskito } from '@maskito/core'
import { maskitoPhoneOptionsGenerator } from '@maskito/phone'
import parsePhoneNumber from 'libphonenumber-js/min'
import metadata from 'libphonenumber-js/min/metadata'

class PhoneField extends HTMLElement {
  constructor() {
    super()
  }

  connectedCallback() {
    this.$select = this.querySelector('select')
    this.$input = this.querySelector('input')
    this.#initMask()

    this.$select.addEventListener('change', this.#onSelectChange)
  }

  #onSelectChange = ({ target }) => {
    target.nextSibling.dataset.countryCode = target.value.toLowerCase()
    this.#resetMask()
  }

  #initMask() {
    this.mask = new Maskito(
      this.$input,
      maskitoPhoneOptionsGenerator({
        countryIsoCode: this.$select.value,
        metadata
      })
    )

    if (this.$input.value !== '') {
      const phone = parsePhoneNumber(this.$input.value, this.$select.value, { extract: false })
      this.$input.value = phone.format('INTERNATIONAL')

      if (phone.country) {
        this.$select.value = phone.country
        this.$select.nextSibling.dataset.countryCode = phone.country.toLowerCase()
      }
    }
  }

  #resetMask() {
    this.mask.destroy()
    this.mask = new Maskito(
      this.$input,
      maskitoPhoneOptionsGenerator({
        countryIsoCode: this.$select.value,
        strict: true,
        metadata
      })
    )

    // Update country prefix
    if (this.$input.value !== '') {
      let phone = parsePhoneNumber(this.$input.value, this.$select.value, { extract: false })
      phone = parsePhoneNumber(phone.nationalNumber, this.$select.value)
      this.$input.value = phone.format('INTERNATIONAL')
    }
  }

  disconnectedCallback() {
    this.mask.destroy()
    this.$select.removeEventListener('change', this.onSelectChange)
  }
}

customElements.define('phone-field', PhoneField)

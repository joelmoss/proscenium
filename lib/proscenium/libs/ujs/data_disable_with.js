export default class DataDisableWith {
  onSubmit = event => {
    const target = event.target
    const formId = target.id

    if (target.matches('[data-turbo=true]')) return

    const submitElements = Array.from(
      target.querySelectorAll(
        ['input[type=submit][data-disable-with]', 'button[type=submit][data-disable-with]'].join(
          ', '
        )
      )
    )

    submitElements.push(
      ...Array.from(
        document.querySelectorAll(
          [
            `input[type=submit][data-disable-with][form='${formId}']`,
            `button[type=submit][data-disable-with][form='${formId}']`
          ].join(', ')
        )
      )
    )

    for (const ele of submitElements) {
      if (ele.hasAttribute('form') && ele.getAttribute('form') !== target.id) continue

      this.#disableButton(ele)
    }
  }

  #disableButton(ele) {
    const defaultTextValue = 'Please wait...'
    let textValue = ele.dataset.disableWith || defaultTextValue
    if (textValue === 'false') return
    if (textValue === 'true') {
      textValue = defaultTextValue
    }

    ele.disabled = true

    if (ele.matches('button')) {
      ele.dataset.valueBeforeDisabled = ele.innerHTML
      ele.innerHTML = textValue
    } else {
      ele.dataset.valueBeforeDisabled = ele.value
      ele.value = textValue
    }

    if (ele.resetDisableWith === undefined) {
      // This function can be called on the element to reset the disabled state. Useful for when
      // form submission fails, and the button should be re-enabled.
      ele.resetDisableWith = function () {
        this.disabled = false

        if (this.matches('button')) {
          this.innerHTML = this.dataset.valueBeforeDisabled
        } else {
          this.value = this.dataset.valueBeforeDisabled
        }

        delete this.dataset.valueBeforeDisabled
      }
    }
  }
}

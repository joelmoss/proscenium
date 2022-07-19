/* eslint-disable no-console */

import renderComponent from `/proscenium-runtime/component_manager/render_component.js`

document.addEventListener('DOMContentLoaded', () => {
  const elements = document.querySelectorAll('[data-component]')

  if (elements.length < 1) return

  Array.from(elements, (ele) => {
    const data = JSON.parse(ele.getAttribute('data-component'))

    let isVisible = false
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!isVisible && entry.isIntersecting) {
          isVisible = true
          observer.unobserve(ele)

          renderComponent(ele, data)
        }
      })
    })

    observer.observe(ele)
  })
})

/* eslint-disable no-console */

export async function init() {
  const elements = document.querySelectorAll('[data-component]')

  if (elements.length < 1) return

  const { default: renderComponent } = await import(`./render_component`)

  Array.from(elements, ele => {
    const data = JSON.parse(ele.getAttribute('data-component'))

    let isVisible = false
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!isVisible && entry.isIntersecting) {
          isVisible = true
          observer.unobserve(ele)

          renderComponent(ele, data)
        }
      })
    })

    observer.observe(ele)
  })
}

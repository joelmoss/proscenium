import { createConsumer } from '@rails/actioncable'

export default socketPath => {
  const uid = (Date.now() + ((Math.random() * 100) | 0)).toString()
  const consumer = createConsumer(`${socketPath}?uid=${uid}`)

  consumer.subscriptions.create('Proscenium::ReloadChannel', {
    received: debounce(
      () => {
        console.log('[Proscenium] Files changed; reloading...')
        location.reload()
      },
      200,
      true
    ),

    connected() {
      console.log('[Proscenium] Auto-reload websocket connected')
    },

    disconnected() {
      console.log('[Proscenium] Auto-reload websocket disconnected')
    }
  })
}

function debounce(func, wait, immediate) {
  let timeout

  return function () {
    const args = arguments

    const later = () => {
      timeout = null
      !immediate && func.apply(this, args)
    }

    const callNow = immediate && !timeout
    clearTimeout(timeout)
    timeout = setTimeout(later, wait)

    callNow && func.apply(this, args)
  }
}

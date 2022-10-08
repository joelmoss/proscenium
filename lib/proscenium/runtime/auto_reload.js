import { createConsumer } from 'https://esm.sh/@rails/actioncable@6.0.5'
import debounce from 'https://esm.sh/debounce@1.2.1'

export default socketPath => {
  const uid = (Date.now() + ((Math.random() * 100) | 0)).toString()
  const consumer = createConsumer(`${socketPath}?uid=${uid}`)

  consumer.subscriptions.create('Proscenium::ReloadChannel', {
    received: debounce(() => {
      console.log('[Proscenium] Files changed; reloading...')
      location.reload()
    }, 200),

    connected() {
      console.log('[Proscenium] Auto-reload websocket connected')
    },

    disconnected() {
      console.log('[Proscenium] Auto-reload websocket disconnected')
    }
  })
}

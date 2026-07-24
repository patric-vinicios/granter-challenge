import type { Pinia } from 'pinia'
import { createApp, type App } from 'vue'

interface WithSetupOptions {
  pinia?: Pinia
}

interface SetupResult<T> {
  app: App
  result: T
  unmount: () => void
}

export function withSetup<T>(
  composable: () => T,
  { pinia }: WithSetupOptions = {},
): SetupResult<T> {
  let result: T | undefined
  const host = document.createElement('div')
  const app = createApp({
    setup() {
      result = composable()
      return () => null
    },
  })

  if (pinia) {
    app.use(pinia)
  }

  document.body.append(host)
  app.mount(host)

  if (result === undefined) {
    throw new Error('Composable did not return a result during setup')
  }

  return {
    app,
    result,
    unmount: () => {
      app.unmount()
      host.remove()
    },
  }
}

import { screen } from '@testing-library/vue'
import { describe, expect, it } from 'vitest'

import { renderWithApp } from '@/test/render'

import App from './App.vue'

describe('App', () => {
  it('renders the active route as the application composition root', async () => {
    await renderWithApp(App, {
      initialRoute: '/inbox',
      routes: [
        {
          path: '/inbox',
          component: { template: '<main>Inbox route</main>' },
        },
      ],
    })

    expect(screen.getByRole('main').textContent).toBe('Inbox route')
  })
})

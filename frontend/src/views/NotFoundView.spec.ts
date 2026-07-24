import userEvent from '@testing-library/user-event'
import { screen } from '@testing-library/vue'
import { describe, expect, it } from 'vitest'

import { renderWithApp } from '@/test/render'

import NotFoundView from './NotFoundView.vue'

describe('NotFoundView', () => {
  it('explains the missing route and returns to the inbox', async () => {
    const user = userEvent.setup()
    const { router } = await renderWithApp(NotFoundView, {
      initialRoute: '/missing',
      routes: [
        { path: '/missing', component: NotFoundView },
        { path: '/inbox', component: { template: '<main>Inbox carregado</main>' } },
      ],
    })

    expect(
      screen.getByRole('heading', { name: 'Pagina nao encontrada' }),
    ).toBeTruthy()
    expect(screen.getByText('O endereco acessado nao existe no Granter Chat.')).toBeTruthy()

    await user.click(screen.getByRole('link', { name: 'Voltar para o inbox' }))

    expect(router.currentRoute.value.path).toBe('/inbox')
  })
})

import userEvent from '@testing-library/user-event'
import { screen, waitFor } from '@testing-library/vue'
import { describe, expect, it, vi } from 'vitest'
import type { RouteRecordRaw } from 'vue-router'

import { renderWithApp } from '@/test/render'

import RegisterView from './RegisterView.vue'

const routes: RouteRecordRaw[] = [
  { path: '/', component: { template: '<main>Login</main>' } },
  { path: '/cadastrar', component: RegisterView },
  { path: '/inbox', component: { template: '<main>Inbox</main>' } },
]

describe('RegisterView', () => {
  it('registers an account, stores the session and navigates to the inbox', async () => {
    const user = userEvent.setup()
    const { router } = await renderWithApp(RegisterView, { routes, initialRoute: '/cadastrar' })
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(201, {
        user: {
          id: 'user-1',
          username: 'anabeatriz',
          name: 'Ana Beatriz',
          last_seen_at: null,
        },
        token: 'new-token',
        expires_at: '2026-07-30T12:00:00Z',
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    await user.type(screen.getByLabelText('Nome'), 'Ana Beatriz')
    await user.type(screen.getByLabelText('Usuario'), '@anabeatriz')
    await user.type(screen.getByLabelText('Senha'), 'senha123456')
    await user.click(screen.getByRole('button', { name: 'Criar conta' }))

    await waitFor(() => {
      expect(router.currentRoute.value.path).toBe('/inbox')
    })

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/auth/register',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          name: 'Ana Beatriz',
          username: '@anabeatriz',
          password: 'senha123456',
        }),
      }),
    )
    expect(window.localStorage.getItem('granter.session')).toContain('new-token')
  })

  it('renders validation fields from the backend error envelope', async () => {
    const user = userEvent.setup()
    await renderWithApp(RegisterView, { routes, initialRoute: '/cadastrar' })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(422, {
          errors: {
            code: 'validation_error',
            detail: 'The request could not be processed',
            fields: {
              username: ['has already been taken'],
              password: ['should be at least 8 character(s)'],
            },
          },
        }),
      ),
    )

    await user.type(screen.getByLabelText('Nome'), 'Ana Beatriz')
    await user.type(screen.getByLabelText('Usuario'), 'anabeatriz')
    await user.type(screen.getByLabelText('Senha'), 'curta')
    await user.click(screen.getByRole('button', { name: 'Criar conta' }))

    expect(await screen.findByText('já está em uso')).toBeTruthy()
    expect(screen.getByText('deve ter pelo menos 8 caracteres')).toBeTruthy()
    expect(screen.getByRole('alert').textContent).toContain('A solicitação não pôde ser processada.')
  })
})

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

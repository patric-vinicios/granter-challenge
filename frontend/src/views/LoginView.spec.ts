import userEvent from '@testing-library/user-event'
import { screen, waitFor } from '@testing-library/vue'
import { describe, expect, it, vi } from 'vitest'
import type { RouteRecordRaw } from 'vue-router'

import { renderWithApp } from '@/test/render'

import LoginView from './LoginView.vue'

const routes: RouteRecordRaw[] = [
  { path: '/', component: LoginView },
  { path: '/inbox', component: { template: '<main>Inbox</main>' } },
  { path: '/cadastrar', component: { template: '<main>Cadastro</main>' } },
]

describe('LoginView', () => {
  it('logs in, stores the returned session and navigates on submit', async () => {
    const user = userEvent.setup()
    const { router } = await renderWithApp(LoginView, { routes })
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        user: {
          id: 'user-1',
          username: 'anabeatriz',
          name: 'Ana Beatriz',
          last_seen_at: null,
        },
        token: 'jwt-token',
        expires_at: '2026-07-30T12:00:00Z',
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const username = screen.getByLabelText('Usuario')
    const password = screen.getByLabelText('Senha')

    await user.type(username, 'anabeatriz')
    await user.type(password, 'segredo')

    expect(screen.getByDisplayValue('anabeatriz')).toBe(username)
    expect(screen.getByDisplayValue('segredo')).toBe(password)
    expect(password.getAttribute('type')).toBe('password')

    await user.click(screen.getByRole('button', { name: 'Mostrar senha' }))
    expect(password.getAttribute('type')).toBe('text')
    expect(screen.getByRole('button', { name: 'Ocultar senha' })).toBeTruthy()

    await user.click(screen.getByRole('button', { name: 'Entrar' }))

    await waitFor(() => {
      expect(router.currentRoute.value.path).toBe('/inbox')
    })

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/auth/login',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ username: 'anabeatriz', password: 'segredo' }),
      }),
    )
    expect(window.localStorage.getItem('granter.session')).toContain('jwt-token')
  })

  it('shows invalid credential errors without navigating', async () => {
    const user = userEvent.setup()
    const { router } = await renderWithApp(LoginView, { routes })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(401, {
          errors: {
            code: 'invalid_credentials',
            detail: 'Invalid username or password',
          },
        }),
      ),
    )

    await user.type(screen.getByLabelText('Usuario'), 'anabeatriz')
    await user.type(screen.getByLabelText('Senha'), 'errada')
    await user.click(screen.getByRole('button', { name: 'Entrar' }))

    expect((await screen.findByRole('alert')).textContent).toContain('Usuário ou senha inválidos.')
    expect(router.currentRoute.value.path).toBe('/')
  })
})

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

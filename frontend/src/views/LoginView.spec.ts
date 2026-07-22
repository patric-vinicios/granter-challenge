import userEvent from '@testing-library/user-event'
import { screen, waitFor } from '@testing-library/vue'
import { describe, expect, it } from 'vitest'
import type { RouteRecordRaw } from 'vue-router'

import { renderWithApp } from '@/test/render'

import LoginView from './LoginView.vue'

const routes: RouteRecordRaw[] = [
  { path: '/', component: LoginView },
  { path: '/inbox', component: { template: '<main>Inbox</main>' } },
  { path: '/cadastrar', component: { template: '<main>Cadastro</main>' } },
]

describe('LoginView', () => {
  it('updates its fields, reveals the password and navigates on submit', async () => {
    const user = userEvent.setup()
    const { router } = await renderWithApp(LoginView, { routes })

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
  })
})

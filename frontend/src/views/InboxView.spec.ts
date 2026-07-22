import { screen, within } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'

import { renderWithApp } from '@/test/render'

import InboxView from './InboxView.vue'

const routes = [
  {
    path: '/',
    component: { template: '<div>Login</div>' },
  },
  {
    path: '/inbox',
    component: InboxView,
  },
]

async function renderInbox() {
  return renderWithApp(InboxView, { routes, initialRoute: '/inbox' })
}

describe('InboxView', () => {
  it('shows the default conversation and switches to another conversation', async () => {
    const user = userEvent.setup()

    await renderInbox()

    expect(screen.getByText('visto por ultimo ha 5 min')).toBeTruthy()
    expect(screen.getByText('Perfeito, fico no aguardo entao')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /time de produto/i }))

    expect(screen.getByText('5 membros · Voce, Rafael, Ana, +2')).toBeTruthy()
    expect(screen.getByText('Bom dia pessoal! Subi a build de staging pra validacao')).toBeTruthy()
    expect(screen.getAllByText('Rafael Alves')).toHaveLength(2)
  })

  it('opens contacts and reports add-contact success and error states', async () => {
    const user = userEvent.setup()

    await renderInbox()

    await user.click(screen.getByRole('button', { name: /contatos/i }))

    expect(screen.getByText('Contatos')).toBeTruthy()
    expect(screen.getByText('@rafaelalves')).toBeTruthy()

    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const dialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    const usernameInput = within(dialog).getByLabelText(/usuario/i)

    await user.type(usernameInput, '@anabeatriz')
    await user.click(within(dialog).getByRole('button', { name: /adicionar/i }))

    expect(within(dialog).getByText(/contato adicionado/i)).toBeTruthy()

    await user.click(within(dialog).getByRole('button', { name: /voltar/i }))
    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const reopenedDialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    await user.type(within(reopenedDialog).getByLabelText(/usuario/i), '@fulano123')
    await user.click(within(reopenedDialog).getByRole('button', { name: /adicionar/i }))

    expect(within(reopenedDialog).getByText(/usuario nao encontrado/i)).toBeTruthy()
  })

  it('opens conversation search and clears the draft when sending', async () => {
    const user = userEvent.setup()

    await renderInbox()

    await user.click(screen.getByRole('button', { name: /buscar na conversa/i }))

    expect(screen.getByLabelText(/buscar na conversa/i)).toBeTruthy()
    expect(screen.getByText('1 / 1')).toBeTruthy()

    const messageInput = screen.getByLabelText(/^mensagem$/i) as HTMLTextAreaElement

    await user.type(messageInput, 'Mensagem de teste')
    await user.click(screen.getByRole('button', { name: /enviar mensagem/i }))

    expect(messageInput.value).toBe('')
  })
})

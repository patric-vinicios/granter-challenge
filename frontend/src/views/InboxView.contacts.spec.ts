import { fireEvent, screen, within } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, it, expect, vi } from 'vitest'

import { useContactsStore } from '@/features/contacts/contacts.store'

import {
  authenticate,
  contactResponse,
  historyResponse,
  jsonResponse,
  mockAuthenticatedFetch,
  privateConversationResponse,
  renderInbox,
  resetInboxHarness,
} from './inbox/inboxTestHarness'

describe('Inbox contacts', () => {
  beforeEach(resetInboxHarness)

  it('opens contacts and reports add-contact success and error states', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [
        contactResponse('contact-rafael', 'user-rafael', 'rafaelalves', 'Rafael Alves'),
        contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      ],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))

    expect(screen.getByText('Contatos')).toBeTruthy()
    expect(await screen.findByText('@rafaelalves')).toBeTruthy()
    const contactSearch = screen.getByLabelText(/buscar contato/i)
    await fireEvent.update(contactSearch, 'ana')
    expect(screen.getByText('@anabeatriz')).toBeTruthy()
    expect(screen.getByText('@rafaelalves')).toBeTruthy()
    await fireEvent.update(contactSearch, '')
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )

    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const dialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    const usernameInput = within(dialog).getByLabelText(/usuario/i)
    expect(document.activeElement).toBe(usernameInput)

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        contact: contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
      }),
    )

    await user.type(usernameInput, '@anabeatriz')
    await user.click(within(dialog).getByRole('button', { name: /adicionar/i }))

    expect(await within(dialog).findByText(/contato adicionado/i)).toBeTruthy()
    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ username: '@anabeatriz' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
          'Content-Type': 'application/json',
        }),
      }),
    )
    expect(screen.getByText('@carlos')).toBeTruthy()

    await user.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: /adicionar contato/i })).toBeNull()
    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const reopenedDialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    fetchMock.mockResolvedValueOnce(
      jsonResponse(404, {
        errors: {
          code: 'user_not_found',
          detail: 'No user with @fulano123 exists in the system',
        },
      }),
    )

    await user.type(within(reopenedDialog).getByLabelText(/usuario/i), '@fulano123')
    await user.click(within(reopenedDialog).getByRole('button', { name: /adicionar/i }))

    expect(await within(reopenedDialog).findByText(/usuario nao encontrado/i)).toBeTruthy()

    fetchMock.mockResolvedValueOnce(jsonResponse(204, null))
    await user.click(screen.getByRole('button', { name: /remover rafael alves/i }))

    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://localhost:4000/api/contacts/contact-rafael',
      expect.objectContaining({
        method: 'DELETE',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(screen.queryByText('@rafaelalves')).toBeNull()
  })

  it('requires a username before requesting a new contact', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({})
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await user.click(screen.getByRole('button', { name: /adicionar/i }))

    const dialog = screen.getByRole('dialog', { name: /adicionar contato/i })
    await user.click(within(dialog).getByRole('button', { name: /adicionar/i }))

    expect(within(dialog).getByText('Usuario obrigatorio')).toBeTruthy()
    expect(within(dialog).getByText('Informe o @usuario que deseja adicionar.')).toBeTruthy()
    expect(fetchMock).not.toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({ method: 'POST' }),
    )
  })

  it('opens a private conversation from a contact', async () => {
    const user = userEvent.setup()

    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(201, {
        conversation: privateConversationResponse('conversation-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz'),
      }),
    )
    fetchMock.mockResolvedValueOnce(historyResponse())

    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/private',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ user_id: 'user-ana' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/conversations/conversation-ana/messages?limit=30',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
    expect(await screen.findByText('Conversa iniciada')).toBeTruthy()
    expect(screen.getByText('Nenhuma mensagem nesta conversa.')).toBeTruthy()
  })

  it('preserves contact state and reports removal failures', async () => {
    const user = userEvent.setup()
    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(500, {
        errors: { code: 'internal_error', detail: 'Something went wrong' },
      }),
    )
    await user.click(screen.getByRole('button', { name: /remover ana beatriz/i }))

    expect((await screen.findByRole('alert')).textContent).toContain(
      'Não foi possível remover o contato.',
    )
    expect(useContactsStore(pinia).contacts.map((contact) => contact.id)).toContain(
      'contact-ana',
    )
  })

  it('keeps the contacts panel open when a private conversation cannot be opened', async () => {
    const user = userEvent.setup()
    const { pinia } = await renderInbox()
    const fetchMock = mockAuthenticatedFetch({
      contacts: [contactResponse('contact-ana', 'user-ana', 'anabeatriz', 'Ana Beatriz')],
    })
    vi.stubGlobal('fetch', fetchMock)
    authenticate(pinia)

    await user.click(screen.getByRole('button', { name: /contatos/i }))
    await screen.findByText('@anabeatriz')

    fetchMock.mockResolvedValueOnce(
      jsonResponse(403, {
        errors: {
          code: 'forbidden',
          detail: 'You are not allowed to perform this action',
        },
      }),
    )
    await user.click(screen.getByRole('button', { name: /abrir conversa com ana beatriz/i }))

    expect((await screen.findByRole('alert')).textContent).toContain(
      'Você não tem permissão para executar esta ação.',
    )
    expect(screen.getByText('Contatos')).toBeTruthy()
  })
})

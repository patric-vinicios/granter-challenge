import { render, screen } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import NewGroupPanel from './NewGroupPanel.vue'

describe('NewGroupPanel', () => {
  it('filters contacts and emits selection through the public form controls', async () => {
    const user = userEvent.setup()
    const toggleContact = vi.fn()
    render(NewGroupPanel, {
      props: {
        contacts: [
          contact('contact-ana', 'user-ana', 'ana', 'Ana Beatriz'),
          contact('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
        ],
        error: null,
        isSubmitting: false,
        selectedContactIds: new Set<string>(),
        groupName: '',
        onToggleContact: toggleContact,
      },
    })

    await user.type(screen.getByLabelText('Buscar contato'), 'ana')
    expect(screen.getByText('Ana Beatriz')).toBeTruthy()
    expect(screen.queryByText('Carlos Silva')).toBeNull()

    await user.click(screen.getByRole('checkbox', { name: /Ana Beatriz/ }))
    expect(toggleContact).toHaveBeenCalledWith('user-ana')
  })

  it('emits name, create and close actions while reflecting pending and error states', async () => {
    const user = userEvent.setup()
    const updateName = vi.fn()
    const createGroup = vi.fn()
    const close = vi.fn()
    render(NewGroupPanel, {
      props: {
        contacts: [],
        error: 'Selecione pelo menos um contato.',
        isSubmitting: true,
        selectedContactIds: new Set<string>(),
        groupName: '',
        'onUpdate:groupName': updateName,
        onCreateGroup: createGroup,
        onClose: close,
      },
    })

    await user.type(screen.getByLabelText('Nome do grupo'), 'Produto')
    expect(updateName).toHaveBeenCalled()
    expect(screen.getByRole('alert').textContent).toContain(
      'Selecione pelo menos um contato.',
    )
    expect(
      (screen.getByRole('button', { name: 'Criando...' }) as HTMLButtonElement).disabled,
    ).toBe(true)

    await user.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(close).toHaveBeenCalledOnce()
    expect(createGroup).not.toHaveBeenCalled()
  })
})

function contact(id: string, userId: string, username: string, name: string) {
  return {
    id,
    user: {
      id: userId,
      username,
      name,
      lastSeenAt: null,
      online: false,
    },
  }
}

import { fireEvent, render, screen } from '@testing-library/vue'
import { afterEach, describe, expect, it, vi } from 'vitest'

import ContactsPanel from './ContactsPanel.vue'

describe('ContactsPanel', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('debounces contact filtering while the user types', async () => {
    vi.useFakeTimers()
    render(ContactsPanel, {
      props: {
        contactGroups: [
          {
            initial: 'A',
            contacts: [contact('contact-ana', 'user-ana', 'ana', 'Ana Beatriz')],
          },
          {
            initial: 'C',
            contacts: [contact('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva')],
          },
        ],
        error: null,
        isEmpty: false,
        isLoading: false,
        pendingConversationUserIds: new Set<string>(),
        pendingRemovalIds: new Set<string>(),
      },
    })

    await fireEvent.update(screen.getByLabelText('Buscar contato'), 'ana')

    expect(screen.getByText('Carlos Silva')).toBeTruthy()

    await vi.advanceTimersByTimeAsync(800)

    expect(screen.getByText('Ana Beatriz')).toBeTruthy()
    expect(screen.queryByText('Carlos Silva')).toBeNull()
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

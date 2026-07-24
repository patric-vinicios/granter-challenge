import { render, screen } from '@testing-library/vue'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import GroupDetailsPanel from './GroupDetailsPanel.vue'

describe('GroupDetailsPanel', () => {
  it('lets the creator manage existing and addable members', async () => {
    const user = userEvent.setup()
    const removeMember = vi.fn()
    const addMember = vi.fn()
    render(GroupDetailsPanel, {
      props: {
        contacts: [
          contact('contact-ana', 'user-ana', 'ana', 'Ana'),
          contact('contact-carlos', 'user-carlos', 'carlos', 'Carlos'),
        ],
        currentUserId: 'user-current',
        error: null,
        group: group(),
        pendingUserIds: new Set<string>(),
        onRemoveMember: removeMember,
        onAddMember: addMember,
      },
    })

    await user.click(screen.getByRole('button', { name: 'Remover Ana' }))
    await user.click(screen.getByRole('button', { name: /Carlos/ }))

    expect(removeMember).toHaveBeenCalledWith('user-ana')
    expect(addMember).toHaveBeenCalledWith('user-carlos')
    expect(screen.queryByRole('button', { name: 'Remover Patric' })).toBeNull()
  })

  it('hides management actions from regular members and emits leave', async () => {
    const user = userEvent.setup()
    const leaveGroup = vi.fn()
    render(GroupDetailsPanel, {
      props: {
        contacts: [contact('contact-carlos', 'user-carlos', 'carlos', 'Carlos')],
        currentUserId: 'user-ana',
        error: 'Apenas o criador pode gerenciar.',
        group: group(),
        pendingUserIds: new Set<string>(),
        onLeaveGroup: leaveGroup,
      },
    })

    expect(screen.queryByRole('button', { name: 'Remover Ana' })).toBeNull()
    expect(screen.queryByRole('button', { name: /Carlos/ })).toBeNull()
    expect(screen.getByRole('alert').textContent).toContain(
      'Apenas o criador pode gerenciar.',
    )

    await user.click(screen.getByRole('button', { name: 'Sair do grupo' }))
    expect(leaveGroup).toHaveBeenCalledOnce()
  })
})

function group() {
  return {
    id: 'group-1',
    type: 'group' as const,
    name: 'Produto',
    creatorId: 'user-current',
    memberCount: 2,
    lastReadAt: null,
    members: [
      user('user-current', 'patric', 'Patric'),
      user('user-ana', 'ana', 'Ana'),
    ],
  }
}

function contact(id: string, userId: string, username: string, name: string) {
  return { id, user: user(userId, username, name) }
}

function user(id: string, username: string, name: string) {
  return { id, username, name, lastSeenAt: null, online: false }
}

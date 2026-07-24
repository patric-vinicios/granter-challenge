import { createPinia, setActivePinia } from 'pinia'
import { ref } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useConversationsStore } from './conversations.store'
import { useGroupDetails } from './useGroupDetails'

describe('useGroupDetails adaptable inputs', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('keeps the current ref contract working for token-dependent actions', async () => {
    const conversationsStore = useConversationsStore()
    const loadConversation = vi
      .spyOn(conversationsStore, 'loadConversation')
      .mockResolvedValue(groupConversation())
    const error = ref<string | null>(null)
    const details = useGroupDetails({
      token: ref('jwt-token'),
      currentUserId: ref('user-current'),
      selectedConversationId: ref(null),
      error,
    })

    await expect(details.open('conversation-1', 'group')).resolves.toBe(true)

    expect(loadConversation).toHaveBeenCalledWith('conversation-1', 'jwt-token')
    expect(error.value).toBeNull()
  })

  it('accepts plain and getter readonly inputs for token-dependent actions', async () => {
    const conversationsStore = useConversationsStore()
    const loadConversation = vi
      .spyOn(conversationsStore, 'loadConversation')
      .mockResolvedValue(groupConversation())
    const error = ref<string | null>(null)
    const details = useGroupDetails({
      token: 'jwt-token',
      currentUserId: () => 'user-current',
      selectedConversationId: ref(null),
      error,
    })

    await expect(details.open('conversation-1', 'group')).resolves.toBe(true)

    expect(loadConversation).toHaveBeenCalledWith('conversation-1', 'jwt-token')
    expect(error.value).toBeNull()
  })

  it('opens an already loaded group without requesting it again', async () => {
    const conversationsStore = useConversationsStore()
    conversationsStore.conversations = [groupConversation()]
    const loadConversation = vi.spyOn(conversationsStore, 'loadConversation')
    const error = ref<string | null>('stale')
    const details = useGroupDetails({
      token: 'jwt-token',
      currentUserId: 'user-current',
      selectedConversationId: 'conversation-1',
      error,
    })

    await expect(details.open('conversation-1', 'group')).resolves.toBe(true)

    expect(loadConversation).not.toHaveBeenCalled()
    expect(error.value).toBeNull()
  })

  it('rejects private conversations and missing authentication', async () => {
    const conversationsStore = useConversationsStore()
    const loadConversation = vi.spyOn(conversationsStore, 'loadConversation')
    const error = ref<string | null>(null)
    const details = useGroupDetails({
      token: null,
      currentUserId: null,
      selectedConversationId: null,
      error,
    })

    await expect(details.open('conversation-1', 'group')).resolves.toBe(false)
    await expect(details.open('conversation-1', 'private')).resolves.toBe(false)
    expect(loadConversation).not.toHaveBeenCalled()
  })

  it('maps group action failures and clears the error after recovery', async () => {
    const conversationsStore = useConversationsStore()
    conversationsStore.conversations = [groupConversation()]
    vi.spyOn(conversationsStore, 'addMembers')
      .mockRejectedValueOnce(new Error('failure'))
      .mockResolvedValueOnce(groupConversation())
    vi.spyOn(conversationsStore, 'removeMember')
      .mockRejectedValueOnce(new Error('failure'))
      .mockResolvedValueOnce()
    const error = ref<string | null>(null)
    const details = useGroupDetails({
      token: 'jwt-token',
      currentUserId: 'user-current',
      selectedConversationId: 'conversation-1',
      error,
    })

    await details.addMember('user-ana')
    expect(error.value).toBe('failure')
    await details.addMember('user-ana')
    expect(error.value).toBeNull()

    await details.removeMember('user-ana')
    expect(error.value).toBe('failure')
    await details.removeMember('user-ana')
    expect(error.value).toBeNull()
  })

  it('returns the departed group id and handles failed or guarded leaves', async () => {
    const conversationsStore = useConversationsStore()
    conversationsStore.conversations = [groupConversation()]
    vi.spyOn(conversationsStore, 'leave')
      .mockRejectedValueOnce(new Error('failure'))
      .mockResolvedValueOnce()
    const error = ref<string | null>(null)
    const details = useGroupDetails({
      token: 'jwt-token',
      currentUserId: 'user-current',
      selectedConversationId: 'conversation-1',
      error,
    })

    await expect(details.leave()).resolves.toBeNull()
    expect(error.value).toBe('failure')
    await expect(details.leave()).resolves.toBe('conversation-1')
    expect(error.value).toBeNull()

    const guarded = useGroupDetails({
      token: null,
      currentUserId: null,
      selectedConversationId: 'conversation-1',
      error,
    })
    await expect(guarded.leave()).resolves.toBeNull()
  })
})

function groupConversation() {
  return {
    id: 'conversation-1',
    type: 'group' as const,
    name: 'Equipe',
    creatorId: 'user-current',
    memberCount: 1,
    lastReadAt: null,
    members: [
      {
        id: 'user-current',
        username: 'patric',
        name: 'Patric',
        lastSeenAt: null,
        online: true,
      },
    ],
  }
}

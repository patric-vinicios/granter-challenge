import { createPinia, setActivePinia } from 'pinia'
import { shallowRef } from 'vue'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import type { GroupConversation } from './conversations.contracts'
import { useConversationsStore } from './conversations.store'
import { useCreateGroup } from './useCreateGroup'

describe('useCreateGroup', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('validates the group name and member selection before calling the store', async () => {
    const error = shallowRef<string | null>(null)
    const composable = useCreateGroup({ token: 'jwt-token', error })
    const store = useConversationsStore()
    const createGroup = vi.spyOn(store, 'createGroup')

    await expect(composable.submit()).resolves.toBeNull()
    expect(error.value).toBe('Informe o nome do grupo.')

    composable.name.value = 'Produto'
    await expect(composable.submit()).resolves.toBeNull()
    expect(error.value).toBe('Selecione pelo menos um contato.')
    expect(createGroup).not.toHaveBeenCalled()
  })

  it('toggles immutable member selections', () => {
    const error = shallowRef<string | null>(null)
    const composable = useCreateGroup({ token: 'jwt-token', error })
    const initialSelection = composable.selectedContactIds.value

    composable.toggleContact('user-1')

    expect(composable.selectedContactIds.value).not.toBe(initialSelection)
    expect(composable.selectedContactIds.value.has('user-1')).toBe(true)

    composable.toggleContact('user-1')
    expect(composable.selectedContactIds.value.has('user-1')).toBe(false)
  })

  it('creates the group and resets the successful form', async () => {
    const error = shallowRef<string | null>('previous error')
    const composable = useCreateGroup({ token: () => 'jwt-token', error })
    const store = useConversationsStore()
    const group = groupConversation()
    vi.spyOn(store, 'createGroup').mockResolvedValue(group)
    composable.name.value = 'Produto'
    composable.toggleContact('user-1')
    composable.toggleContact('user-2')

    await expect(composable.submit()).resolves.toEqual(group)

    expect(store.createGroup).toHaveBeenCalledWith(
      'Produto',
      ['user-1', 'user-2'],
      'jwt-token',
    )
    expect(composable.name.value).toBe('')
    expect(composable.selectedContactIds.value.size).toBe(0)
    expect(error.value).toBeNull()
  })

  it('keeps form state and exposes store failures for retry', async () => {
    const error = shallowRef<string | null>(null)
    const composable = useCreateGroup({ token: 'jwt-token', error })
    const store = useConversationsStore()
    vi.spyOn(store, 'createGroup').mockRejectedValue(new Error('Falha temporária'))
    composable.name.value = 'Produto'
    composable.toggleContact('user-1')

    await expect(composable.submit()).resolves.toBeNull()

    expect(error.value).toBe('Falha temporária')
    expect(composable.name.value).toBe('Produto')
    expect(composable.selectedContactIds.value.has('user-1')).toBe(true)
  })

  it('does not submit without an authenticated token', async () => {
    const error = shallowRef<string | null>(null)
    const composable = useCreateGroup({ token: null, error })
    const store = useConversationsStore()
    const createGroup = vi.spyOn(store, 'createGroup')
    composable.name.value = 'Produto'
    composable.toggleContact('user-1')

    await expect(composable.submit()).resolves.toBeNull()
    expect(createGroup).not.toHaveBeenCalled()
  })
})

function groupConversation(): GroupConversation {
  return {
    id: 'group-1',
    type: 'group',
    name: 'Produto',
    creatorId: 'user-current',
    memberCount: 3,
    lastReadAt: null,
    members: [],
  }
}

import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { deferred, jsonResponse } from '@/test/http'

import { useContactsStore } from './contacts.store'

describe('contacts store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('loads contacts and derives accessible alphabetical groups', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          contacts: [
            contactResponse('contact-1', 'user-1', 'alvaro', 'Álvaro Lima'),
            contactResponse('contact-2', 'user-2', 'bruna', 'Bruna Souza'),
          ],
        }),
      ),
    )
    const store = useContactsStore()

    await store.load('jwt-token')

    expect(store.loadState).toBe('success')
    expect(store.isLoading).toBe(false)
    expect(store.isEmpty).toBe(false)
    expect(store.contactGroups.map((group) => group.initial)).toEqual(['A', 'B'])
    expect(store.contactGroups[0]?.contacts[0]?.user.name).toBe('Álvaro Lima')
  })

  it('preserves existing contacts and exposes a retryable load error', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          contacts: [contactResponse('contact-1', 'user-1', 'ana', 'Ana Beatriz')],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(503, {
          errors: {
            code: 'service_unavailable',
            detail: 'Try again later',
          },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)
    const store = useContactsStore()
    await store.load('jwt-token')

    await store.load('jwt-token')

    expect(store.loadState).toBe('error')
    expect(store.loadError).toBe('Try again later')
    expect(store.contacts.map((contact) => contact.id)).toEqual(['contact-1'])
  })

  it('upserts additions and keeps contacts sorted by display name', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(201, {
          contact: contactResponse('contact-2', 'user-2', 'carlos', 'Carlos Silva'),
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(201, {
          contact: contactResponse('contact-1', 'user-1', 'ana', 'Ana Beatriz'),
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(201, {
          contact: contactResponse('contact-2', 'user-2', 'carlos', 'Carlos Almeida'),
        }),
      )
    vi.stubGlobal('fetch', fetchMock)
    const store = useContactsStore()

    await store.add('@carlos', 'jwt-token')
    await store.add('@ana', 'jwt-token')
    await store.add('@carlos', 'jwt-token')

    expect(store.contacts.map((contact) => contact.user.name)).toEqual([
      'Ana Beatriz',
      'Carlos Almeida',
    ])
    expect(store.contacts).toHaveLength(2)
    expect(store.loadState).toBe('success')
  })

  it('cleans pending removal state after success', async () => {
    const removal = deferred<Response>()
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          contacts: [contactResponse('contact-1', 'user-1', 'ana', 'Ana Beatriz')],
        }),
      )
      .mockReturnValueOnce(removal.promise)
    vi.stubGlobal('fetch', fetchMock)
    const store = useContactsStore()
    await store.load('jwt-token')

    const pendingRemoval = store.remove('contact-1', 'jwt-token')
    expect(store.pendingRemovalIds.has('contact-1')).toBe(true)

    removal.resolve(jsonResponse(204, null))
    await pendingRemoval

    expect(store.pendingRemovalIds.has('contact-1')).toBe(false)
    expect(store.contacts).toHaveLength(0)
  })

  it('cleans pending removal state and preserves the contact after failure', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(200, {
          contacts: [contactResponse('contact-1', 'user-1', 'ana', 'Ana Beatriz')],
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse(500, {
          errors: {
            code: 'internal_error',
            detail: 'Unexpected failure',
          },
        }),
      )
    vi.stubGlobal('fetch', fetchMock)
    const store = useContactsStore()
    await store.load('jwt-token')

    await expect(store.remove('contact-1', 'jwt-token')).rejects.toThrow('Unexpected failure')

    expect(store.pendingRemovalIds.has('contact-1')).toBe(false)
    expect(store.contacts.map((contact) => contact.id)).toEqual(['contact-1'])
  })

  it('resets all feature state', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          contacts: [contactResponse('contact-1', 'user-1', 'ana', 'Ana Beatriz')],
        }),
      ),
    )
    const store = useContactsStore()
    await store.load('jwt-token')

    store.reset()

    expect(store.contacts).toEqual([])
    expect(store.loadState).toBe('idle')
    expect(store.loadError).toBeNull()
    expect(store.pendingRemovalIds.size).toBe(0)
  })
})

function contactResponse(id: string, userId: string, username: string, name: string) {
  return {
    id,
    user: {
      id: userId,
      username,
      name,
      last_seen_at: null,
      online: false,
    },
  }
}

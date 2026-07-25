import { describe, expect, it, vi } from 'vitest'

import { isApiError } from '@/shared/api/errors'
import { jsonResponse } from '@/test/http'

import { addContact, listContacts, removeContact } from './contacts.api'

describe('contacts api', () => {
  it('lists contacts through the authenticated contacts endpoint', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        contacts: [contactResponse('contact-1', 'user-1', 'anabeatriz', 'Ana Beatriz')],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    await expect(listContacts('jwt-token')).resolves.toEqual([
      {
        id: 'contact-1',
        user: {
          id: 'user-1',
          username: 'anabeatriz',
          name: 'Ana Beatriz',
          lastSeenAt: null,
          online: false,
        },
      },
    ])

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
  })

  it('adds a contact by username and decodes the created contact', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(201, {
        contact: contactResponse('contact-2', 'user-2', 'carlos', 'Carlos Silva'),
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    await expect(addContact('@carlos', 'jwt-token')).resolves.toMatchObject({
      id: 'contact-2',
      user: { username: 'carlos', name: 'Carlos Silva' },
    })

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ username: '@carlos' }),
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
          'Content-Type': 'application/json',
        }),
      }),
    )
  })

  it('removes a contact by row id', async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(204, null))
    vi.stubGlobal('fetch', fetchMock)

    await expect(removeContact('contact-1', 'jwt-token')).resolves.toBeUndefined()

    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/contacts/contact-1',
      expect.objectContaining({
        method: 'DELETE',
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
  })

  it('preserves machine-readable contact errors', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(409, {
          errors: {
            code: 'contact_already_exists',
            detail: 'This user is already in your contacts',
          },
        }),
      ),
    )

    try {
      await addContact('@anabeatriz', 'jwt-token')
      throw new Error('Expected request to fail')
    } catch (error) {
      expect(isApiError(error)).toBe(true)

      if (isApiError(error)) {
        expect(error.code).toBe('contact_already_exists')
        expect(error.status).toBe(409)
        expect(error.message).toBe('Este usuário já está nos seus contatos.')
      }
    }
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
    },
  }
}

import { describe, expect, it } from 'vitest'

import { decodeContacts, decodeCreatedContact } from './contacts.contracts'

describe('contacts contracts', () => {
  it('decodes contact lists and defaults an omitted online flag to false', () => {
    expect(decodeContacts({ contacts: [contactResponse()] })).toEqual([
      {
        id: 'contact-1',
        user: {
          id: 'user-1',
          username: 'ana',
          name: 'Ana',
          lastSeenAt: null,
          online: false,
        },
      },
    ])
  })

  it('decodes a created online contact', () => {
    expect(
      decodeCreatedContact({
        contact: contactResponse({
          online: true,
          last_seen_at: '2026-07-24T10:00:00Z',
        }),
      }),
    ).toMatchObject({
      user: { online: true, lastSeenAt: '2026-07-24T10:00:00Z' },
    })
  })

  it.each([
    null,
    [],
    {},
    { contacts: {} },
    { contacts: [null] },
    { contacts: [{ ...contactResponse(), id: '' }] },
    { contacts: [contactResponse({ online: 'yes' })] },
    { contacts: [contactResponse({ last_seen_at: 42 })] },
  ])('rejects malformed contact collections %#', (payload) => {
    expect(() => decodeContacts(payload)).toThrow()
  })

  it('rejects malformed created-contact envelopes', () => {
    expect(() => decodeCreatedContact({ contact: [] })).toThrow()
  })
})

function contactResponse(userOverrides: Record<string, unknown> = {}) {
  return {
    id: 'contact-1',
    user: {
      id: 'user-1',
      username: 'ana',
      name: 'Ana',
      last_seen_at: null,
      ...userOverrides,
    },
  }
}

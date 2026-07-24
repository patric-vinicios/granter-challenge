import { describe, expect, it } from 'vitest'

import {
  decodeAuthSession,
  decodeCurrentUser,
  decodeStoredSession,
} from './auth.contracts'

describe('auth contracts', () => {
  it('decodes API sessions and current users', () => {
    const user = apiUser()

    expect(
      decodeAuthSession({
        user,
        token: 'jwt-token',
        expires_at: '2026-07-30T12:00:00Z',
      }),
    ).toEqual({
      user: {
        id: 'user-1',
        username: 'ana',
        name: 'Ana',
        lastSeenAt: null,
      },
      token: 'jwt-token',
      expiresAt: '2026-07-30T12:00:00Z',
    })
    expect(decodeCurrentUser({ user })).toMatchObject({ id: 'user-1', name: 'Ana' })
  })

  it('decodes the camel-case session persisted by the frontend', () => {
    expect(
      decodeStoredSession({
        user: {
          id: 'user-1',
          username: 'ana',
          name: 'Ana',
          lastSeenAt: '2026-07-24T10:00:00Z',
        },
        token: 'jwt-token',
        expiresAt: '2026-07-30T12:00:00Z',
      }),
    ).toMatchObject({
      user: { lastSeenAt: '2026-07-24T10:00:00Z' },
      token: 'jwt-token',
    })
  })

  it.each([
    null,
    [],
    {},
    { token: '', expires_at: '2026-07-30T12:00:00Z', user: apiUser() },
    { token: 'jwt-token', expires_at: '', user: apiUser() },
    { token: 'jwt-token', expires_at: '2026-07-30T12:00:00Z', user: [] },
    {
      token: 'jwt-token',
      expires_at: '2026-07-30T12:00:00Z',
      user: { ...apiUser(), last_seen_at: 42 },
    },
  ])('rejects malformed API sessions %#', (payload) => {
    expect(() => decodeAuthSession(payload)).toThrow()
  })

  it.each([
    null,
    [],
    {},
    { user: {}, token: 'jwt-token', expiresAt: '2026-07-30T12:00:00Z' },
    {
      user: { id: 'user-1', username: 'ana', name: 'Ana', lastSeenAt: [] },
      token: 'jwt-token',
      expiresAt: '2026-07-30T12:00:00Z',
    },
  ])('returns null instead of leaking stored-session decoding errors %#', (payload) => {
    expect(decodeStoredSession(payload)).toBeNull()
  })
})

function apiUser() {
  return {
    id: 'user-1',
    username: 'ana',
    name: 'Ana',
    last_seen_at: null,
  }
}

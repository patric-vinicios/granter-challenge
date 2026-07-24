import { beforeEach, describe, expect, it } from 'vitest'

import { clearStorageKey, readJsonValue, writeJsonValue } from './jsonStorage'

describe('JSON storage', () => {
  beforeEach(() => window.localStorage.clear())

  it('round-trips JSON values', () => {
    writeJsonValue('preferences', { compact: true })

    expect(readJsonValue('preferences')).toEqual({ compact: true })
  })

  it('returns null for missing and malformed values', () => {
    expect(readJsonValue('missing')).toBeNull()

    window.localStorage.setItem('broken', '{')
    expect(readJsonValue('broken')).toBeNull()
  })

  it('clears only the requested key', () => {
    writeJsonValue('session', { token: 'jwt' })
    writeJsonValue('preferences', { compact: true })

    clearStorageKey('session')

    expect(readJsonValue('session')).toBeNull()
    expect(readJsonValue('preferences')).toEqual({ compact: true })
  })
})

import { describe, expect, it } from 'vitest'

import { formatMessageTime } from './formatMessageTime'

describe('formatMessageTime', () => {
  it('formats a valid local timestamp with hours and minutes', () => {
    expect(formatMessageTime('2026-07-22T09:42:00')).toBe('09:42')
  })

  it('returns an empty label for an invalid timestamp', () => {
    expect(formatMessageTime('not-a-date')).toBe('')
  })
})

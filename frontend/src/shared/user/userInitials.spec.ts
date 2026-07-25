import { describe, expect, it } from 'vitest'

import { userInitials } from './userInitials'

describe('userInitials', () => {
  it.each([
    ['Ana Beatriz', 'AB'],
    ['Prince', 'P'],
    ['  Maria   da Silva  ', 'MS'],
    ['', ''],
  ])('formats %j as %s initials', (name, expected) => {
    expect(userInitials(name)).toBe(expected)
  })
})

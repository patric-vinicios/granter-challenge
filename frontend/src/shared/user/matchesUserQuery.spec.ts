import { describe, expect, it } from 'vitest'

import { matchesUserQuery } from './matchesUserQuery'

const user = {
  name: 'Ana Beatriz',
  username: 'anabeatriz',
}

describe('matchesUserQuery', () => {
  it.each(['', 'ana', 'BEATRIZ', 'anabeatriz'])('matches the normalized query %j', (query) => {
    expect(matchesUserQuery(user, query)).toBe(true)
  })

  it('rejects a query outside the name and username', () => {
    expect(matchesUserQuery(user, 'carlos')).toBe(false)
  })
})

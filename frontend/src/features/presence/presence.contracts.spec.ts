import { describe, expect, it } from 'vitest'

import { decodePresenceDiff, decodePresenceState } from './presence.contracts'
import { formatPresenceLabel } from './presence.format'

describe('presence contracts', () => {
  it('decodes Phoenix presence state as online users', () => {
    expect(
      decodePresenceState({
        'user-ana': {
          metas: [{ online_at: '2026-07-23T17:30:00Z' }],
        },
      }),
    ).toEqual([
      {
        userId: 'user-ana',
        online: true,
        lastSeenAt: null,
      },
    ])
  })

  it('decodes joins and leaves from presence diff', () => {
    const now = () => new Date('2026-07-23T17:42:00.000Z')

    expect(
      decodePresenceDiff(
        {
          joins: {
            'user-ana': { metas: [{ online_at: '2026-07-23T17:41:00Z' }] },
          },
          leaves: {
            'user-carlos': { metas: [{}] },
            'user-mariana': { metas: [{ last_seen_at: '2026-07-23T17:35:00Z' }] },
          },
        },
        now,
      ),
    ).toEqual([
      { userId: 'user-ana', online: true, lastSeenAt: null },
      { userId: 'user-carlos', online: false, lastSeenAt: '2026-07-23T17:42:00.000Z' },
      { userId: 'user-mariana', online: false, lastSeenAt: '2026-07-23T17:35:00Z' },
    ])
  })
})

describe('presence formatting', () => {
  it('renders online, never-seen, recent, and older offline labels', () => {
    const now = new Date('2026-07-23T17:45:00.000Z')

    expect(formatPresenceLabel({ online: true, lastSeenAt: null }, now)).toBe('online')
    expect(formatPresenceLabel({ online: false, lastSeenAt: null }, now)).toBe('offline')
    expect(formatPresenceLabel({ online: false, lastSeenAt: '2026-07-23T17:40:00.000Z' }, now)).toBe(
      'visto por ultimo ha 5 min',
    )
    expect(formatPresenceLabel({ online: false, lastSeenAt: '2026-07-22T17:40:00.000Z' }, now)).toBe(
      'visto por ultimo ontem',
    )
  })
})

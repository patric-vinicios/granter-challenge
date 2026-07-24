import { describe, expect, it } from 'vitest'

import { useConversationPresence } from './useConversationPresence'

const ana = {
  id: 'user-ana',
  online: false,
  lastSeenAt: null,
}

describe('useConversationPresence', () => {
  it('falls back to the conversation user state before realtime data arrives', () => {
    const presence = useConversationPresence()

    expect(presence.subtitleFor({ ...ana, online: true })).toBe('online')
    expect(presence.subtitleFor(ana)).toBe('offline')
  })

  it('applies full presence state updates', () => {
    const presence = useConversationPresence()

    presence.applyState({
      'user-ana': {
        metas: [{ online_at: '2026-07-23T17:44:00.000Z' }],
      },
    })

    expect(presence.subtitleFor(ana)).toBe('online')
  })

  it('merges diffs without discarding other users', () => {
    const presence = useConversationPresence()
    presence.applyState({
      'user-ana': {
        metas: [{ online_at: '2026-07-23T17:44:00.000Z' }],
      },
      'user-bruno': {
        metas: [{ online_at: '2026-07-23T17:44:00.000Z' }],
      },
    })

    presence.applyDiff({
      joins: {},
      leaves: {
        'user-ana': {
          metas: [{}],
        },
      },
    })

    expect(presence.subtitleFor(ana)).toMatch(/^visto por ultimo/)
    expect(
      presence.subtitleFor({
        id: 'user-bruno',
        online: false,
        lastSeenAt: null,
      }),
    ).toBe('online')
  })
})

import { shallowRef } from 'vue'

import { decodePresenceDiff, decodePresenceState, type PresenceStatus } from './presence.contracts'
import { formatPresenceLabel } from './presence.format'

interface PresenceUser {
  id: string
  online: boolean
  lastSeenAt: string | null
}

export function useConversationPresence() {
  const presenceByUserId = shallowRef<Record<string, PresenceStatus>>({})

  function applyState(payload: unknown): void {
    applyUpdates(decodePresenceState(payload))
  }

  function applyDiff(payload: unknown): void {
    applyUpdates(decodePresenceDiff(payload))
  }

  function applyUpdates(updates: PresenceStatus[]): void {
    const nextPresence = { ...presenceByUserId.value }

    for (const update of updates) {
      nextPresence[update.userId] = update
    }

    presenceByUserId.value = nextPresence
  }

  function subtitleFor(user: PresenceUser): string {
    const status = presenceByUserId.value[user.id] ?? {
      userId: user.id,
      online: user.online,
      lastSeenAt: user.lastSeenAt,
    }

    return formatPresenceLabel(status)
  }

  return {
    applyDiff,
    applyState,
    subtitleFor,
  }
}

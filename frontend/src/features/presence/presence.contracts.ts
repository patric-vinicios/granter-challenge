export interface PresenceStatus {
  userId: string
  online: boolean
  lastSeenAt: string | null
}

type PresenceClock = () => Date

export function decodePresenceState(payload: unknown): PresenceStatus[] {
  return Object.entries(decodePresenceMap(payload)).map(([userId, entry]) => ({
    userId,
    online: entry.metas.length > 0,
    lastSeenAt: null,
  }))
}

export function decodePresenceDiff(payload: unknown, now: PresenceClock = () => new Date()): PresenceStatus[] {
  const data = requireRecord(payload)
  const updates: PresenceStatus[] = []

  for (const [userId, entry] of Object.entries(decodePresenceMap(data.joins ?? {}))) {
    updates.push({
      userId,
      online: entry.metas.length > 0,
      lastSeenAt: null,
    })
  }

  for (const [userId, entry] of Object.entries(decodePresenceMap(data.leaves ?? {}))) {
    updates.push({
      userId,
      online: false,
      lastSeenAt: decodeLastSeenAt(entry, now),
    })
  }

  return updates
}

function decodePresenceMap(payload: unknown): Record<string, { metas: Array<Record<string, unknown>> }> {
  const data = requireRecord(payload)
  const presence: Record<string, { metas: Array<Record<string, unknown>> }> = {}

  for (const [userId, value] of Object.entries(data)) {
    const entry = requireRecord(value)
    const metas = entry.metas

    if (!Array.isArray(metas) || !metas.every(isRecord)) {
      throw new Error('Expected presence metas array')
    }

    presence[userId] = { metas }
  }

  return presence
}

function decodeLastSeenAt(entry: { metas: Array<Record<string, unknown>> }, now: PresenceClock): string {
  for (const meta of entry.metas) {
    const lastSeenAt = meta.last_seen_at

    if (typeof lastSeenAt === 'string' && lastSeenAt.length > 0) {
      return lastSeenAt
    }
  }

  return now().toISOString()
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new Error('Expected object')
  }

  return value
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

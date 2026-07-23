import type { PresenceStatus } from './presence.contracts'

export function formatPresenceLabel(status: Pick<PresenceStatus, 'online' | 'lastSeenAt'>, now = new Date()): string {
  if (status.online) {
    return 'online'
  }

  if (!status.lastSeenAt) {
    return 'offline'
  }

  const lastSeen = new Date(status.lastSeenAt)

  if (Number.isNaN(lastSeen.getTime())) {
    return 'offline'
  }

  const elapsedMs = Math.max(0, now.getTime() - lastSeen.getTime())
  const elapsedMinutes = Math.floor(elapsedMs / 60_000)

  if (elapsedMinutes < 1) {
    return 'visto por ultimo agora'
  }

  if (elapsedMinutes < 60) {
    return `visto por ultimo ha ${elapsedMinutes} min`
  }

  const elapsedHours = Math.floor(elapsedMinutes / 60)

  if (elapsedHours < 24) {
    return `visto por ultimo ha ${elapsedHours} h`
  }

  if (elapsedHours < 48) {
    return 'visto por ultimo ontem'
  }

  return `visto por ultimo em ${new Intl.DateTimeFormat('pt-BR').format(lastSeen)}`
}

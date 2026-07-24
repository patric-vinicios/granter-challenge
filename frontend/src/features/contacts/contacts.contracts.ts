import type { Contact } from '@/types/contact'
import type { ChatUser } from '@/types/user'

export type ContactUser = ChatUser
export type { Contact } from '@/types/contact'

export interface ContactGroup {
  initial: string
  contacts: Contact[]
}

export type AddContactFeedback =
  | { kind: 'idle' }
  | { kind: 'success'; message: string }
  | { kind: 'error'; title: string; message: string }

export function decodeContacts(payload: unknown): Contact[] {
  const data = requireRecord(payload)
  const contacts = data.contacts

  if (!Array.isArray(contacts)) {
    throw new Error('Expected contacts array')
  }

  return contacts.map(decodeContact)
}

export function decodeCreatedContact(payload: unknown): Contact {
  const data = requireRecord(payload)

  return decodeContact(data.contact)
}

function decodeContact(payload: unknown): Contact {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    user: decodeContactUser(data.user),
  }
}

function decodeContactUser(payload: unknown): ContactUser {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    username: requireString(data.username),
    name: requireString(data.name),
    lastSeenAt: requireNullableString(data.last_seen_at),
    online: requireOptionalBoolean(data.online),
  }
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Expected object')
  }

  return value as Record<string, unknown>
}

function requireString(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Expected string')
  }

  return value
}

function requireNullableString(value: unknown): string | null {
  if (value === null) {
    return null
  }

  return requireString(value)
}

function requireOptionalBoolean(value: unknown): boolean {
  if (value === undefined) {
    return false
  }

  if (typeof value !== 'boolean') {
    throw new Error('Expected boolean')
  }

  return value
}

import type { Contact } from '@/types/contact'
import { requireRecord, requireString } from '@/shared/contracts/decoders'
import { decodeChatUser } from '@/shared/contracts/user'

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
    user: decodeChatUser(data.user, { requireLastSeenAt: true }),
  }
}

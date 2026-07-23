import { requestJson } from '@/shared/api/httpClient'

import { type Contact, decodeContacts, decodeCreatedContact } from './contacts.contracts'

export function listContacts(token: string, signal?: AbortSignal): Promise<Contact[]> {
  return requestJson('/contacts', {
    token,
    signal,
    decode: decodeContacts,
  })
}

export function addContact(username: string, token: string, signal?: AbortSignal): Promise<Contact> {
  return requestJson('/contacts', {
    method: 'POST',
    body: { username },
    token,
    signal,
    decode: decodeCreatedContact,
  })
}

export function removeContact(contactId: string, token: string, signal?: AbortSignal): Promise<void> {
  return requestJson('/contacts/' + encodeURIComponent(contactId), {
    method: 'DELETE',
    token,
    signal,
    decode: () => undefined,
  })
}

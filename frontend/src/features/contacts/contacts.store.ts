import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { addContact as addContactRequest, listContacts, removeContact as removeContactRequest } from './contacts.api'
import type { Contact, ContactGroup } from './contacts.contracts'

type LoadState = 'idle' | 'loading' | 'success' | 'error'

export const useContactsStore = defineStore('contacts', () => {
  const contacts = ref<Contact[]>([])
  const loadState = ref<LoadState>('idle')
  const loadError = ref<string | null>(null)
  const pendingRemovalIds = ref<Set<string>>(new Set())

  const isLoading = computed(() => loadState.value === 'loading')
  const isEmpty = computed(() => loadState.value === 'success' && contacts.value.length === 0)

  const contactGroups = computed<ContactGroup[]>(() => {
    const groups = new Map<string, Contact[]>()

    for (const contact of contacts.value) {
      const initial = groupInitial(contact.user.name)
      groups.set(initial, [...(groups.get(initial) ?? []), contact])
    }

    return Array.from(groups.entries()).map(([initial, groupedContacts]) => ({
      initial,
      contacts: groupedContacts,
    }))
  })

  async function load(token: string, signal?: AbortSignal): Promise<void> {
    loadState.value = 'loading'
    loadError.value = null

    try {
      contacts.value = await listContacts(token, signal)
      loadState.value = 'success'
    } catch (error) {
      if (signal?.aborted) {
        return
      }

      loadState.value = 'error'
      loadError.value = error instanceof Error ? error.message : 'Não foi possível carregar os contatos.'
    }
  }

  async function add(username: string, token: string): Promise<Contact> {
    const contact = await addContactRequest(username, token)
    upsertContact(contact)
    loadState.value = 'success'

    return contact
  }

  async function remove(contactId: string, token: string): Promise<void> {
    pendingRemovalIds.value = new Set(pendingRemovalIds.value).add(contactId)

    try {
      await removeContactRequest(contactId, token)
      contacts.value = contacts.value.filter((contact) => contact.id !== contactId)
    } finally {
      const nextIds = new Set(pendingRemovalIds.value)
      nextIds.delete(contactId)
      pendingRemovalIds.value = nextIds
    }
  }

  function reset(): void {
    contacts.value = []
    loadState.value = 'idle'
    loadError.value = null
    pendingRemovalIds.value = new Set()
  }

  function upsertContact(contact: Contact): void {
    const existingIndex = contacts.value.findIndex((item) => item.id === contact.id)

    if (existingIndex >= 0) {
      const nextContacts = [...contacts.value]
      nextContacts[existingIndex] = contact
      contacts.value = nextContacts
      return
    }

    contacts.value = [...contacts.value, contact].sort(compareContacts)
  }

  return {
    contacts,
    loadState,
    loadError,
    pendingRemovalIds,
    isLoading,
    isEmpty,
    contactGroups,
    load,
    add,
    remove,
    reset,
  }
})

function compareContacts(left: Contact, right: Contact): number {
  return left.user.name.localeCompare(right.user.name, 'pt-BR', { sensitivity: 'base' })
}

function groupInitial(name: string): string {
  return name.trim().charAt(0).normalize('NFD').replace(/\p{Diacritic}/gu, '').toUpperCase() || '#'
}

export function contactInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  const first = parts[0]?.charAt(0) ?? ''
  const second = parts.length > 1 ? (parts.at(-1)?.charAt(0) ?? '') : ''

  return `${first}${second}`.toUpperCase()
}

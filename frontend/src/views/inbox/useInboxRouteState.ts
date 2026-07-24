import { shallowRef, watch } from 'vue'
import { useRoute, useRouter, type LocationQueryValue } from 'vue-router'

type InboxRouteQueryKey = 'conversation' | 'q'

export function useInboxRouteState() {
  const route = useRoute()
  const router = useRouter()

  const inboxSearchQuery = shallowRef(readQueryString(route.query.q))
  const selectedConversationId = shallowRef(readQueryString(route.query.conversation) || null)

  watch(
    () => route.query.q,
    (value) => {
      const nextQuery = readQueryString(value)

      if (inboxSearchQuery.value !== nextQuery) {
        inboxSearchQuery.value = nextQuery
      }
    },
  )

  watch(
    () => route.query.conversation,
    (value) => {
      const nextConversationId = readQueryString(value) || null

      if (selectedConversationId.value !== nextConversationId) {
        selectedConversationId.value = nextConversationId
      }
    },
  )

  watch(inboxSearchQuery, (value) => updateQuery('q', value.trim() ? value : undefined))
  watch(selectedConversationId, (value) => updateQuery('conversation', value || undefined))

  function updateQuery(key: InboxRouteQueryKey, value: string | undefined): void {
    if (readQueryString(route.query[key]) === (value ?? '')) {
      return
    }

    void router.replace({
      query: {
        ...route.query,
        [key]: value,
      },
    })
  }

  return {
    inboxSearchQuery,
    selectedConversationId,
  }
}

function readQueryString(value: LocationQueryValue | LocationQueryValue[]): string {
  const firstValue = Array.isArray(value) ? value[0] : value

  return typeof firstValue === 'string' ? firstValue : ''
}

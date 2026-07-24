import { render, screen } from '@testing-library/vue'
import { flushPromises } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'

import type { ChatConversation } from '@/types/chat'

import ChatPanel from './ChatPanel.vue'

const conversation: ChatConversation = {
  id: 'conversation-1',
  type: 'private',
  initials: 'AB',
  name: 'Ana Beatriz',
  subtitle: '',
  preview: '',
  time: '',
  messages: [{ side: 'out', text: 'Mensagem mais recente', time: '19:13' }],
}

describe('ChatPanel', () => {
  it('starts the message scroller at the bottom', async () => {
    render(ChatPanel, { props: defaultProps() })

    const scroller = screen.getByRole('log', { name: 'Mensagens da conversa' })
    Object.defineProperty(scroller, 'scrollHeight', { configurable: true, value: 480 })

    await flushPromises()

    expect(scroller.scrollTop).toBe(480)
  })

  it('preserves the visible position when older messages are prepended', async () => {
    const { rerender } = render(ChatPanel, { props: defaultProps() })
    const scroller = screen.getByRole('log', { name: 'Mensagens da conversa' })
    Object.defineProperty(scroller, 'scrollHeight', { configurable: true, value: 480 })

    await flushPromises()

    scroller.scrollTop = 120
    Object.defineProperty(scroller, 'scrollHeight', { configurable: true, value: 580 })

    await rerender({
      ...defaultProps(),
      conversation: {
        ...conversation,
        messages: [
          { id: 'message-older', side: 'in', text: 'Mensagem anterior', time: '19:10' },
          ...conversation.messages,
        ],
      },
    })
    await flushPromises()

    expect(scroller.scrollTop).toBe(220)
  })

  it('renders observable loading, failure and empty history states', async () => {
    const { rerender } = render(ChatPanel, {
      props: { ...defaultProps(), isLoadingHistory: true },
    })

    expect(screen.getByText('Carregando historico...')).toBeTruthy()

    await rerender({
      ...defaultProps(),
      isLoadingHistory: false,
      historyError: 'Histórico indisponível.',
    })
    expect(screen.getByText('Histórico indisponível.')).toBeTruthy()

    await rerender({
      ...defaultProps(),
      conversation: { ...conversation, messages: [] },
    })
    expect(screen.getByText('Nenhuma mensagem nesta conversa.')).toBeTruthy()
  })

  it('reports truncated search progress and enables navigation for multiple results', () => {
    render(ChatPanel, {
      props: {
        ...defaultProps(),
        isSearching: true,
        searchStatus: 'success',
        searchTerm: 'agenda',
        searchActivePosition: 2,
        searchTotalMatches: 100,
        searchTruncated: true,
      },
    })

    expect(screen.getByRole('status').textContent).toContain('2 / 100+')
    expect(
      (screen.getByRole('button', { name: 'Resultado anterior' }) as HTMLButtonElement)
        .disabled,
    ).toBe(false)
    expect(
      (screen.getByRole('button', { name: 'Proximo resultado' }) as HTMLButtonElement)
        .disabled,
    ).toBe(false)
  })
})

function defaultProps() {
  return {
    conversation,
    canSendMessage: true,
    isSearching: false,
    isLoadingHistory: false,
    isLoadingOlder: false,
    canLoadOlder: false,
    historyError: null,
    searchTerm: '',
    messageDraft: '',
    realtimeError: null,
    searchStatus: 'idle' as const,
    searchError: null,
    searchActivePosition: null,
    searchTotalMatches: 0,
    searchTruncated: false,
    searchActiveMessageId: null,
    searchActiveMatchOffsets: [],
  }
}

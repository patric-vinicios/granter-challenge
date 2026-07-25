import { render, screen } from '@testing-library/vue'
import { flushPromises } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'

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
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('shows a neutral placeholder when no conversation is selected', () => {
    render(ChatPanel, {
      props: {
        ...defaultProps(),
        conversation: null,
        canSendMessage: false,
      },
    })

    expect(screen.getByText('Selecione uma conversa')).toBeTruthy()
    expect(screen.queryByRole('log', { name: 'Mensagens da conversa' })).toBeNull()
    expect(screen.queryByRole('textbox', { name: 'Mensagem' })).toBeNull()
  })

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

  it('shows the message send shortcut near the composer', () => {
    render(ChatPanel, { props: defaultProps() })

    expect(screen.getByText('Enviar: CTRL + ENTER')).toBeTruthy()
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

  it('scrolls to the active search result when it changes', async () => {
    const scrollIntoView = mockScrollIntoView()
    const { rerender } = render(ChatPanel, {
      props: {
        ...defaultProps(),
        conversation: {
          ...conversation,
          messages: [
            { id: 'message-1', side: 'out', text: 'Primeiro cronograma', time: '19:10' },
            { id: 'message-2', side: 'in', text: 'Segundo cronograma', time: '19:11' },
          ],
        },
        isSearching: true,
        searchStatus: 'success',
        searchActiveMessageId: 'message-1',
        searchActiveMatchOffsets: [{ start: 9, length: 10 }],
        searchActivePosition: 1,
        searchTotalMatches: 2,
      },
    })

    await flushPromises()

    expect(scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'center',
      inline: 'nearest',
    })
    scrollIntoView.mockClear()

    await rerender({
      ...defaultProps(),
      conversation: {
        ...conversation,
        messages: [
          { id: 'message-1', side: 'out', text: 'Primeiro cronograma', time: '19:10' },
          { id: 'message-2', side: 'in', text: 'Segundo cronograma', time: '19:11' },
        ],
      },
      isSearching: true,
      searchStatus: 'success',
      searchActiveMessageId: 'message-2',
      searchActiveMatchOffsets: [{ start: 8, length: 10 }],
      searchActivePosition: 2,
      searchTotalMatches: 2,
    })
    await flushPromises()

    expect(scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'center',
      inline: 'nearest',
    })
  })

  it('scrolls to a far search result injected outside the current loaded history', async () => {
    const scrollIntoView = mockScrollIntoView()
    const loadedMessages = Array.from({ length: 500 }, (_, index): ChatConversation['messages'][number] => ({
      id: `message-${index + 1}`,
      side: index % 2 === 0 ? 'out' : 'in',
      text: `Mensagem atual ${index + 1}`,
      time: '19:13',
    }))

    render(ChatPanel, {
      props: {
        ...defaultProps(),
        conversation: {
          ...conversation,
          messages: [
            ...loadedMessages,
            { id: 'message-4500', side: 'in', text: 'Resultado distante encontrado', time: '12:00' },
          ],
        },
        isSearching: true,
        searchStatus: 'success',
        searchActiveMessageId: 'message-4500',
        searchActiveMatchOffsets: [{ start: 20, length: 10 }],
        searchActivePosition: 4500,
        searchTotalMatches: 5000,
      },
    })
    await flushPromises()

    expect(screen.getByText('4500 / 5000')).toBeTruthy()
    expect(
      screen.getByText((_content, element) => element?.textContent === 'Resultado distante encontrado'),
    ).toBeTruthy()
    expect(scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'center',
      inline: 'nearest',
    })
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

function mockScrollIntoView() {
  const scrollIntoView = vi.fn()

  Object.defineProperty(Element.prototype, 'scrollIntoView', {
    configurable: true,
    value: scrollIntoView,
  })

  return scrollIntoView
}

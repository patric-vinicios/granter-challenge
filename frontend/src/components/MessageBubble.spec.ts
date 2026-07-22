import { render, screen } from '@testing-library/vue'
import { describe, expect, it } from 'vitest'

import MessageBubble from './MessageBubble.vue'

describe('MessageBubble', () => {
  it('shows the sender identity on an incoming message', () => {
    render(MessageBubble, {
      props: {
        side: 'in',
        author: 'Ana Beatriz',
        text: 'Oi, Carlos!',
        time: '09:42',
      },
    })

    expect(screen.getByText('AB')).toBeTruthy()
    expect(screen.getByText('Ana Beatriz')).toBeTruthy()
    expect(screen.getByText('Oi, Carlos!')).toBeTruthy()
  })

  it('does not invent an avatar for an outgoing message without an author', () => {
    render(MessageBubble, {
      props: {
        side: 'out',
        text: 'Até mais!',
        time: '09:43',
      },
    })

    expect(screen.getByText('Até mais!')).toBeTruthy()
    expect(screen.queryByText('AB')).toBeNull()
  })
})

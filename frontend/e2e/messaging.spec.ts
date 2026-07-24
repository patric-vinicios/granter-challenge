import { expect, test } from '@playwright/test'

import {
  createBackendState,
  inboxSummaryResponse,
  messageResponse,
  openAuthenticatedInbox,
  searchHitResponse,
} from './support/appHarness'

test('loads message history and sends a message through realtime', async ({ page }) => {
  const conversationId = 'conversation-ana'
  const state = createBackendState({
    conversations: [
      inboxSummaryResponse({
        id: conversationId,
        title: 'Ana Beatriz',
        body: 'Mensagem anterior',
      }),
    ],
    histories: {
      [conversationId]: [
        messageResponse('message-old', conversationId, 'Mensagem do historico'),
      ],
    },
  })
  await openAuthenticatedInbox(page, state)

  await page.getByRole('button', { name: /Ana Beatriz/ }).click()
  await expect(page.getByText('Mensagem do historico', { exact: true })).toBeVisible()

  await page.getByRole('textbox', { name: 'Mensagem', exact: true }).fill('Mensagem enviada pelo E2E')
  await page.getByRole('button', { name: 'Enviar mensagem' }).click()

  await expect(page.getByText('Mensagem enviada pelo E2E', { exact: true })).toBeVisible()
  await expect.poll(() => state.sentMessages).toHaveLength(1)
  expect(state.sentMessages[0]?.body).toBe('Mensagem enviada pelo E2E')
})

test('searches within the selected conversation and highlights the result', async ({ page }) => {
  const conversationId = 'conversation-ana'
  const state = createBackendState({
    conversations: [
      inboxSummaryResponse({
        id: conversationId,
        title: 'Ana Beatriz',
        body: 'Cronograma aprovado',
      }),
    ],
    histories: {
      [conversationId]: [
        messageResponse('message-result', conversationId, 'Cronograma aprovado'),
      ],
    },
    searches: {
      [conversationId]: [
        searchHitResponse(
          'message-result',
          conversationId,
          'Cronograma aprovado',
          1,
        ),
      ],
    },
  })
  await openAuthenticatedInbox(page, state)

  await page.getByRole('button', { name: /Ana Beatriz/ }).click()
  await page.getByRole('button', { name: 'Buscar na conversa' }).click()
  await page.getByLabel('Buscar na conversa').fill('Cronograma')

  await expect(page.getByRole('status')).toHaveText('1 / 1')
  await expect(
    page
      .getByLabel('Mensagens da conversa')
      .getByText('Cronograma aprovado', { exact: true }),
  ).toBeVisible()
  await expect(page.getByRole('button', { name: 'Resultado anterior' })).toBeDisabled()
  await expect(page.getByRole('button', { name: 'Proximo resultado' })).toBeDisabled()
})

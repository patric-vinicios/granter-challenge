import { expect, test } from '@playwright/test'

import {
  contactResponse,
  createBackendState,
  inboxSummaryResponse,
  openAuthenticatedInbox,
} from './support/appHarness'

test('filters conversations and preserves the selected conversation in the URL', async ({ page }) => {
  const state = createBackendState({
    conversations: [
      inboxSummaryResponse({
        id: 'conversation-ana',
        title: 'Ana Beatriz',
        body: 'Revisamos o contrato',
      }),
      inboxSummaryResponse({
        id: 'group-product',
        title: 'Time de Produto',
        body: 'Roadmap atualizado',
        type: 'group',
      }),
    ],
  })
  await openAuthenticatedInbox(page, state)

  const search = page.getByLabel('Buscar conversa')
  await expect(page.getByRole('button', { name: /Ana Beatriz/ })).toBeVisible()
  await search.fill('produto')

  await expect(page).toHaveURL(/q=produto/)
  await expect(page.getByRole('button', { name: /Time de Produto/ })).toBeVisible()
  await expect(page.getByRole('button', { name: /Ana Beatriz/ })).toBeHidden()

  await page.getByRole('button', { name: /Time de Produto/ }).click()
  await expect(page).toHaveURL(/conversation=group-product/)
  await expect(page.getByRole('button', { name: 'Gerenciar grupo' })).toBeVisible()
})

test('adds a contact and opens a private conversation', async ({ page }) => {
  const state = createBackendState()
  await openAuthenticatedInbox(page, state)

  await page.getByRole('button', { name: 'Contatos' }).click()
  await page.getByRole('button', { name: 'Adicionar', exact: true }).click()

  const dialog = page.getByRole('dialog', { name: 'Adicionar contato' })
  await dialog.getByLabel('Usuario').fill('@bruno')
  await dialog.getByRole('button', { name: 'Adicionar', exact: true }).click()
  await expect(dialog.getByRole('status')).toContainText('Contato adicionado')

  await dialog.getByRole('button', { name: 'Voltar' }).click()
  await expect(dialog).toBeHidden()
  await expect(page.getByText('@bruno', { exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Abrir conversa com Bruno Lima' }).click()

  await expect(page).toHaveURL(/conversation=conversation-bruno/)
  await expect(page.getByLabel('Mensagens da conversa')).toBeVisible()
  expect(state.requests).toContainEqual({
    method: 'POST',
    path: '/api/contacts',
    body: { username: '@bruno' },
  })
})

test('creates a group from selected contacts', async ({ page }) => {
  const state = createBackendState({
    contacts: [
      contactResponse('contact-ana', 'user-ana', 'ana', 'Ana Beatriz'),
      contactResponse('contact-carlos', 'user-carlos', 'carlos', 'Carlos Silva'),
    ],
  })
  await openAuthenticatedInbox(page, state)

  await page.getByRole('button', { name: 'Novo grupo' }).click()
  await page.getByLabel('Nome do grupo').fill('Time Produto')
  await page.getByText('Ana Beatriz', { exact: true }).click()
  await page.getByText('Carlos Silva', { exact: true }).click()
  await expect(page.getByRole('checkbox', { name: /Ana Beatriz/ })).toBeChecked()
  await expect(page.getByRole('checkbox', { name: /Carlos Silva/ })).toBeChecked()
  await page.getByRole('button', { name: 'Criar grupo' }).click()

  await expect(page).toHaveURL(/conversation=group-created/)
  await expect(page.getByRole('button', { name: 'Gerenciar grupo' })).toBeVisible()
  expect(state.requests).toContainEqual({
    method: 'POST',
    path: '/api/conversations/groups',
    body: {
      name: 'Time Produto',
      member_ids: ['user-ana', 'user-carlos'],
    },
  })
})

import { expect, test } from '@playwright/test'

import { createBackendState, openAuthenticatedInbox } from './support/appHarness'

test('traps focus inside the add-contact dialog and restores it on close', async ({ page }) => {
  await openAuthenticatedInbox(page, createBackendState())

  await page.getByRole('button', { name: 'Contatos' }).click()
  const openDialogButton = page.getByRole('button', { name: 'Adicionar', exact: true })
  await openDialogButton.click()

  const dialog = page.getByRole('dialog', { name: 'Adicionar contato' })
  const username = dialog.getByLabel('Usuario')
  const backButton = dialog.getByRole('button', { name: 'Voltar' })
  const submitButton = dialog.getByRole('button', { name: 'Adicionar', exact: true })

  await expect(username).toBeFocused()

  await submitButton.focus()
  await page.keyboard.press('Tab')
  await expect(backButton).toBeFocused()

  await backButton.focus()
  await page.keyboard.press('Shift+Tab')
  await expect(submitButton).toBeFocused()

  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
  await expect(openDialogButton).toBeFocused()
})

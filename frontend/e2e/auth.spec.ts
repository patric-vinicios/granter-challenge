import { expect, test } from '@playwright/test'

import { createBackendState, installAppMocks } from './support/appHarness'

test('logs in and reaches the authenticated inbox', async ({ page }) => {
  const state = createBackendState()
  await installAppMocks(page, state)
  await page.goto('/')

  await page.getByLabel('Usuario').fill('patric')
  await page.getByLabel('Senha', { exact: true }).fill('segredo')
  await page.getByRole('button', { name: 'Entrar', exact: true }).click()

  await expect(page).toHaveURL(/\/inbox$/)
  await expect(page.getByRole('button', { name: 'Contatos' })).toBeVisible()
  await expect(page.getByLabel('Buscar conversa')).toBeVisible()
  expect(state.requests).toContainEqual({
    method: 'POST',
    path: '/api/auth/login',
    body: { username: 'patric', password: 'segredo' },
  })
})

test('creates an account and starts an authenticated session', async ({ page }) => {
  const state = createBackendState()
  await installAppMocks(page, state)
  await page.goto('/cadastrar')

  await page.getByLabel('Nome').fill('Patric')
  await page.getByLabel('Usuario').fill('patric')
  await page.getByLabel('Senha', { exact: true }).fill('segredo')
  await page.getByRole('button', { name: 'Criar conta' }).click()

  await expect(page).toHaveURL(/\/inbox$/)
  await expect(page.getByLabel('Buscar conversa')).toBeVisible()
  expect(state.requests).toContainEqual({
    method: 'POST',
    path: '/api/auth/register',
    body: { name: 'Patric', username: 'patric', password: 'segredo' },
  })
})

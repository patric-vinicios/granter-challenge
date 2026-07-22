# Protocolo para agentes

## Escopo e fontes

Preserve o trabalho existente. Antes de alterar uma fronteira, leia o código, este README, o PRD disponível e os contratos do backend. O código executável prevalece quando o README estiver desatualizado. Não altere o backend a partir deste diretório.

O harness não autoriza mudanças no produto. Não altere arquivos existentes em `src/` sem um pedido explícito do usuário; arquivos `*.spec.ts` e helpers em `src/test/` são infraestrutura de teste, não implementação de feature.

## Fluxo obrigatório

Antes:

- Execute `git status --short`, identifique arquivos do usuário e declare os arquivos que pretende alterar.
- Rode o menor baseline relevante antes de editar.

Durante:

- Faça mudanças pequenas e rode um teste direcionado após cada comportamento.
- Não acesse backend ou rede real em testes unitários.
- Não corrija nem reformate arquivo alheio ao escopo.

Depois:

- Execute `npm run verify` e `git diff --check`.
- Revise o diff e registre falhas preexistentes separadamente.

## Arquitetura

Leia `docs/architecture/frontend.md` antes de implementar uma feature.

- Organize novas implementações como vertical slices em `src/features/`.
- Views orquestram features; não acessam HTTP ou WebSocket diretamente.
- Transporte compartilhado fica em `src/shared/api/` e `src/shared/realtime/`.
- Pinia guarda apenas estado compartilhado; estado de formulário permanece local.
- REST faz bootstrap, histórico e recuperação; WebSocket aplica eventos incrementais.
- O contrato executável do backend prevalece sobre documentação divergente.
- Não crie uma camada, store ou abstração sem um consumidor real.

## Diretrizes Vue

- Use `ref` para valores primitivos ou substituíveis e `reactive` para objetos coesos; acesse `.value` no script, nunca no template.
- Modele estado derivado com `computed`; não copie valores deriváveis para outro `ref`.
- Use lifecycle e `watch` somente para efeitos externos, com cleanup explícito; não sincronize duas fontes de verdade com watchers.
- Props são readonly via `defineProps<T>()`; componentes comunicam por `defineEmits<T>()` ou `v-model` tipado e nunca mutam props.
- Use Pinia apenas para estado compartilhado; preserve reatividade com `storeToRefs` ao desestruturar estado ou getters e concentre mutações em actions.
- Acesse navegação com `useRoute`/`useRouter`, guards e route params; testes sempre usam `createMemoryHistory`.
- Extraia lógica reutilizável para composables `useX`; transporte fica em `src/api` e DTO/schema na fronteira, não em views ou stores.

## Convenções Vue e fronteiras

Use Composition API e `<script setup lang="ts">`. Mantenha estado local na view/componente, derivação em `computed` e efeitos em composables. Stores não acessam DOM/router implicitamente. A camada API não importa componente/store. Views orquestram; componentes apresentam.

Toda entrada externa deve começar como `unknown` e ser validada na fronteira quando a integração for implementada; nunca use `as Type` para confiar nela. Não crie clientes ou schemas antes de existir um consumidor real.

Teste comportamento e acessibilidade por role, label e texto. Não selecione classes Tailwind, use snapshots grandes, rede/timer real ou singleton global. Cada teste de app cria Pinia e router próprios.

## Comandos

| Intenção          | Comando                                           |
| ----------------- | ------------------------------------------------- |
| Lint direcionado  | `npm run lint -- src/views/LoginView.vue`         |
| Tipos             | `npm run typecheck`                               |
| Testes em watch   | `npm run test`                                    |
| Teste direcionado | `npm run test:run -- src/views/LoginView.spec.ts` |
| Testes afetados   | `npm run test:changed -- <arquivos>`              |
| Suíte rápida      | `npm run test:run`                                |
| Build             | `npm run build`                                   |
| Porta completa    | `npm run verify`                                  |

`npm run verify` é obrigatório antes de concluir.

## Limites

Não implemente feature adjacente nem adicione abstração sem consumidor. Não silencie lint, tipos ou testes. Não reformate arquivos fora do escopo.

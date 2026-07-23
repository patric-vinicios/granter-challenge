# Diretrizes de engenharia Vue

Este projeto usa Vue 3 com Composition API e `<script setup lang="ts">`. No template, refs são
desembrulhadas automaticamente; no script, um `ref` exige `.value`.

## Estado e reatividade

- Use `ref` para valores primitivos ou que serão substituídos por inteiro.
- Use `reactive` para objetos coesos mutados por propriedade.
- Não desestruture diretamente objetos reativos. Use `toRefs` ou `storeToRefs` quando precisar
  preservar a reatividade.
- Modele valores derivados com `computed`, mantendo o getter puro.
- Evite duplicar estado que pode ser calculado a partir de outra fonte.

## Componentes

- Declare props com `defineProps<T>()` e trate-as como readonly.
- Declare eventos com `defineEmits<T>()`; não altere props recebidas.
- Use `v-model` tipado apenas quando o componente possuir um contrato real de edição bidirecional.
- Mantenha views responsáveis por orquestração e componentes reutilizáveis focados em apresentação.
- Use chaves estáveis baseadas em identificadores, nunca o índice da lista quando a ordem puder mudar.

## Efeitos e composables

- Use `watch` e lifecycle somente para efeitos externos, não para sincronizar estado derivado.
- Remova listeners, timers, subscriptions e sockets no cleanup correspondente.
- Extraia lógica reutilizável para composables nomeados com o prefixo `use`.
- Mantenha transporte em `src/api`; composables coordenam efeitos, mas não misturam UI e protocolo.

## Pinia e Router

- Use Pinia somente para estado compartilhado entre rotas ou componentes distantes.
- Concentre mutações em actions e use `storeToRefs` ao desestruturar estado ou getters.
- Use `useRoute` e `useRouter` dentro do contexto Vue; não importe o singleton do router em testes.
- Cada teste deve criar router com `createMemoryHistory` e uma Pinia nova.

## Testes

- Verifique comportamento observável por role, label ou texto.
- Não use classes Tailwind, estrutura interna ou snapshots grandes como contrato.
- Aguarde interações e atualizações assíncronas; use `nextTick` apenas para mutação direta.
- Não acesse rede real. Instale stubs explícitos para `fetch`, WebSocket ou cliente Phoenix.
- Restaure timers, mocks, router e Pinia entre testes.

## Diagnóstico

- `vue-tsc` aponta problemas de tipos em TypeScript e SFCs.
- ESLint aponta padrões estáticos inseguros ou inconsistentes.
- Vitest aponta comportamento executado que divergiu do esperado.
- Corrija a camada que falhou; não silencie a ferramenta nem atualize o teste sem entender a causa.

## Checklist de revisão

- O componente usa `<script setup lang="ts">` e fronteiras tipadas?
- Estado derivado está em `computed`, sem refs duplicadas?
- Desestruturação preserva reatividade?
- Props permanecem readonly e mudanças saem por evento ou `v-model`?
- Watches e lifecycle representam efeitos externos e possuem cleanup?
- Estado global realmente merece Pinia?
- Views orquestram e componentes de apresentação permanecem focados?
- Testes usam role, label ou texto em vez de classes de estilo?
- Cada teste recebe Pinia e router próprios e não acessa rede real?
- `npm run verify` e `git diff --check` estão verdes?

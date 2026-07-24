# Granter Chat — Frontend

Single-page application de mensagens construída com Vue 3, TypeScript e Vite.

> **Estado atual:** SPA funcional com login, cadastro, inbox, contatos, grupos, busca, histórico
> persistido e mensagens realtime integrados aos contratos REST/WebSocket do backend.

## Requisitos

- Node.js 22+ (validado em 22.22.3)

## Setup

```bash
npm install
cp .env.example .env
npm run dev
```

A aplicação fica disponível em `http://localhost:5173`.

## Scripts

| Script                               | O que faz                                            |
| ------------------------------------ | ---------------------------------------------------- |
| `npm run dev`                        | Servidor de desenvolvimento com HMR                  |
| `npm run lint`                       | Analisa Vue/TypeScript e falha com warnings          |
| `npm run typecheck`                  | Checa tipos, incluindo SFCs e configs                |
| `npm run test`                       | Executa Vitest em watch, com DOM simulado            |
| `npm run test:run`                   | Executa uma vez a suíte rápida e isolada             |
| `npm run test:changed -- <arquivos>` | Executa testes relacionados aos arquivos informados  |
| `npm run build`                      | Typecheck seguido do build de produção               |
| `npm run verify`                     | Porta completa: lint, tipos, testes e build          |
| `npm run preview`                    | Serve localmente o resultado do build                |

Antes de concluir uma mudança, execute `npm run verify`. Os testes são isolados e bloqueiam `fetch` e `WebSocket` sem um stub explícito. Para convenções e diagnóstico, veja o [guia de engenharia Vue](docs/ai-harness/vue-guidelines.md).

## Variáveis de ambiente

Definidas em `.env` (veja `.env.example`) e tipadas em [`src/env.d.ts`](src/env.d.ts):

| Variável          | Padrão local                 | Uso                    |
| ----------------- | ---------------------------- | ---------------------- |
| `VITE_API_URL`    | `http://localhost:4000/api`  | Base das chamadas REST |
| `VITE_SOCKET_URL` | `ws://localhost:4000/socket` | Canais de tempo real   |

## Estrutura

```
src/
├── features/     # slices verticais por domínio: auth, contatos, conversas, mensagens e busca
├── shared/       # clientes HTTP, socket, configuração e utilitários compartilhados
├── components/   # componentes de UI reutilizáveis
├── layouts/      # esqueletos de página
├── router/       # rotas e navigation guards
├── stores/       # estado global (Pinia)
├── test/         # harness e helpers de teste
├── views/        # componentes de rota
└── style.css     # estilos globais e tokens visuais
```

O alias `@` aponta para `src/`, configurado em `vite.config.ts` e `tsconfig.app.json`.

## Arquitetura

O frontend adota módulos orientados a features e vertical slices, com fronteiras explícitas entre
UI, estado e transporte. Consulte a [arquitetura do frontend](docs/architecture/frontend.md) antes
de implementar uma feature.

## Stack e decisões

| Escolha                     | Motivo                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------ |
| **Vue 3 + Vite**            | Exigido pelo enunciado; Vite é o toolchain padrão do Vue 3.                                            |
| **TypeScript 6.0**          | Ver a nota abaixo.                                                                                     |
| **Pinia**                   | Store oficial do Vue 3, com inferência de tipos direta nas stores.                                     |
| **Vue Router**              | Roteador oficial; a navegação por conversa vira URL, então recarregar a página preserva o contexto.    |
| **Tailwind CSS 4**          | As telas de referência são um design system pequeno e fechado; utilitários evitam manter CSS paralelo. |
| **`phoenix`**               | Cliente WebSocket com reconexão, heartbeat, canais e referências de mensagens.                         |

### Sobre a versão do TypeScript

O enunciado pede "TypeScript 6 ou superior". A versão mais recente hoje é a **7.0.2**, que é a
reescrita nativa em Go — e ela **não é compatível com o ecossistema Vue neste momento**: o pacote
`typescript@7` deixou de expor a API JS do compilador (o export `.` aponta apenas para
`lib/version.cjs`), e é exatamente sobre essa API que o `vue-tsc` se apoia para checar os blocos
`<script setup>` dos SFCs. Instalando a 7.0.2, `vue-tsc` quebra com
`ERR_PACKAGE_PATH_NOT_EXPORTED` e o projeto fica sem checagem de tipos dentro dos `.vue`.

Por isso o projeto usa **TypeScript 6.0.2**, que atende o requisito e mantém a verificação de
tipos ponta a ponta. A migração para a 7.x fica condicionada ao suporte a `tsgo` no
`@vue/language-tools`.

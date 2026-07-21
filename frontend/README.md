# Granter Chat — Frontend

Aplicação web do teste prático full-stack (Elixir + TypeScript). Consome a API REST e os
canais WebSocket do backend Phoenix em [`../backend`](../backend).

> **Estado atual:** esqueleto do projeto. A estrutura, o toolchain e as dependências estão
> configurados e validados; as telas e a camada de dados ainda não foram implementadas.

## Requisitos

- Node.js 22+ (validado em 22.22.3)
- Backend rodando em `http://localhost:4000`

## Setup

```bash
npm install
cp .env.example .env
npm run dev
```

A aplicação sobe em `http://localhost:5173` — a mesma origem já liberada no CORS do backend.

## Scripts

| Script              | O que faz                                        |
| ------------------- | ------------------------------------------------ |
| `npm run dev`       | Servidor de desenvolvimento com HMR              |
| `npm run build`     | Type-check (`vue-tsc`) seguido do build de prod   |
| `npm run typecheck` | Só a checagem de tipos, incluindo os SFCs `.vue`  |
| `npm run preview`   | Serve localmente o resultado do `build`           |

## Variáveis de ambiente

Definidas em `.env` (veja `.env.example`) e tipadas em [`src/env.d.ts`](src/env.d.ts):

| Variável           | Padrão local                  | Uso                          |
| ------------------ | ----------------------------- | ---------------------------- |
| `VITE_API_URL`     | `http://localhost:4000/api`   | Base das chamadas REST       |
| `VITE_SOCKET_URL`  | `ws://localhost:4000/socket`  | Canais de tempo real         |

## Estrutura

```
src/
├── api/          # clientes HTTP e socket, um módulo por recurso da API
├── assets/       # imagens e fontes processadas pelo Vite
├── components/   # componentes de UI reutilizáveis
├── composables/  # lógica reaproveitável (Composition API)
├── layouts/      # esqueletos de página
├── router/       # rotas e navigation guards
├── stores/       # estado global (Pinia)
├── types/        # tipos do contrato da API
├── utils/        # helpers puros (datas, formatação, etc.)
└── views/        # componentes de rota
```

O alias `@` aponta para `src/`, configurado em `vite.config.ts` e `tsconfig.app.json`.

## Stack e decisões

| Escolha                    | Motivo                                                                                                     |
| -------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Vue 3 + Vite**           | Exigido pelo enunciado; Vite é o toolchain padrão do Vue 3.                                                  |
| **TypeScript 6.0**         | Ver a nota abaixo.                                                                                           |
| **Pinia**                  | Store oficial do Vue 3, com inferência de tipos direta nas stores.                                           |
| **Vue Router**             | Roteador oficial; a navegação por conversa vira URL, então recarregar a página preserva o contexto.          |
| **Tailwind CSS 4**         | As telas de referência são um design system pequeno e fechado; utilitários evitam manter CSS paralelo.       |
| **`phoenix` (npm oficial)**| Cliente JS mantido junto com o servidor: reconexão, heartbeat e refs de canal já resolvidos.                 |

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

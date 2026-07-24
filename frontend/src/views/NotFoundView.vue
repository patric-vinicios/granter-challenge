<script setup lang="ts"></script>

<template>
  <main class="grid min-h-full place-items-center bg-[#f7f7f7] p-6">
    <section
      aria-labelledby="not-found-title"
      class="grid w-full max-w-[420px] gap-4 rounded-[10px] border border-[#e8e8e8] bg-white p-8 text-center shadow-[0_24px_72px_rgba(0,0,0,0.14)] max-[860px]:p-5"
    >
      <div class="grid gap-2">
        <p class="m-0 text-[13px] font-bold uppercase text-[#737373]">404</p>
        <h1 id="not-found-title" class="m-0 text-2xl font-bold text-[#171717]">Pagina nao encontrada</h1>
      </div>

      <p class="m-0 text-[14px] leading-6 text-[#525252]">
        O endereco acessado nao existe no Granter Chat.
      </p>

      <RouterLink
        class="inline-flex min-h-9 items-center justify-center rounded-lg border border-black bg-black px-3.5 text-[13px] font-bold text-white no-underline hover:bg-[#222222]"
        to="/inbox"
      >
        Voltar para o inbox
      </RouterLink>
    </section>
  </main>
</template>

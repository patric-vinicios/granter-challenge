const featureNames = ['auth', 'contacts', 'conversations', 'messaging', 'presence', 'search']

const featureIsolationRules = featureNames.map((featureName) => ({
  name: `feature-${featureName}-does-not-import-other-features`,
  severity: 'error',
  comment: 'Features expose product behavior to views and must not import another feature internals.',
  from: {
    path: `^src/features/${featureName}/`,
  },
  to: {
    path: `^src/features/(?!${featureName}/)`,
  },
}))

/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: 'no-circular',
      severity: 'error',
      comment: 'Circular dependencies make feature state and side effects hard to reason about.',
      from: {},
      to: {
        circular: true,
      },
    },
    {
      name: 'no-unresolved',
      severity: 'error',
      comment: 'Every import must resolve from the local TypeScript/Vite configuration.',
      from: {},
      to: {
        path: '^(\\.|@/)',
        couldNotResolve: true,
      },
    },
    {
      name: 'shared-is-infrastructure-only',
      severity: 'error',
      comment: 'Shared modules must not depend on app composition, feature code, router, stores or views.',
      from: {
        path: '^src/shared/',
      },
      to: {
        path: '^src/(app|features|router|stores|views)/',
      },
    },
    {
      name: 'api-modules-stay-headless',
      severity: 'error',
      comment: 'API modules must not import UI, router or stores.',
      from: {
        path: '\\.api\\.(ts|tsx|vue)$',
      },
      to: {
        path: '^src/(components|layouts|router|stores|views)/',
      },
    },
    ...featureIsolationRules,
  ],
  options: {
    doNotFollow: {
      path: 'node_modules',
    },
    exclude: {
      path: '^(dist|coverage|node_modules)/',
    },
    tsConfig: {
      fileName: 'tsconfig.app.json',
    },
    reporterOptions: {
      dot: {
        collapsePattern: 'node_modules/[^/]+',
      },
    },
  },
}

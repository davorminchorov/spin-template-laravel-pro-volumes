// https://github.com/nuxt-themes/docus/blob/main/nuxt.schema.ts
export default defineAppConfig({
  docus: {
    title: '💪 Laravel Pro by Spin',
    description: 'The best place to start your documentation.',
    socials: {
      twitter: 'serversideup',
      github: 'serversideup/spin-template-laravel-pro'
    },
    github: {
      dir: 'docs',
      branch: 'main',
      repo: 'spin-template-laravel-pro',
      owner: 'serversideup',
      edit: true
    },
    aside: {
      level: 0,
      collapsed: false,
      exclude: []
    },
    main: {
      padded: true,
      fluid: true
    },
    header: {
      logo: false,
      showLinkIcon: true,
      exclude: [],
      fluid: true
    }
  }
})

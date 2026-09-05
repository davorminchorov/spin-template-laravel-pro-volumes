<p align="center">
		<a href="https://getspin.pro"><img src=".github/images/header.png" width="1200" alt="Spin Header" /></a>
</p>

# 🏆 Spin Pro - Laravel Template (named volumes)
This is a fork of the official [Spin Pro Laravel template](https://github.com/serversideup/spin-template-laravel-pro). It includes Laravel, Redis, Reverb, Queues, and more. Spin Pro is a local development environment that makes it easy to create and manage your projects. Spin Pro is built on top of Docker Compose and Docker Swarm, making it easy to manage your application from development to production.

## 🔀 What is different from the official template
The official template stores development data for MySQL, MariaDB, PostgreSQL, Redis and Meilisearch as bind mounts under `.infrastructure/volume_data/` inside the project folder.

This template stores that data in named Docker volumes instead, matching how production already works:

| Service     | Official template (dev)                                       | This template (dev)                   |
|-------------|---------------------------------------------------------------|---------------------------------------|
| MySQL       | `./.infrastructure/volume_data/mysql/database_data/`          | `mysql_data:/var/lib/mysql`           |
| MariaDB     | `./.infrastructure/volume_data/mariadb/database_data/`        | `mariadb_data:/var/lib/mysql`         |
| PostgreSQL  | `./.infrastructure/volume_data/postgres/database_data/`       | `postgres_data:/var/lib/postgresql`   |
| Redis       | `./.infrastructure/volume_data/redis/data`                    | `redis_data:/data`                    |
| Meilisearch | `./.infrastructure/volume_data/meilisearch/meilisearch_data`  | `meilisearch_data:/meili_data`        |

SQLite is unchanged. The whole project folder is bind mounted into the `php` container during development, so the SQLite file stays at `.infrastructure/volume_data/sqlite/database.sqlite`.

Named volumes are created per project (Docker Compose prefixes them with the project name) and survive `spin down`. To wipe the data, run `spin down --volumes` or remove the volume with `docker volume rm`.

Everything else (install prompts, blocks, GitHub Actions, production compose files) is identical to the official template, and this repository tracks it as the `upstream` git remote.

## 🌎 Default Development Environment Config
> [!CAUTION]
> These URLs will only work after you add the following to your hosts file (`/etc/hosts`):
> ```shell
> 127.0.0.1 laravel.dev.test
> 127.0.0.1 mailpit.dev.test
> 127.0.0.1 vite.dev.test
> 127.0.0.1 reverb.dev.test
> 127.0.0.1 meilisearch.dev.test
> ```
- **Laravel**: [https://laravel.dev.test](https://laravel.dev.test)
- **Mailpit**: [https://mailpit.dev.test](https://mailpit.dev.test)
- **Vite**: [https://vite.dev.test](https://vite.dev.test)
- **Reverb**: [wss://reverb.dev.test](wss://reverb.dev.test)
- **Meilisearch**: [http://meilisearch.dev.test](http://meilisearch.dev.test)

### 🚀 Quick Start
You can create a new Laravel project with Redis, Reverb, Queues, and more in less than a minute.

Once you have your computer prepared to run Spin, you can create a new project by running the following command:

```shell
spin new davorminchorov/spin-template-laravel-pro-volumes
```

To add it to an existing Laravel project instead:

```shell
spin init davorminchorov/spin-template-laravel-pro-volumes
```

To use a local checkout of this repository without pushing it anywhere:

```shell
spin new --local ~/Code/GitHub/spin-template-laravel-pro-volumes my-project
```

The official Spin Pro documentation applies to this template as well:

[Read the docs →](https://getspin.pro/docs)

## 📕 Resources
- **[Website](https://getspin.pro/)** overview of the product.
- **[Docs](https://getspin.pro/docs)** for a deep-dive on how to use the product.
- **[Discord](https://serversideup.net/discord)** for friendly support from the community and the team.
- **[Official template on GitHub](https://github.com/serversideup/spin-template-laravel-pro)** for the upstream source code.
- **[This template on GitHub](https://github.com/davorminchorov/spin-template-laravel-pro-volumes)** for the named-volumes fork.
- **[Get Professional Help](https://serversideup.net/professional-support)** - If you need video + screen-sharing support, we offer that too.

## ❤️ Contributing
We're a community that strives on helping each other. If you're interested in contributing to this project, here are some ways you can help:

- **Bug Report**: If you're experiencing an issue while using these images, please [create an issue](https://github.com/serversideup/spin-template-laravel-pro/issues/new/choose).
- **Feature Request**: Make this project better by [submitting a feature request](https://github.com/serversideup/spin-template-laravel-pro/discussions/6).
- **Documentation**: If something doesn't make sense, take a screenshot and [create an issue](https://github.com/serversideup/spin-template-laravel-pro/issues/new/choose)
- **Community Support**: Help others on [GitHub Discussions](https://github.com/serversideup/spin-template-laravel-pro/discussions) or [Discord](https://serversideup.net/discord).
- **Security Report**: Report critical security issues via [our responsible disclosure policy](https://www.notion.so/Responsible-Disclosure-Policy-421a6a3be1714d388ebbadba7eebbdc8).
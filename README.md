# WSL dev setup (Ubuntu 26.04)

Companion notes for `setup-wsl-dev.sh`: what it installs, whether each install follows the tool's official instructions, how each tool gets updated, and what you still do yourself.

## Usage

```bash
bash setup-wsl-dev.sh                 # every step
bash setup-wsl-dev.sh hcloud dotnet   # only selected steps
exec bash                             # reload your shell afterwards
```

Steps, in order: `base ripgrep just node pnpm typescript uv dotnet hcloud aws terraform ansible sdkman`

Run it as your normal user from your Linux home directory (`~`), not from `/mnt/c`. It asks for your sudo password where needed. Every step can be rerun safely. If a step fails, the script continues and lists the failed steps at the end.

## Tool matrix

| Tool | How the script installs it | Official method? | How it updates |
|---|---|---|---|
| Base tools (curl, git, zip, build-essential…) | `apt install` | Standard Ubuntu packages | `sudo apt upgrade` |
| [ripgrep](https://github.com/BurntSushi/ripgrep#installation) | `apt install ripgrep` | Yes | `sudo apt upgrade` |
| [just](https://github.com/casey/just#installation) | `apt install just` | Yes | `sudo apt upgrade` |
| [.NET SDK 10](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu-install) | `apt install dotnet-sdk-10.0` from Ubuntu's feed | Yes | `sudo apt upgrade` |
| [Terraform](https://developer.hashicorp.com/terraform/install) | HashiCorp's apt repo | Yes, plus a fallback if the repo doesn't support your Ubuntu codename yet | `sudo apt upgrade` |
| [hcloud](https://github.com/hetznercloud/cli/blob/main/docs/tutorials/setup-hcloud-cli.md) | Hetzner's documented commands, run as-is | Yes | Rerun `bash setup-wsl-dev.sh hcloud` |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS's documented installer (`awscli-exe-linux-<arch>.zip`, then `sudo ./aws/install`) | Yes | Rerun `bash setup-wsl-dev.sh aws` |
| [SDKMAN](https://sdkman.io/install) | `curl -s "https://get.sdkman.io" \| bash` | Yes | Updates itself, or `sdk selfupdate` |
| [nvm](https://github.com/nvm-sh/nvm#installing-and-updating) + Node LTS | nvm's `install.sh`, then `nvm install --lts` | Yes, except the script looks up the newest nvm version instead of using the README's fixed one | Node: `nvm install --lts`. nvm: rerun its install script |
| [pnpm](https://pnpm.io/installation) | `get.pnpm.io` standalone script | Yes | `pnpm self-update` |
| [TypeScript](https://www.typescriptlang.org/download) | `pnpm add -g typescript` | Documented, but TypeScript recommends per-project installs. Global is a deliberate choice for convenience | `pnpm update -g` |
| [uv](https://docs.astral.sh/uv/getting-started/installation/) + Python | `astral.sh/uv` installer, then `uv python install` | Yes | `uv self update` |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) | `uv tool install`, including ansible-core's commands | No (Ansible documents pipx and its PPA). uv is a deliberate choice | `uv tool upgrade --all` |

## Installed by the script

- **Node:** the current LTS, via nvm, set as the default. Install other versions with `nvm install <version>`.
- **Python:** one version, via uv. Add others with `uv python install 3.x`.
- **Ansible collections:** the full `ansible` package includes the `hetzner.hcloud` collection. The script adds `requests` and `python-dateutil`, which that collection lists as its requirements.

## You install these yourself

- **Java:** `sdk list java`, then `sdk install java <identifier>`.
- **Maven:** `sdk install maven`, or `sudo apt install maven` if you want it updated by apt.
- **Spring Boot CLI (optional):** `sdk install springboot`. Projects don't need it: Maven downloads Spring for each project, and [start.spring.io](https://start.spring.io) generates new projects.
- **TypeScript per project:** `pnpm add -D typescript`, so builds don't depend on whatever global version is installed.

## One-time setup the script doesn't do

- **Connect hcloud to your Hetzner project:** run `hcloud context create <name>` and paste an API token.
- **Connect the AWS CLI to your account:** run `aws configure sso` if your account uses IAM Identity Center, otherwise `aws configure` and paste an access key.
- **Create an SSH key inside WSL:** `ssh-keygen -t ed25519`. Don't link to your Windows `.ssh` folder; files on `/mnt/c` show up with loose permissions, and SSH refuses those keys.
- **Docker:** not included. Install it separately if you want local containers.

## Good to know

- **Ubuntu packages keep the same version.** ripgrep, just and .NET get security and bug fixes through `apt upgrade`, but stay on the same major/minor version for as long as you're on 26.04. Terraform is different: HashiCorp's repo ships every new release.
- **.NET 11.** Microsoft's support table for 26.04 lists only .NET 10 in Ubuntu's built-in feed. When .NET 11 comes out, check that page for how to get it on 26.04. Don't mix .NET packages from Ubuntu's and Microsoft's feeds.
- **.NET global tools.** Ubuntu's .NET package adds `~/.dotnet/tools` to your PATH, so `dotnet tool install -g` works without extra setup.
- **nvm globals.** Global npm packages are tied to each Node version, so switching versions with nvm hides them. pnpm and the global TypeScript aren't affected because pnpm is installed separately from Node.
- **hcloud and the AWS CLI** are the only tools that need the script to update. Neither has an apt repo or a self-update command, so rerunning the step downloads the latest release. Hetzner's documented command is for x86_64 only; the AWS step also works on aarch64.
- **AWS CLI location.** It installs to `/usr/local/aws-cli`, with `aws` and `aws_completer` linked into `/usr/local/bin`. Each update keeps the previous version's folder under `/usr/local/aws-cli/v2`; old ones can be deleted.
- **SDKMAN's lines in `.bashrc`** must stay at the end of the file. The script runs the SDKMAN step last for that reason. If other lines end up after them, move SDKMAN's three lines (the comment, `export SDKMAN_DIR`, and the `source` line) back to the bottom.
- **Keep projects in `~`, not `/mnt/c`.** Builds are much slower across the Windows boundary, and Ansible ignores an `ansible.cfg` in a world-writable folder, which every `/mnt/c` folder is.
- **Windows tools on your PATH.** WSL adds your Windows PATH to the end of yours. If Node, Java or .NET is also installed on Windows, check with `which <tool>` that you get the Linux version. The script's version summary warns when a tool resolves to `/mnt/c/...`.

## What the script adds beyond official instructions

These parts are the script's own and don't change how any tool is installed:

- the step runner, failure summary and end-of-run version check
- cleanup of installs made by earlier versions of the script
- the Terraform codename fallback
- the nvm newest-version lookup
- running Hetzner's and AWS's commands inside a temporary folder
- choosing AWS's update command instead of the first-install command when `/usr/local/aws-cli` already exists

The Terraform tab-completion line it adds to `.bashrc` is the same line `terraform -install-autocomplete` writes. The hcloud completion line is the one Hetzner's docs say to add, and the AWS completion line is the one from AWS's command-completion page.

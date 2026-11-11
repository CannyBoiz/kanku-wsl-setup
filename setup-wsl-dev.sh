#!/usr/bin/env bash
# =============================================================================
# WSL dev bootstrap (written for Ubuntu 26.04)
#
#   Tool                                     Installed via              Updated by
#   ripgrep (rg), just                       Ubuntu apt                 sudo apt upgrade
#   .NET SDK 10                              Ubuntu apt                 sudo apt upgrade
#   Terraform                                HashiCorp apt repo         sudo apt upgrade
#   Node LTS                                 nvm                        nvm install --lts
#   pnpm                                     standalone installer       pnpm self-update
#   TypeScript                               pnpm global                pnpm update -g
#   Python tooling                           uv (no pip)                uv self update
#   Ansible                                  uv tool                    uv tool upgrade --all
#   hcloud CLI                               Hetzner's documented       re-run: bash setup-wsl-dev.sh hcloud
#                                            tarball -> /usr/local/bin
#   AWS CLI v2                               AWS's documented           re-run: bash setup-wsl-dev.sh aws
#                                            installer -> /usr/local
#   SDKMAN (you install Java yourself)       sdkman.io installer        sdk selfupdate
#
# Usage:
#   bash setup-wsl-dev.sh                 # everything
#   bash setup-wsl-dev.sh sdkman dotnet   # only selected steps
#
# Steps: base ripgrep just node pnpm typescript uv dotnet hcloud aws terraform ansible sdkman
# (sdkman runs last: SDKMAN's docs say its .bashrc snippet must be at the end of the file)
# Re-runnable: steps skip or update what is already installed.
# =============================================================================

set -o pipefail   # deliberately no -e / -u: nvm and SDKMAN aren't safe under them

DOTNET_SDK="${DOTNET_SDK:-dotnet-sdk-10.0}" # apt package; current .NET LTS
ANSIBLE_PYTHON="${ANSIBLE_PYTHON:-3.14}"    # newest Python ansible-core supports (3.12-3.14)
BIN_DIR="$HOME/.local/bin"
ALL_STEPS=(base ripgrep just node pnpm typescript uv dotnet hcloud aws terraform ansible sdkman)
FAILED=()

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

path_prepend() { case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH" ;; esac; }
path_remove()  { PATH=":$PATH:"; PATH="${PATH//:$1:/:}"; PATH="${PATH#:}"; PATH="${PATH%:}"; }

# Append a marked block to ~/.bashrc once.
add_rc() {
  local name="$1"; shift
  grep -qF "# >>> $name >>>" "$HOME/.bashrc" 2>/dev/null && return 0
  { printf '\n# >>> %s >>>\n' "$name"; printf '%s\n' "$@"; printf '# <<< %s <<<\n' "$name"; } >> "$HOME/.bashrc"
}

# Latest release tag via redirect (avoids GitHub API rate limits).
latest_tag() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'
}

# Remove a block previously added by add_rc (used when migrating a tool to apt).
remove_rc() {
  [[ -f "$HOME/.bashrc" ]] || return 0
  sed -i "/^# >>> $1 >>>\$/,/^# <<< $1 <<<\$/d" "$HOME/.bashrc"
}

# Migration from older versions of this script, which put rg/just/hcloud in ~/.local/bin.
# Those copies would shadow the new ones, since ~/.local/bin comes first in PATH.
#   $1 binary name   $2 where the new install lives
drop_local_bin() {
  if [[ -f "$BIN_DIR/$1" ]]; then
    rm -f "$BIN_DIR/$1"
    warn "Removed old $BIN_DIR/$1 so $2 is used"
  fi
}

# Make everything installed so far visible to this script's shell.
load_env() {
  path_prepend "$BIN_DIR"
  # shellcheck disable=SC1091
  [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  export PNPM_HOME="$HOME/.local/share/pnpm"
  path_prepend "$PNPM_HOME"
  path_prepend "$PNPM_HOME/bin"   # pnpm 11+ keeps its binaries and global packages here
  export PATH
}

# ----------------------------------------------------------------------------- steps

step_base() {
  sudo apt-get update || return 1
  sudo apt-get install -y \
    curl wget git ca-certificates gnupg zip unzip tar build-essential bash-completion || return 1
  mkdir -p "$BIN_DIR"
}

# The apt packages ship their own bash completions, so no .bashrc lines needed.
step_ripgrep() {
  sudo apt-get install -y ripgrep || return 1
  drop_local_bin rg /usr/bin/rg
  remove_rc ripgrep-completion
}

step_just() {
  sudo apt-get install -y just || return 1
  drop_local_bin just /usr/bin/just
  remove_rc just-completion
}

step_node() {
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    local ver; ver="$(latest_tag nvm-sh/nvm)"; ver="${ver:-v0.41.0}"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${ver}/install.sh" | bash || return 1
    load_env
  fi
  nvm install --lts || return 1
  nvm alias default 'lts/*'
}

step_pnpm() {
  # Standalone pnpm: independent of whichever Node version nvm has active.
  if ! have pnpm; then
    curl -fsSL https://get.pnpm.io/install.sh | sh - || return 1
    load_env
  else
    pnpm self-update || true
  fi
  have pnpm
}

step_typescript() {
  have pnpm || { warn "pnpm missing, run the pnpm step first"; return 1; }
  have node || { warn "node missing, run the node step first"; return 1; }
  pnpm add -g typescript
}

step_uv() {
  if ! have uv; then
    curl -LsSf https://astral.sh/uv/install.sh | sh || return 1
    load_env
  else
    uv self update || true
  fi
  uv python install   # uv-managed Python, separate from Ubuntu's /usr/bin/python3
}

step_dotnet() {
  # Ubuntu's own .NET packages: maintained by Canonical, security updates via apt.
  # The package also puts ~/.dotnet/tools on PATH (/etc/profile.d/dotnet.sh)
  # and installs bash completion, so no .bashrc lines needed.
  sudo apt-get install -y "$DOTNET_SDK" || return 1

  # Migration from older versions of this script (dotnet-install.sh into ~/.dotnet).
  if grep -qF '# >>> dotnet >>>' "$HOME/.bashrc" 2>/dev/null; then
    remove_rc dotnet
    warn "Removed the old DOTNET_ROOT/PATH lines from ~/.bashrc"
  fi
  unset DOTNET_ROOT
  path_remove "$HOME/.dotnet"
  if [[ -x "$HOME/.dotnet/dotnet" ]]; then
    warn "The old SDK in ~/.dotnet is no longer used. To reclaim the space:"
    warn "  rm -rf ~/.dotnet    (then reinstall any 'dotnet tool install -g' tools)"
  fi
  hash -r
  [[ "$(command -v dotnet)" == /usr/bin/dotnet ]] || warn "dotnet resolves to $(command -v dotnet), expected /usr/bin/dotnet"
  have dotnet
}

step_hcloud() {
  # Hetzner's documented manual install, commands run as-is inside a temp directory.
  # Source: github.com/hetznercloud/cli docs/tutorials/setup-hcloud-cli.md (1.1, 64-bit Linux)
  [[ "$(uname -m)" == x86_64 ]] || { warn "Hetzner's documented command is for x86_64 (you have $(uname -m))"; return 1; }
  local tmp rc
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 1
    curl -sSLO https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz &&
    sudo tar -C /usr/local/bin --no-same-owner -xzf hcloud-linux-amd64.tar.gz hcloud &&
    rm hcloud-linux-amd64.tar.gz
  )
  rc=$?
  rm -rf "$tmp"
  [[ $rc -eq 0 ]] || return 1
  drop_local_bin hcloud /usr/local/bin/hcloud

  # Hetzner's docs (2.1 Bash): append this line to .bashrc for completion.
  # Older versions of this script wrote a guarded variant; rewrite it in place.
  sed -i 's|^command -v hcloud >/dev/null && source <(hcloud completion bash)$|source <(hcloud completion bash)|' "$HOME/.bashrc"
  add_rc hcloud-completion 'source <(hcloud completion bash)'
  hash -r
}

step_aws() {
  # AWS's documented install for AWS CLI v2, commands run as-is inside a temp directory.
  # Source: docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html (Linux)
  local arch tmp rc
  case "$(uname -m)" in
    x86_64)  arch=x86_64 ;;
    aarch64) arch=aarch64 ;;
    *) warn "AWS ships the installer for x86_64 and aarch64 only (you have $(uname -m))"; return 1 ;;
  esac
  have unzip || { warn "unzip missing, run the base step first"; return 1; }
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 1
    curl -fsS "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "awscliv2.zip" &&
    unzip -q awscliv2.zip || exit 1
    if [[ -d /usr/local/aws-cli ]]; then
      # AWS's documented update command (same installer, default locations spelled out).
      sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    else
      sudo ./aws/install
    fi
  )
  rc=$?
  rm -rf "$tmp"
  [[ $rc -eq 0 ]] || return 1

  # AWS's docs (Command completion, Bash): add this line to .bashrc.
  add_rc aws-completion "complete -C '/usr/local/bin/aws_completer' aws"
  hash -r
  [[ "$(command -v aws)" == /usr/local/bin/aws ]] || warn "aws resolves to $(command -v aws), expected /usr/local/bin/aws"
  have aws
}

step_terraform() {
  local keyring=/usr/share/keyrings/hashicorp-archive-keyring.gpg codename fallback
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="${VERSION_CODENAME}"
  if [[ "$ID" == "debian" ]]; then fallback=bookworm; else fallback=noble; fi
  if ! curl -fsSI "https://apt.releases.hashicorp.com/dists/${codename}/Release" >/dev/null; then
    warn "HashiCorp repo has no '${codename}' yet, using '${fallback}' (Terraform is a static binary, works fine)"
    codename="$fallback"
  fi
  if [[ ! -f "$keyring" ]]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --yes --dearmor -o "$keyring" || return 1
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://apt.releases.hashicorp.com ${codename} main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update && sudo apt-get install -y terraform || return 1
  add_rc terraform-completion 'complete -C /usr/bin/terraform terraform'
}

step_ansible() {
  have uv || { warn "uv missing, run the uv step first"; return 1; }
  # Full 'ansible' package (includes hetzner.hcloud collection) with ansible-core's CLIs.
  # requests + python-dateutil are needed by the hetzner.hcloud modules/inventory plugin.
  # --python: ansible-core declares no upper Python bound, so without it uv uses the newest
  # Python (3.15), which ansible-core doesn't support yet and crashes on.
  uv tool install --upgrade \
    --python "$ANSIBLE_PYTHON" \
    --with-executables-from ansible-core \
    --with requests --with python-dateutil \
    ansible
}

step_sdkman() {
  # SDKMAN's documented install (sdkman.io/install). Java itself is up to you:
  #   sdk list java   then   sdk install java <identifier>
  if [[ -d "$HOME/.sdkman" ]]; then
    echo "SDKMAN already installed, skipping (it updates itself; or run: sdk selfupdate)"
  else
    curl -s "https://get.sdkman.io" | bash || return 1
  fi
  # shellcheck disable=SC1091
  source "$HOME/.sdkman/bin/sdkman-init.sh" || return 1
  sdk version
}

# ----------------------------------------------------------------------------- main

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal WSL user (it uses sudo where needed), not as root." >&2
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID_LIKE" != *debian* ]]; then
  echo "This script expects Ubuntu/Debian (found: $ID)." >&2
  exit 1
fi
if [[ "$ID" == "ubuntu" && "$VERSION_ID" != "26.04" ]]; then
  warn "Written for Ubuntu 26.04 (you have $VERSION_ID): apt may lack 'just' or '$DOTNET_SDK' here"
fi
[[ "$PWD" == /mnt/* ]] && warn "You're under /mnt (Windows drive). Keep your projects in ~ for speed and sane permissions."

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=("${ALL_STEPS[@]}")

sudo -v || exit 1
load_env

for s in "${steps[@]}"; do
  if ! declare -F "step_$s" >/dev/null; then warn "Unknown step: $s"; continue; fi
  log "$s"
  if ! "step_$s"; then FAILED+=("$s"); warn "Step '$s' failed, continuing"; fi
  load_env
done

log "Versions"
check() {
  local name="$1"; shift
  local path; path="$(command -v "$name" 2>/dev/null)"
  if [[ -z "$path" ]]; then printf '  %-10s %s\n' "$name" "(not found)"; return; fi
  [[ "$path" == /mnt/* ]] && warn "$name resolves to a Windows binary: $path"
  local out; out="$("$@" 2>&1)"   # read everything; '| head -1' makes some CLIs crash on a broken pipe
  printf '  %-10s %s\n' "$name" "${out%%$'\n'*}"
}
check rg        rg --version
check just      just --version
check node      node -v
check pnpm      pnpm -v
check tsc       tsc -v
check uv        uv -V
check dotnet    dotnet --version
check hcloud    hcloud version
check aws       aws --version
check terraform terraform -version
check ansible   ansible --version
sdk_ver() { sdk version 2>/dev/null | grep -m1 -E '[0-9]+\.[0-9]+'; }
check sdk       sdk_ver

if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "Failed steps: ${FAILED[*]}  (re-run with: bash $0 ${FAILED[*]})"
fi
echo
echo "Done. Open a new terminal (or run: exec bash) so all PATH changes apply."

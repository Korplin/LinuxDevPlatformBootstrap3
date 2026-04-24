# DevPlatform Bootstrap — Code Review Report

**Files reviewed:** `devplatform.yml` · `devplatformbootstrap.sh`  
**Repository:** https://github.com/Korplin/LinuxDevPlatformBootstrap2  
**Target OS:** Debian 13 "trixie" amd64  
**Verdict:** Not production-grade yet — fixable issues found. Structure and idiomatic quality are above average.

---

## Table of Contents

- [Summary](#summary)
- [Bugs](#bugs)
- [Pitfalls](#pitfalls)
- [Security Issues](#security-issues)
- [Quality / Idempotency Issues](#quality--idempotency-issues)
- [What Is Done Well](#what-is-done-well)

---

## Summary

| Category | Count | Priority |
|---|---|---|
| 🐛 Bugs | 4 | Fix before publishing |
| ⚠️ Pitfalls | 4 | Fix before first real use |
| 🔒 Security | 3 | Fix before making repo public |
| 💡 Quality / Idempotency | 4 | Fix for maintainability |

---

## Bugs

> Bugs cause incorrect or broken behavior. Fix all of these before publishing.

---

### BUG-1 · Intel GPU detection is case-sensitive; NVIDIA and AMD are not

**File:** `devplatform.yml`  
**Line:** 158  
**Fixable by:** AI agent or human
**Status:** Fixed, not tested

**Problem:**  
NVIDIA and AMD GPU detection uses Jinja2's `| upper` filter to make the `lspci` output comparison case-insensitive. The Intel check does not. If `lspci` outputs `"INTEL"` or `"intel"` — possible with some drivers or kernel versions — the detection silently fails and no Intel GPU drivers are installed.

**Current code:**
```yaml
has_nvidia:    "{{ 'NVIDIA' in lspci_output.stdout | upper }}"
has_amd:       "{{ ('AMD' in lspci_output.stdout | upper) or ('ATI' in lspci_output.stdout | upper) }}"
has_intel_gpu: "{{ 'Intel' in lspci_output.stdout and ('VGA' in lspci_output.stdout or 'Display' in lspci_output.stdout) }}"
```

**Fixed code:**
```yaml
has_nvidia:    "{{ 'NVIDIA' in lspci_output.stdout | upper }}"
has_amd:       "{{ ('AMD' in lspci_output.stdout | upper) or ('ATI' in lspci_output.stdout | upper) }}"
has_intel_gpu: "{{ ('INTEL' in lspci_output.stdout | upper) and ('VGA' in lspci_output.stdout | upper or 'DISPLAY' in lspci_output.stdout | upper) }}"
```

**AI agent instruction:**  
In `devplatform.yml`, find the `set_fact` task named `[detect] Set environment facts`. Replace the `has_intel_gpu` value with:
```
"{{ ('INTEL' in lspci_output.stdout | upper) and ('VGA' in lspci_output.stdout | upper or 'DISPLAY' in lspci_output.stdout | upper) }}"
```

---

### BUG-2 · SSH restart handler is dead code — never notified

**File:** `devplatform.yml`  
**Line:** 80–83  
**Fixable by:** Human (requires deciding on SSH hardening scope)
**Status:** Fixed, not tested

**Problem:**  
A `Restart ssh` handler is defined but no task in the playbook uses `notify: Restart ssh`. This handler never fires. Its presence suggests an SSH hardening task was planned but not implemented. As a side effect, if openssh-server configuration is written in a future task, the service will not be restarted and the config will not take effect until the next reboot.

**Current code:**
```yaml
handlers:
  - name: Restart ssh
    ansible.builtin.systemd:
      name: ssh
      state: restarted
```

**Fix options (human decides):**

Option A — Remove the dead handler if SSH hardening is out of scope:
```yaml
# Delete the entire handlers block (lines 79–83) if no SSH hardening will be added.
```

Option B — Add an SSH hardening task that actually notifies the handler:
```yaml
- name: "[SSH] Write sshd hardening config"
  ansible.builtin.copy:
    dest: /etc/ssh/sshd_config.d/devplatform.conf
    owner: root
    group: root
    mode: "0644"
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      X11Forwarding no
  notify: Restart ssh
```

**AI agent instruction:**  
In `devplatform.yml`, search for `notify: Restart ssh`. If no task in the file contains that string, either delete the `handlers` block entirely (lines 79–83) or add the hardening task from Option B above before the `tasks:` section ends.

---

### BUG-3 · PATH addition targets `~/.profile` but login shell is zsh

**File:** `devplatform.yml`  
**Line:** 917–925  
**Fixable by:** AI agent or human
**Status:** Fixed, not tested


**Problem:**  
The `~/.local/bin` PATH entry is written to `~/.profile`. Zsh — the login shell being configured by this very playbook — reads `~/.zprofile` for login shells, not `~/.profile`. `~/.profile` is sourced by bash and sh. On a bare tty login, SSH session, or any non-interactive login with zsh, `~/.local/bin` will not be in PATH, causing `pipx` tools, `uv`, `pre-commit`, and `cookiecutter` to be command-not-found. The `~/.zshrc` addition (line 1299) covers interactive sessions only.

**Current code:**
```yaml
- name: "[PYTHON] Ensure ~/.local/bin is on PATH in .profile"
  ansible.builtin.lineinfile:
    path: "{{ real_home }}/.profile"
    line: 'export PATH="$HOME/.local/bin:$PATH"'
    state: present
    create: true
    mode: "0644"
  become: true
  become_user: "{{ real_user }}"
```

**Fixed code:**
```yaml
- name: "[PYTHON] Ensure ~/.local/bin is on PATH in .zprofile"
  ansible.builtin.lineinfile:
    path: "{{ real_home }}/.zprofile"
    line: 'export PATH="$HOME/.local/bin:$PATH"'
    state: present
    create: true
    mode: "0644"
  become: true
  become_user: "{{ real_user }}"
  # Reason: zsh reads ~/.zprofile for login shells, not ~/.profile.
  # ~/.zshrc (interactive sessions) already sets this PATH.
  # ~/.zprofile covers login shells: bare tty, SSH, sddm session startup.

- name: "[PYTHON] Ensure ~/.local/bin is on PATH in .profile (bash fallback)"
  ansible.builtin.lineinfile:
    path: "{{ real_home }}/.profile"
    line: 'export PATH="$HOME/.local/bin:$PATH"'
    state: present
    create: true
    mode: "0644"
  become: true
  become_user: "{{ real_user }}"
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[PYTHON] Ensure ~/.local/bin is on PATH in .profile`. Change the `path:` value from `"{{ real_home }}/.profile"` to `"{{ real_home }}/.zprofile"` and update the task name to `[PYTHON] Ensure ~/.local/bin is on PATH in .zprofile`. Optionally duplicate the task with the original `.profile` path as a bash fallback.

---

### BUG-4 · `changed_when: true` on VS Code signing key install always reports changed

**File:** `devplatform.yml`  
**Line:** 696  
**Fixable by:** AI agent  

**Problem:**  
`changed_when: true` causes this task to report as *changed* on every single playbook run, including fully idempotent re-runs where nothing actually changed. This makes `--diff` output noisy and breaks the ability to verify at a glance whether a re-run had any real effect.

**Current code:**
```yaml
- name: "[VSCODE] Install Microsoft signing key"
  ansible.builtin.shell: |
    set -euo pipefail
    gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft.gpg
    chmod 0644 /usr/share/keyrings/microsoft.gpg
  args:
    executable: /bin/bash
  changed_when: true
```

**Fixed code:**
```yaml
- name: "[VSCODE] Install Microsoft signing key"
  ansible.builtin.shell: |
    set -euo pipefail
    gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft.gpg
    chmod 0644 /usr/share/keyrings/microsoft.gpg
  args:
    executable: /bin/bash
  changed_when: false
  # Reason: gpg --dearmor is deterministic — same key in always produces the
  # same key out. The preceding tasks that delete and re-download the key
  # already handle the "key changed upstream" case by always forcing a fresh
  # download (force: true). Reporting changed here adds no information.
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[VSCODE] Install Microsoft signing key`. Change `changed_when: true` to `changed_when: false`.

---

## Pitfalls

> Pitfalls will not fail outright but will cause unexpected, hard-to-debug behavior.

---

### PITFALL-1 · Full system upgrade runs at the END — wrong ordering

**File:** `devplatform.yml`  
**Line:** 1378–1382  
**Fixable by:** Human (requires moving a block and verifying task ordering)
**Status:** Fixed by human, not tested

**Problem:**  
`apt full-upgrade` runs as the very last task, after every package has already been installed. This has two consequences:

1. Packages installed mid-run may be slightly behind their latest point release if security updates were available during the run.
2. An outdated baseline (e.g. a stale libc or libssl) can cause dependency resolution failures mid-playbook that a pre-run upgrade would have prevented.

The upgrade should happen immediately after sources.list is written and the cache is refreshed, before any packages are installed.

**Fix — move this block:**
```yaml
# Move these three tasks to immediately AFTER the task named:
# "[APT] Refresh package cache after sources.list update"
# and BEFORE the "[detect] Query PCI devices" task.

- name: "[APT] Full system upgrade"
  ansible.builtin.apt:
    upgrade: dist          # 'dist' is safer than 'full' — see QUAL-4
    update_cache: false    # cache was just refreshed by the preceding task

- name: "[APT] Remove orphaned packages"
  ansible.builtin.apt:
    autoremove: true
    purge: true

- name: "[APT] Clean apt package cache"
  ansible.builtin.apt:
    autoclean: true
```

Keep the existing `[FINAL]` cleanup tasks at the end of the file to remove temp files and print the summary. Only the upgrade/autoremove/autoclean should move forward.

**AI agent instruction:**  
In `devplatform.yml`, cut the three tasks named `[FINAL] Full system upgrade`, `[FINAL] Remove orphaned packages`, and `[FINAL] Clean apt package cache`. Paste them immediately after the task named `[APT] Refresh package cache after sources.list update` (around line 122). Rename them `[APT] Full system upgrade`, `[APT] Remove orphaned packages`, and `[APT] Clean apt package cache` respectively.

---

### PITFALL-2 · Global npm packages re-install silently on every run

**File:** `devplatform.yml`  
**Line:** 885–897  
**Fixable by:** AI agent  

**Problem:**  
`changed_when: false` suppresses the changed report, but `npm install -g pnpm yarn typescript ts-node nodemon http-server` still executes on every playbook run. This silently adds 20–40 seconds to every re-run, re-downloads packages unnecessarily, and never reports a change even on the first install (making it impossible to verify the task did anything).

**Current code:**
```yaml
- name: "[NVM] Install global npm packages"
  ansible.builtin.shell: |
    export NVM_DIR="{{ real_home }}/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    npm install -g pnpm yarn typescript ts-node nodemon http-server
  ...
  changed_when: false
```

**Fixed code:**
```yaml
- name: "[NVM] Install global npm packages"
  ansible.builtin.shell: |
    export NVM_DIR="{{ real_home }}/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    _changed=0
    _install_if_missing() {
      if ! npm list -g --depth=0 "$1" &>/dev/null; then
        npm install -g "$1"
        _changed=1
      fi
    }
    _install_if_missing pnpm
    _install_if_missing yarn
    _install_if_missing typescript
    _install_if_missing ts-node
    _install_if_missing nodemon
    _install_if_missing http-server
    echo "$_changed"
  args:
    executable: /bin/bash
  become: true
  become_user: "{{ real_user }}"
  environment:
    HOME: "{{ real_home }}"
    NVM_DIR: "{{ real_home }}/.nvm"
  register: _npm_global
  changed_when: _npm_global.stdout | trim == '1'
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[NVM] Install global npm packages`. Replace the `cmd` shell block and `changed_when: false` with the fixed version above that checks each package individually with `npm list -g` before installing, and reports `changed` only when at least one package was newly installed.

---

### PITFALL-3 · `ignore_errors: true` on Intel GPU task silently swallows real failures

**File:** `devplatform.yml`  
**Line:** 357  
**Fixable by:** Human  

**Problem:**  
`ignore_errors: true` is a broad suppressor. While the comment explains it handles removed packages (correct — `xserver-xorg-video-intel` was dropped from Debian 13), it also silently swallows network failures, broken dependencies, and package conflicts. A genuine system error here would be invisible.

**Current code:**
```yaml
- name: "[gpu/intel] Install Intel GPU drivers and VA-API acceleration"
  ansible.builtin.apt:
    name:
      - intel-media-va-driver
      - libgl1-mesa-dri
      - mesa-vulkan-drivers
    state: present
  when: has_intel_gpu and is_bare_metal
  ignore_errors: true
```

**Fixed code:**  
Remove `ignore_errors: true`. The packages listed (`intel-media-va-driver`, `libgl1-mesa-dri`, `mesa-vulkan-drivers`) are all present in Debian 13 trixie — they do not need error suppression. The removed packages (`xserver-xorg-video-intel`, `i965-va-driver`) are already excluded from the list. Since only valid packages remain, this task should succeed cleanly.

```yaml
- name: "[gpu/intel] Install Intel GPU drivers and VA-API acceleration"
  ansible.builtin.apt:
    name:
      - intel-media-va-driver
      - libgl1-mesa-dri
      - mesa-vulkan-drivers
    state: present
  when: has_intel_gpu and is_bare_metal
  # Note: xserver-xorg-video-intel and i965-va-driver were removed from
  # Debian 13 and are intentionally excluded from this list.
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[gpu/intel] Install Intel GPU drivers and VA-API acceleration`. Remove the `ignore_errors: true` line. Verify the package list does not include `xserver-xorg-video-intel` or `i965-va-driver`.

---

### PITFALL-4 · `alias grep='rg'` and `alias find='fd'` break standard command syntax

**File:** `devplatform.yml`  
**Line:** 1354–1355  
**Fixable by:** Human  

**Problem:**  
`rg` and `fd` do not support all flags of `grep` and `find`. Commands copied from documentation or manpages will silently fail or error:

- `grep -P "pattern" file` → `rg` uses `--pcre2` instead of `-P` → error
- `grep -c "pattern" file` → `rg -c` behaves differently (counts per-file matches, not total)
- `find . -type f -exec cmd {} \;` → `fd` does not support `-exec ... \;` syntax → error

Aliases apply only to interactive shells (not scripts), limiting the blast radius — but developers constantly type commands from documentation interactively, making this a practical daily friction point.

**Fix:**  
Remove the aliases that override standard POSIX tool names. Keep the modern tools available under their own names:

```bash
# In the aliases block of .zshrc — REMOVE these two lines:
# alias grep='rg'
# alias find='fd'

# KEEP these (non-conflicting):
alias cat='bat --paging=never'
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias tree='eza --tree --icons'

# OPTIONAL — add convenience shortcuts without overriding standard names:
alias rg='rg --smart-case'          # enhance rg, don't replace grep
alias fd='fd --hidden'              # enhance fd, don't replace find
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[SHELL] Add shell aliases for modern CLI tools`. In the `block:` content, remove the two lines:
```
          alias grep='rg'                     # ripgrep as default grep
          alias find='fd'                     # fd as default find
```

---

## Security Issues

> Fix these before making the repository public.

---

### SEC-1 · No integrity check on downloaded playbook in bootstrap script

**File:** `devplatformbootstrap.sh`  
**Line:** 271–299  
**Fixable by:** Human (requires publishing a checksum file alongside the playbook)  

**Problem:**  
The bootstrap script downloads the playbook from GitHub raw and immediately executes it as root. The only "validation" is `grep -q "^- name:"` which would pass on any file containing that string — including a GitHub 404 HTML page that happened to include that substring. A compromised repository, CDN tamper, or network-level injection on an untrusted network would result in arbitrary code execution as root.

**Fix — Step 1:** Add a `devplatform.yml.sha256` file to the repository. Generate it after every release:
```bash
sha256sum devplatform.yml > devplatform.yml.sha256
# Contents of devplatform.yml.sha256:
# abc123def456...  devplatform.yml
```

**Fix — Step 2:** In `devplatformbootstrap.sh`, replace the weak `grep` check with a real verification:
```bash
CHECKSUM_FILENAME="${PLAYBOOK_FILENAME}.sha256"
CHECKSUM_URL="${GITHUB_RAW_BASE}/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${CHECKSUM_FILENAME}"
CHECKSUM_DEST="/tmp/${CHECKSUM_FILENAME}"

# Download checksum file
if ! curl -fsSL --retry 3 -o "${CHECKSUM_DEST}" "${CHECKSUM_URL}"; then
    die "Failed to download checksum file.\n  URL: ${CHECKSUM_URL}"
fi

# Verify the downloaded playbook matches the published checksum
if ! (cd /tmp && sha256sum -c "${CHECKSUM_FILENAME}" --status); then
    die "Playbook checksum verification FAILED.\n" \
        "  The downloaded file does not match the expected checksum.\n" \
        "  Do not proceed. Investigate before re-running."
fi

success "Playbook checksum verified."
```

**AI agent instruction:**  
This fix requires two coordinated changes: (1) a CI/CD step or manual step to publish `devplatform.yml.sha256` to the repo, and (2) adding the checksum download and `sha256sum -c` verification block in `devplatformbootstrap.sh` after the playbook download, replacing the `grep -q "^- name:"` check. The AI agent can implement step 2; a human must implement step 1.

---

### SEC-2 · openssh-server installed without hardening

**File:** `devplatform.yml`  
**Line:** 1016  
**Fixable by:** AI agent or human  

**Problem:**  
`openssh-server` is installed in the DevOps utilities block. Debian's default sshd configuration ships with password authentication enabled and root login as `prohibit-password`. On a developer workstation connected to any non-isolated network, this is unnecessarily permissive. The `Restart ssh` handler (BUG-2) exists but is never triggered, so even if config were written, it would not take effect until reboot.

**Fix — add a hardening task after the DevOps packages block:**
```yaml
- name: "[SSH] Write sshd hardening configuration"
  ansible.builtin.copy:
    dest: /etc/ssh/sshd_config.d/devplatform.conf
    owner: root
    group: root
    mode: "0600"
    content: |
      # Managed by devplatform.yml
      # Drop-in config — overrides defaults in /etc/ssh/sshd_config
      PermitRootLogin no
      PasswordAuthentication no
      X11Forwarding no
      MaxAuthTries 3
      LoginGraceTime 30
  notify: Restart ssh
  # Reason: Disabling password auth forces key-based auth only.
  # PermitRootLogin no prevents direct root SSH even with a key.
  # X11Forwarding no closes a forwarding attack surface.
  # These are standard hardening settings for a dev workstation.
  # The user must add their public key to ~/.ssh/authorized_keys before
  # applying this — otherwise they will be locked out over SSH.
```

**Important prerequisite:** Ensure the real user has an `~/.ssh/authorized_keys` file before `PasswordAuthentication no` takes effect, or provide a task to set one up. If this is a desktop machine accessed only locally, consider keeping `PasswordAuthentication yes`.

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[DEVOPS] Install core DevOps utility packages` (the large apt task that includes `openssh-server`). Insert the SSH hardening task shown above immediately after it. Also ensure the `Restart ssh` handler exists in the `handlers:` block (it does — see BUG-2).

---

### SEC-3 · Multiple binary downloads without checksum verification

**File:** `devplatform.yml`  
**Lines:** 536–546 (lazygit), 965–975 (uv), 1055–1063 (yq), 1135–1144 (kubectl), 1220–1225 (k9s), 1253–1261 (cosign)  
**Fixable by:** Human and AI agent (pattern is repeatable once established)  

**Problem:**  
The following tools are downloaded and installed as root with no checksum verification: `lazygit`, `uv`, `yq`, `kubectl`, `k9s`, `cosign`. The Helm section already does this correctly. `cosign` — a tool specifically designed for supply-chain security — being installed without verification is particularly contradictory.

**Reference — the correct pattern already used for Helm:**
```yaml
- name: "[HELM] Download Helm checksum"
  ansible.builtin.get_url:
    url: "https://get.helm.sh/helm-{{ helm_version }}-linux-{{ helm_arch }}.tar.gz.sha256sum"
    dest: "/tmp/helm-{{ helm_version }}-linux-{{ helm_arch }}.tar.gz.sha256sum"
    mode: "0644"
  when: helm_version not in (_helm_installed.stdout | default(''))

- name: "[HELM] Verify Helm checksum"
  ansible.builtin.shell: |
    set -euo pipefail
    cd /tmp
    sha256sum -c "helm-{{ helm_version }}-linux-{{ helm_arch }}.tar.gz.sha256sum"
  args:
    executable: /bin/bash
  changed_when: false
  when: helm_version not in (_helm_installed.stdout | default(''))
```

**Fix for kubectl (official SHA file available):**
```yaml
- name: "[KUBECTL] Download kubectl checksum"
  ansible.builtin.shell:
    cmd: |
      set -euo pipefail
      VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
      curl -sLO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl.sha256"
      echo "  kubectl" >> kubectl.sha256
    executable: /bin/bash
  when: not _kubectl_stat.stat.exists

- name: "[KUBECTL] Verify kubectl checksum"
  ansible.builtin.shell:
    cmd: sha256sum -c kubectl.sha256
    executable: /bin/bash
  changed_when: false
  when: not _kubectl_stat.stat.exists
```

**Fix for cosign — use `get_url` checksum parameter:**
```yaml
- name: "[COSIGN] Install cosign binary"
  ansible.builtin.get_url:
    url: https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
    dest: /usr/local/bin/cosign
    checksum: "sha256:https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64.sha256"
    owner: root
    group: root
    mode: "0755"
    force: false
  when: not _cosign_stat.stat.exists
```

**Fix for yq — use `get_url` checksum parameter:**
```yaml
- name: "[YQ] Install yq Go binary (mikefarah/yq)"
  ansible.builtin.get_url:
    url: https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    dest: /usr/local/bin/yq
    checksum: "sha256:https://github.com/mikefarah/yq/releases/latest/download/checksums"
    owner: root
    group: root
    mode: "0755"
    force: false
  when: not _yq_stat.stat.exists
```

**AI agent instruction:**  
For each binary download task listed above, add checksum verification using the `checksum:` parameter of `ansible.builtin.get_url` where the upstream provides a `.sha256` file at a predictable URL. For tools downloaded via `shell` (lazygit, kubectl), add a separate download + `sha256sum -c` step following the Helm pattern. Priority order: cosign, kubectl, k9s, yq, lazygit, uv.

---

## Quality / Idempotency Issues

> These do not cause failures but affect maintainability, re-run accuracy, and long-term reliability.

---

### QUAL-1 · `ansible.builtin.shell` used for a plain command

**File:** `devplatform.yml`  
**Line:** 136  
**Fixable by:** AI agent  

**Problem:**  
`lspci -nn` uses no shell features (no pipes, no redirects, no globs, no variable expansion). Using `ansible.builtin.shell` triggers ansible-lint's `command-instead-of-shell` rule and is considered a code smell. `ansible.builtin.command` is safer — it does not invoke a shell and avoids accidental shell injection.

**Current code:**
```yaml
- name: "[detect] Query PCI devices"
  ansible.builtin.shell:
    cmd: lspci -nn
  register: lspci_output
  changed_when: false
```

**Fixed code:**
```yaml
- name: "[detect] Query PCI devices"
  ansible.builtin.command:
    cmd: lspci -nn
  register: lspci_output
  changed_when: false
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[detect] Query PCI devices`. Change `ansible.builtin.shell:` to `ansible.builtin.command:`.

---

### QUAL-2 · `changed_when: false` on Flatpak remote add always reports not-changed

**File:** `devplatform.yml`  
**Line:** 609  
**Fixable by:** AI agent  

**Problem:**  
`flatpak remote-add --if-not-exists` handles idempotency correctly at the Flatpak level — it does nothing if Flathub is already registered. However, `changed_when: false` means the first run (when the remote is genuinely being added for the first time) also reports as "not changed." This makes it impossible to verify from the Ansible output whether Flathub was already there or just added.

**Current code:**
```yaml
- name: "[FLATPAK] Add Flathub remote"
  ansible.builtin.command:
    cmd: flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  changed_when: false
```

**Fixed code:**
```yaml
- name: "[FLATPAK] Check if Flathub remote is already registered"
  ansible.builtin.command:
    cmd: flatpak remote-list
  register: _flatpak_remotes
  changed_when: false

- name: "[FLATPAK] Add Flathub remote"
  ansible.builtin.command:
    cmd: flatpak remote-add flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  when: "'flathub' not in _flatpak_remotes.stdout"
  # Reason: Splitting the check from the add gives accurate changed reporting.
  # The task only runs — and only reports changed — when Flathub is genuinely absent.
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[FLATPAK] Add Flathub remote`. Replace it with two tasks: a `flatpak remote-list` check task registered as `_flatpak_remotes` with `changed_when: false`, followed by the add task with `when: "'flathub' not in _flatpak_remotes.stdout"` and `--if-not-exists` removed.

---

### QUAL-3 · `upgrade: full` is more aggressive than needed

**File:** `devplatform.yml`  
**Line:** 1380  
**Fixable by:** AI agent  

**Problem:**  
`upgrade: full` maps to `apt full-upgrade`, which can automatically remove installed packages to resolve dependency conflicts. On an already-bootstrapped system being re-run for drift correction, this could unexpectedly remove something. `upgrade: dist` provides equivalent behavior on a clean system but uses a more conservative conflict resolution strategy.

**Current code:**
```yaml
- name: "[FINAL] Full system upgrade"
  ansible.builtin.apt:
    upgrade: full
    update_cache: true
```

**Fixed code:**
```yaml
- name: "[APT] System upgrade"
  ansible.builtin.apt:
    upgrade: dist
    update_cache: false   # cache was refreshed earlier; set true if this task is moved
  # Reason: 'dist' is equivalent to apt-get dist-upgrade, which handles new
  # dependency requirements but uses a more conservative conflict resolution
  # strategy than full-upgrade. Safer for re-runs on partially-configured systems.
```

**AI agent instruction:**  
In `devplatform.yml`, find the task named `[FINAL] Full system upgrade`. Change `upgrade: full` to `upgrade: dist`.

---

### QUAL-4 · Upgrade of binary tools requires manual deletion — not documented prominently

**File:** `devplatform.yml`  
**Lines:** 960–975 (uv), 1050–1064 (yq), 1130–1145 (kubectl), 1215–1241 (k9s), 1248–1261 (cosign)  
**Fixable by:** Human  

**Problem:**  
All binary tools that use a `stat` guard for idempotency (uv, yq, kubectl, k9s, cosign) can only be upgraded by manually deleting the binary and re-running the playbook. This is mentioned in individual comments but is not consolidated anywhere visible to users. The same pattern applies to the NVM install, JetBrainsMono font, and Cursor IDE.

**Fix — add an upgrade section to the repository README.md:**

```markdown
## Upgrading individual tools

Binary tools managed by a `stat` guard are only installed once. To upgrade any of them,
delete the binary and re-run `bash bootstrap.sh`.

| Tool | Delete this path |
|---|---|
| kubectl | `/usr/local/bin/kubectl` |
| helm | Change `helm_version` in `devplatform.yml` vars |
| k9s | `/usr/local/bin/k9s` |
| cosign | `/usr/local/bin/cosign` |
| yq | `/usr/local/bin/yq` |
| lazygit | `/usr/local/bin/lazygit` |
| uv | `~/.local/bin/uv` |
| Cursor IDE | `/usr/bin/cursor` |
| JetBrainsMono Nerd Font | `/usr/local/share/fonts/nerd-fonts/.devplatform-installed` |
| Node.js (via nvm) | `nvm install --lts && nvm alias default node` (no re-run needed) |
```

**Optional fix — add a `force_reinstall` variable to the playbook vars section:**
```yaml
vars:
  # Set to true to force re-download of all stat-guarded binaries
  # Usage: ansible-playbook devplatform.yml -e "force_reinstall=true"
  force_reinstall: false
```

Then modify stat-guarded tasks:
```yaml
when: not _kubectl_stat.stat.exists or force_reinstall | bool
```

**AI agent instruction:**  
In `devplatform.yml`, add `force_reinstall: false` to the `vars:` block at the top of the file. Then, for each task that uses `when: not _<name>_stat.stat.exists`, change the condition to `when: not _<name>_stat.stat.exists or force_reinstall | bool`. Affected tasks: kubectl, k9s, cosign, yq, uv, lazygit, cursor, nvm.

---

## What Is Done Well

These patterns are correct and should be preserved as reference implementations within the project.

| Pattern | Location | Why it is correct |
|---|---|---|
| Fully-qualified `ansible.builtin.*` module names | Throughout | No ambiguity with community collections |
| `getent passwd` for home directory | pre_tasks | Handles non-standard home paths authoritatively |
| `append: true` on all group membership tasks | KVM, Docker | Prevents accidental removal of other groups |
| Helm checksum verification | HELM section | The pattern all binary installs should follow |
| `become_user: real_user` for nvm/pipx/uv | NVM, Python | Correctly scopes per-user tools to the real user |
| VirtualBox ISO detection with graceful fallback | VirtualBox section | Warns and continues; re-runnable after ISO insertion |
| Docker GPG key in `/etc/apt/keyrings/` | DOCKER section | Uses the Debian 12+ standard location |
| `set -euo pipefail` in all shell tasks | Throughout | Prevents silent partial failures in shell blocks |
| Self-escalation via `exec sudo` | bootstrap.sh | Preserves `SUDO_USER` correctly for the playbook |
| Kubectl skips broken pkgs.k8s.io GPG v3 path | KUBECTL section | Documents and correctly avoids a real Debian 13 incompatibility |

---

*Generated by code review · `devplatform.yml` + `devplatformbootstrap.sh` · Debian 13 trixie*

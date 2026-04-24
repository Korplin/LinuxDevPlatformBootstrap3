# DevPlatform Bootstrap — Code Review Report

**Files reviewed:** `devplatform.yml` · `devplatformbootstrap.sh`  
**Repository:** https://github.com/Korplin/LinuxDevPlatformBootstrap2  
**Target OS:** Debian 13 "trixie" amd64  
**Verdict:** Not production-grade yet — fixable issues found. Structure and idiomatic quality are above average.

---

## Table of Contents

- [Summary](#summary)
- [Bugs](#bugs)
- [Pitfalls and Hidden Failures](#pitfalls-and-hidden-failures)
- [Security Issues](#security-issues)
- [Idempotency Issues](#idempotency-issues)
- [Design Choices Worth Documenting](#design-choices-worth-documenting)
- [What Is Done Well](#what-is-done-well)

---

## Summary

| Category | Count | Priority |
|---|---|---|
| 🐛 Bugs | 5 | Fix before first use |
| ⚠️ Pitfalls | 5 | Fix before first real use |
| 🔒 Security | 4 | Fix before making repo public |
| 🔁 Idempotency | 4 | Fix for reliable re-runs |
| 📝 Design | 3 | Document or improve for maintainability |

---

## Bugs

> Bugs cause incorrect or broken behavior on at least some execution paths. Fix all of these before publishing.

---

### BUG-1 · SSH `notify` is a misindented module parameter — handler block is also missing

**File:** `devplatform.yml`  
**Line:** 1403–1413  
**Fixable by:** AI agent or human  
**Status:** Fixed, need review / testing

**Problem:**  
The `[SSH] Write sshd hardening config` task contains `notify: Restart ssh` indented at 8 spaces, which places it inside the `ansible.builtin.copy` module's parameter dictionary. Ansible silently ignores unknown module parameters and never triggers the handler. Additionally, there is no `handlers:` block defined anywhere in the playbook, so even if the indentation were corrected, Ansible would raise `ERROR! The requested handler 'Restart ssh' was not found` and abort. The hardening config file is written correctly but the SSH service is never restarted, meaning the config takes effect only after the reboot that is instructed at the end.

**Current code (broken):**
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
    notify: Restart ssh        # ← 8 spaces: inside the module, not the task
```

**Fixed code:**
```yaml
  handlers:
    - name: Restart ssh
      ansible.builtin.systemd:
        name: ssh
        state: restarted

  tasks:

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
      notify: Restart ssh      # ← 6 spaces: task level, outside the module
```

**Human instructions:**  
1. Open `devplatform.yml`.
2. Find the `tasks:` key near the top of the play. Immediately before it, add a `handlers:` block containing the `Restart ssh` handler shown above.
3. Scroll to the `[SSH] Write sshd hardening config` task. The `notify: Restart ssh` line is currently indented with 8 spaces (same level as `dest:`, `mode:`, etc.). Outdent it by 2 spaces so it sits at 6-space indent alongside `ansible.builtin.copy:`.

**AI agent instructions:**  
1. In `devplatform.yml`, locate the `tasks:` key. Insert the following block immediately before it:
   ```yaml
     handlers:
       - name: Restart ssh
         ansible.builtin.systemd:
           name: ssh
           state: restarted
   ```
2. In the same file, find the task named `[SSH] Write sshd hardening config`. Locate the line `        notify: Restart ssh` (8-space indent). Remove it from inside the `ansible.builtin.copy:` parameter block. Add `    notify: Restart ssh` (6-space indent) as a new key at task level, after the closing of the `ansible.builtin.copy:` parameters.

---

### BUG-2 · Repository name mismatch between comment and variable

**File:** `devplatformbootstrap.sh`  
**Lines:** 7 and 31  
**Fixable by:** Human (needs to confirm which name is correct)  
**Status:** Fixed

**Problem:**  
The header comment on line 7 references `LinuxDevPlatformBootstrap2` while the actual `GITHUB_REPO` variable on line 31 is set to `LinuxDevPlatformBootstrap3`. One of these is wrong. The variable controls the actual download URL, so if the repo was renamed to Bootstrap3 the comment is stale; if the repo is still Bootstrap2, the variable is wrong and every playbook download will silently 404. GitHub raw 404 responses return HTML that does not contain `^- name:`, so the downstream sanity check will catch it — but only after a misleading download failure.

**Current code:**
```bash
# Line 7 (comment):
# Repository : https://github.com/Korplin/LinuxDevPlatformBootstrap2

# Line 31 (variable):
GITHUB_REPO="LinuxDevPlatformBootstrap3"
```

**Fixed code — if the repo is named Bootstrap3 (update comment):**
```bash
# Repository : https://github.com/Korplin/LinuxDevPlatformBootstrap3
GITHUB_REPO="LinuxDevPlatformBootstrap3"
```

**Fixed code — if the repo is still named Bootstrap2 (update variable):**
```bash
# Repository : https://github.com/Korplin/LinuxDevPlatformBootstrap2
GITHUB_REPO="LinuxDevPlatformBootstrap2"
```

**Human instructions:**  
1. Check your actual GitHub repository name in your browser.
2. If it is `LinuxDevPlatformBootstrap3`, update line 7's comment URL to match.
3. If it is `LinuxDevPlatformBootstrap2`, change `GITHUB_REPO` on line 31 to `"LinuxDevPlatformBootstrap2"`.
4. Also verify the `devplatform.yml` header comment on line 6–7 references the correct URL and update it to match.

**AI agent instructions:**  
In `devplatformbootstrap.sh`, read the value of `GITHUB_REPO` on line 31. Find every URL in the file's comments that references the repository name. Replace all occurrences of the mismatched name with the value from `GITHUB_REPO` so the comment and the variable agree. Also update the `devplatform.yml` header comment (line 7) to match.

---

### BUG-3 · Intel GPU detection is case-sensitive; NVIDIA and AMD are not

**File:** `devplatform.yml`  
**Line:** 170  
**Fixable by:** AI agent  
**Status:** Fixed, need review testing

**Problem:**  
NVIDIA and AMD GPU detection uses the `| upper` Jinja2 filter to make string matching case-insensitive. The Intel check does not. If `lspci` outputs `INTEL`, `intel`, or any variant, the detection silently fails and no Intel GPU drivers are installed. The behavior is inconsistent across all three GPU vendor checks in the same `set_fact` task.

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
has_intel_gpu: "{{ ('INTEL' in lspci_output.stdout | upper) and (('VGA' in lspci_output.stdout | upper) or ('DISPLAY' in lspci_output.stdout | upper)) }}"
```

**Human instructions:**  
1. Open `devplatform.yml` and find the `[detect] Set environment facts` `set_fact` task.
2. Replace the `has_intel_gpu` line with the fixed version above.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[detect] Set environment facts`. Locate the `has_intel_gpu:` key. Replace its value with:
```
"{{ ('INTEL' in lspci_output.stdout | upper) and (('VGA' in lspci_output.stdout | upper) or ('DISPLAY' in lspci_output.stdout | upper)) }}"
```

---

### BUG-4 · `changed_when: true` on VS Code signing key always reports changed

**File:** `devplatform.yml`  
**Line:** 708  
**Fixable by:** AI agent  
**Status:** Fixed, need review, testing

**Problem:**  
`changed_when: true` forces the task to report as *changed* on every single playbook run — including fully idempotent re-runs where nothing actually happened. This pollutes `--diff` output, breaks at-a-glance verification of clean re-runs, and would cause unnecessary handler triggers if any handler were ever notified by this task. The operation (`gpg --dearmor`) is deterministic: the same input always produces the same output.

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
  # Reason: gpg --dearmor is deterministic — same input key always produces
  # the same output. The preceding [VSCODE] Remove existing keys tasks ensure
  # a clean state before this runs. Reporting changed here adds no information
  # and creates noise on re-runs.
```

**Human instructions:**  
Open `devplatform.yml`, find the `[VSCODE] Install Microsoft signing key` task, and change `changed_when: true` to `changed_when: false`.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[VSCODE] Install Microsoft signing key`. Change the value of `changed_when:` from `true` to `false`.

---

### BUG-5 · PATH addition targets `~/.profile` but default login shell is zsh

**File:** `devplatform.yml`  
**Lines:** 929–940  
**Fixable by:** AI agent  
**Status:** Fixed, need review, testing

**Problem:**  
`~/.local/bin` is written to `~/.profile`. Zsh — the login shell being configured by this very playbook — reads `~/.zprofile` on login, not `~/.profile`. `~/.profile` is sourced by bash and sh login shells only. On a bare TTY login, SSH session, sddm session start, or any non-interactive login with zsh, `~/.local/bin` will not be in PATH. This causes `pipx`-installed tools (`ansible-lint`, `pre-commit`, `cookiecutter`) and `uv` to produce `command not found` errors in those contexts. The `~/.zshrc` addition already covers interactive zsh sessions, so this only affects login shells.

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
  # ~/.zprofile covers: bare TTY login, SSH, sddm session startup.

- name: "[PYTHON] Ensure ~/.local/bin is on PATH in .profile (bash fallback)"
  ansible.builtin.lineinfile:
    path: "{{ real_home }}/.profile"
    line: 'export PATH="$HOME/.local/bin:$PATH"'
    state: present
    create: true
    mode: "0644"
  become: true
  become_user: "{{ real_user }}"
  # Reason: .profile covers bash/sh login shells. Kept as a belt-and-suspenders
  # fallback for environments where zsh is not the login shell.
```

**Human instructions:**  
1. Open `devplatform.yml` and find the task `[PYTHON] Ensure ~/.local/bin is on PATH in .profile`.
2. Change the task `name:` to `[PYTHON] Ensure ~/.local/bin is on PATH in .zprofile`.
3. Change `path: "{{ real_home }}/.profile"` to `path: "{{ real_home }}/.zprofile"`.
4. Duplicate the task below it with the original `.profile` path and name it the `(bash fallback)` variant.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[PYTHON] Ensure ~/.local/bin is on PATH in .profile`. Change its `name:` to `[PYTHON] Ensure ~/.local/bin is on PATH in .zprofile` and its `path:` value to `"{{ real_home }}/.zprofile"`. Then insert a second, identical task immediately after it with `name: "[PYTHON] Ensure ~/.local/bin is on PATH in .profile (bash fallback)"` and `path: "{{ real_home }}/.profile"`.

---

## Pitfalls and Hidden Failures

> These will not fail outright on a clean first run but will cause unexpected, hard-to-debug behavior in specific scenarios or on re-runs.

---

### PITFALL-1 · `alias grep='rg'` and `alias find='fd'` override POSIX tool semantics

**File:** `devplatform.yml`  
**Line:** 1375–1380 (inside the aliases blockinfile task)  
**Fixable by:** Human  
**Status:** Open

**Problem:**  
`rg` and `fd` do not implement all flags of `grep` and `find`. Interactive commands copied directly from documentation or manpages will silently fail or error in a hard-to-diagnose way:

- `grep -P "pattern" file` — `rg` uses `--pcre2` not `-P` → error
- `grep -c "pattern" file` — `rg -c` counts per-file matches, not total lines → wrong output
- `find . -type f -exec cmd {} \;` — `fd` does not support `-exec ... \;` → error
- `find . -name "*.txt" -delete` — `fd` syntax is `fd -e txt --exec-batch rm` → error

Aliases apply only to interactive shells (not scripts), limiting the blast radius. But developers routinely paste commands from documentation into the terminal, making this a practical daily friction source on a teaching platform.

**Fix — remove the overriding aliases, keep the tools available under their own names:**
```bash
# REMOVE these two lines from the aliases block:
#   alias grep='rg'
#   alias find='fd'

# KEEP — these do not override standard names:
alias cat='bat --paging=never'
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias tree='eza --tree --icons'

# OPTIONAL — add safe enhancements that do not shadow standard names:
alias rg='rg --smart-case'
alias fd='fd --hidden'
```

**Human instructions:**  
1. Open `devplatform.yml` and find the task named `[SHELL] Add shell aliases for modern CLI tools`.
2. In the `block:` content, delete the two lines:
   ```
             alias grep='rg'                     # ripgrep as default grep
             alias find='fd'                     # fd as default find
   ```
3. Optionally replace them with non-overriding aliases such as `alias rg='rg --smart-case'`.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[SHELL] Add shell aliases for modern CLI tools`. Within the `block:` scalar, remove the lines `alias grep='rg'` and `alias find='fd'` (along with their inline comments). Do not remove any other alias lines.

---

### PITFALL-2 · Full system upgrade and cleanup run before third-party repos are added

**File:** `devplatform.yml`  
**Lines:** 126–139  
**Fixable by:** AI agent or human  
**Status:** Open

**Problem:**  
Three tasks labeled `[FINAL]` (`Full system upgrade`, `Remove orphaned packages`, `Clean apt package cache`) appear at lines 126–139 — immediately after `sources.list` is written, but long before Docker, GitHub CLI, Brave, and VS Code repositories are added. On a first run this is harmless, but the `[FINAL]` label strongly implies these tasks belong at the end. On a re-run the upgrade runs against all previously configured repos (correct behavior), but any resolver conflicts introduced by the third-party repos will not be caught until those repos are re-added later in the same run. The misleading label also causes confusion when reading playbook output or task lists — there appear to be two "final" stages.

**Fix — rename the early tasks and move the upgrade block:**
```yaml
# Move these three tasks to immediately AFTER:
#   "[APT] Refresh package cache after sources.list update"
# and BEFORE:
#   "[detect] Query PCI devices"
# Rename [FINAL] → [APT] to match the section they belong in.

- name: "[APT] Full system upgrade"
  ansible.builtin.apt:
    upgrade: dist           # 'dist' is safer — see IDEM-4
    update_cache: false     # cache was just refreshed by the preceding task

- name: "[APT] Remove orphaned packages"
  ansible.builtin.apt:
    autoremove: true
    purge: true

- name: "[APT] Clean apt package cache"
  ansible.builtin.apt:
    autoclean: true
```

**Human instructions:**  
1. Open `devplatform.yml` and cut the three tasks at lines 126–139 (`[FINAL] Full system upgrade`, `[FINAL] Remove orphaned packages`, `[FINAL] Clean apt package cache`).
2. Paste them immediately after the `[APT] Refresh package cache after sources.list update` task.
3. Rename all three from `[FINAL]` to `[APT]` prefixes.
4. The actual final cleanup tasks at the end of the file (temp file removal, post-install summary) are correct and should stay where they are.

**AI agent instructions:**  
In `devplatform.yml`, locate the three tasks named `[FINAL] Full system upgrade`, `[FINAL] Remove orphaned packages`, and `[FINAL] Clean apt package cache` (around lines 126–139). Cut all three. Paste them immediately after the task named `[APT] Refresh package cache after sources.list update`. Rename each task's `name:` prefix from `[FINAL]` to `[APT]`.

---

### PITFALL-3 · `ignore_errors: true` on Intel GPU task silently swallows real failures

**File:** `devplatform.yml`  
**Line:** 369  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
`ignore_errors: true` suppresses all errors from this task, not only the removed-package errors it was intended to handle. The comment correctly notes that `xserver-xorg-video-intel` and `i965-va-driver` were removed from Debian 13 — but those packages are already excluded from the package list. The remaining packages (`intel-media-va-driver`, `libgl1-mesa-dri`, `mesa-vulkan-drivers`) are all present in Debian 13 trixie. `ignore_errors: true` therefore serves no purpose and silently masks genuine errors: network failures, broken package dependencies, APT lock timeouts, or repository misconfiguration.

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
```yaml
- name: "[gpu/intel] Install Intel GPU drivers and VA-API acceleration"
  ansible.builtin.apt:
    name:
      - intel-media-va-driver    # VA-API hardware video decode
      - libgl1-mesa-dri          # Mesa DRI driver (iris for modern Intel)
      - mesa-vulkan-drivers      # Vulkan support via ANV driver
    state: present
  when: has_intel_gpu and is_bare_metal
  # Note: xserver-xorg-video-intel and i965-va-driver were removed from
  # Debian 13 and are intentionally not listed here. All listed packages
  # are available in trixie; ignore_errors is not needed.
```

**Human instructions:**  
1. Open `devplatform.yml` and find the task named `[gpu/intel] Install Intel GPU drivers and VA-API acceleration`.
2. Remove the `ignore_errors: true` line.
3. Verify the package list does not contain `xserver-xorg-video-intel` or `i965-va-driver`.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[gpu/intel] Install Intel GPU drivers and VA-API acceleration`. Remove the `ignore_errors: true` line entirely. Do not change any other part of the task.

---

### PITFALL-4 · `kubectl` binary is downloaded to the current working directory, not `/tmp`

**File:** `devplatform.yml`  
**Line:** 1162–1167  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
The install command uses `curl -sLO`, which downloads `kubectl` to the Ansible process's current working directory (typically `/root` when running as root). If the task fails mid-run due to a network drop or interrupted install, a partially-downloaded or zero-byte `kubectl` is left in `/root`. The subsequent `rm -f kubectl` cleanup only runs if the entire shell block succeeds. On a re-run, `_kubectl_stat.stat.exists` will be False (the binary was never installed to `/usr/local/bin`), but a stale partial file in `/root` may cause confusing errors.

**Current code:**
```yaml
- name: "[KUBECTL] Install kubectl — official binary"
  ansible.builtin.shell:
    cmd: |
      set -euo pipefail
      VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
      curl -sLO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
      install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      rm -f kubectl
    executable: /bin/bash
  when: not _kubectl_stat.stat.exists
```

**Fixed code:**
```yaml
- name: "[KUBECTL] Install kubectl — official binary"
  ansible.builtin.shell:
    cmd: |
      set -euo pipefail
      VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
      curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
      install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
      rm -f /tmp/kubectl
    executable: /bin/bash
  when: not _kubectl_stat.stat.exists
  # Reason: explicit /tmp path prevents stale partials in /root and is
  # consistent with how all other binaries in this playbook use /tmp.
```

**Human instructions:**  
Open `devplatform.yml`, find the `[KUBECTL] Install kubectl — official binary` task. Change `curl -sLO` to `curl -sLo /tmp/kubectl`. Change `install -o root -g root -m 0755 kubectl` to `install -o root -g root -m 0755 /tmp/kubectl`. Change `rm -f kubectl` to `rm -f /tmp/kubectl`.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[KUBECTL] Install kubectl — official binary`. In its `cmd:` block, make three substitutions: (1) replace `curl -sLO "https://dl.k8s.io/...kubectl"` with `curl -sLo /tmp/kubectl "https://dl.k8s.io/...kubectl"`, (2) replace `install -o root -g root -m 0755 kubectl` with `install -o root -g root -m 0755 /tmp/kubectl`, (3) replace `rm -f kubectl` with `rm -f /tmp/kubectl`.

---

### PITFALL-5 · `read -rp` in user-detection fallback has no timeout — hangs non-interactive runs

**File:** `devplatformbootstrap.sh`  
**Line:** 184  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
When `detect_real_user` returns empty (e.g., the script was run directly as root with no `SUDO_USER`, `logname`, or `PKEXEC_UID`), the script falls through to an interactive `read -rp` prompt with no timeout. If the script is invoked from a CI pipeline, an automation tool, a `cron` job, a `tmux` session with no TTY, or piped from another process, the script hangs indefinitely and silently, consuming a process slot with no indication of what is wrong.

**Current code:**
```bash
read -rp "  Enter the username to configure the desktop for: " REAL_USER
```

**Fixed code:**
```bash
if ! read -r -t 60 -p "  Enter the username to configure the desktop for: " REAL_USER; then
    echo ""
    die "Timed out waiting for username input (60s).\n" \
        "  If running non-interactively, set SUDO_USER or run via sudo:\n" \
        "    SUDO_USER=yourusername sudo bash $0"
fi
```

**Human instructions:**  
Open `devplatformbootstrap.sh` and find the `read -rp` line (line 184). Replace it with the `read -r -t 60` version above that adds a 60-second timeout and an informative error message.

**AI agent instructions:**  
In `devplatformbootstrap.sh`, find the line `read -rp "  Enter the username to configure the desktop for: " REAL_USER`. Replace it with:
```bash
if ! read -r -t 60 -p "  Enter the username to configure the desktop for: " REAL_USER; then
    echo ""
    die "Timed out waiting for username input (60s).\n" \
        "  If running non-interactively, set SUDO_USER or run via sudo:\n" \
        "    SUDO_USER=yourusername sudo bash $0"
fi
```

---

## Security Issues

> Fix these before making the repository public or running on any machine that is not fully trusted and isolated.

---

### SEC-1 · No integrity check on the downloaded playbook in the bootstrap script

**File:** `devplatformbootstrap.sh`  
**Lines:** 271–299  
**Fixable by:** Human (requires publishing a checksum file) + AI agent (script changes)  
**Status:** Open

**Problem:**  
The bootstrap script downloads the playbook from GitHub over HTTPS and immediately executes it as root. The only validation is `grep -q "^- name:"` — which any file containing that string would pass. A compromised GitHub repository, a CDN-level network injection on an untrusted network, or a DNS hijack would result in arbitrary code execution as root with no warning to the user.

**Fix — Step 1 (human): publish a checksum file in the repository after every change:**
```bash
# Run this locally after editing devplatform.yml:
sha256sum devplatform.yml > devplatform.yml.sha256
git add devplatform.yml devplatform.yml.sha256
git commit -m "chore: update playbook and checksum"
git push
```

**Fix — Step 2 (AI agent or human): replace the weak grep check in `devplatformbootstrap.sh`:**
```bash
CHECKSUM_FILENAME="${PLAYBOOK_FILENAME}.sha256"
CHECKSUM_URL="${GITHUB_RAW_BASE}/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${CHECKSUM_FILENAME}"
CHECKSUM_DEST="/tmp/${CHECKSUM_FILENAME}"

section "Verifying Playbook Integrity"

info "Downloading checksum: ${CHECKSUM_URL}"
if ! curl -fsSL --retry 3 -o "${CHECKSUM_DEST}" "${CHECKSUM_URL}"; then
    die "Failed to download checksum file.\n  URL: ${CHECKSUM_URL}"
fi

if ! (cd /tmp && sha256sum -c "${CHECKSUM_FILENAME}" --status); then
    die "Playbook checksum verification FAILED.\n" \
        "  The downloaded file does not match the published checksum.\n" \
        "  Do NOT proceed. Check network integrity and repository status."
fi

success "Playbook integrity verified."
```

**Human instructions:**  
1. After every edit to `devplatform.yml`, run `sha256sum devplatform.yml > devplatform.yml.sha256` and commit both files to the repository.
2. In `devplatformbootstrap.sh`, replace the `grep -q "^- name:"` block (lines ~293–299) with the checksum verification block above. Add the three `CHECKSUM_*` variable declarations near the top of the URL configuration section.

**AI agent instructions:**  
In `devplatformbootstrap.sh`: (1) In the URL configuration block near the top, add three new variables: `CHECKSUM_FILENAME`, `CHECKSUM_URL`, and `CHECKSUM_DEST` as shown above. (2) Find the block starting with `# Guard: downloaded file must look like an Ansible playbook.` and ending with the `die` call on the `grep` failure. Replace the entire guard block (the `if ! grep -q ...` through its closing `fi`) with the checksum download and `sha256sum -c` verification block shown above.

---

### SEC-2 · openssh-server is installed but never hardened

**File:** `devplatform.yml`  
**Line:** 1040  
**Fixable by:** AI agent or human  
**Status:** Open

**Problem:**  
`openssh-server` is installed in the DevOps utilities block. Debian's default `sshd` configuration ships with `PasswordAuthentication yes` and `PermitRootLogin prohibit-password`. On a developer workstation connected to any non-isolated network, this accepts SSH password authentication from any host. The `[SSH] Write sshd hardening config` task does exist (see BUG-1) but its `notify` is broken and no handler fires, so the hardening config is written but never applied until reboot. If a user does not reboot promptly after bootstrapping, the window of exposure can be significant.

**Fix — add a `handlers:` block and correct the existing task (see BUG-1 for the full handler fix), then extend the hardening config:**
```yaml
- name: "[SSH] Write sshd hardening config"
  ansible.builtin.copy:
    dest: /etc/ssh/sshd_config.d/devplatform.conf
    owner: root
    group: root
    mode: "0600"            # 0644 is also acceptable; 0600 is tighter
    content: |
      # Managed by devplatform.yml — do not edit manually
      PermitRootLogin no
      PasswordAuthentication no
      X11Forwarding no
      MaxAuthTries 3
      LoginGraceTime 30
  notify: Restart ssh
```

> **Warning:** Setting `PasswordAuthentication no` will lock you out of SSH unless your user has a public key in `~/.ssh/authorized_keys`. If this is a desktop machine accessed only locally, keep `PasswordAuthentication yes` and restrict SSH to localhost or a trusted subnet instead.

**Human instructions:**  
1. Fix BUG-1 first (add the `handlers:` block and correct the `notify` indentation).
2. Review whether `PasswordAuthentication no` is safe for your environment. If the machine is only accessed locally, consider `ListenAddress 127.0.0.1` instead.
3. Ensure the real user has an SSH public key set up before running the playbook on a remote machine.

**AI agent instructions:**  
After applying the BUG-1 fix, in `devplatform.yml` find the task named `[SSH] Write sshd hardening config`. Update the `mode:` to `"0600"`. Add `MaxAuthTries 3` and `LoginGraceTime 30` to the `content:` block. Ensure `notify: Restart ssh` is at task level (6-space indent), not inside the module parameters.

---

### SEC-3 · Multiple binary tools installed without checksum verification

**File:** `devplatform.yml`  
**Lines:** 548–558 (lazygit), 990–1000 (uv), 1080–1088 (yq), 1160–1169 (kubectl), 1245–1259 (k9s), 1278–1286 (cosign)  
**Fixable by:** AI agent (repeatable pattern) + human (for shell-based installs)  
**Status:** Open

**Problem:**  
The following tools are downloaded and installed as root without checksum or signature verification: `lazygit`, `uv`, `yq`, `kubectl`, `k9s`, and `cosign`. The Helm section already does this correctly and serves as the reference pattern. `cosign` — a tool specifically designed for container signing and supply-chain verification — being installed without verification is particularly contradictory.

**Reference — correct Helm pattern to replicate:**
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

**Fix for cosign and yq — use `get_url`'s built-in `checksum:` parameter:**
```yaml
# cosign — sigstore publishes a .sha256 file alongside the binary:
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

# yq — mikefarah publishes checksums alongside each release:
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

**Fix for kubectl — official SHA256 file available:**
```yaml
- name: "[KUBECTL] Install kubectl — official binary"
  ansible.builtin.shell:
    cmd: |
      set -euo pipefail
      VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
      curl -sLo /tmp/kubectl     "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
      curl -sLo /tmp/kubectl.sha256 "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl.sha256"
      echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum -c -
      install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
      rm -f /tmp/kubectl /tmp/kubectl.sha256
    executable: /bin/bash
  when: not _kubectl_stat.stat.exists
```

**Human instructions:**  
1. For `cosign` and `yq`: add the `checksum:` parameter shown above to their `get_url` tasks.
2. For `kubectl`: replace the current shell block with the version above that downloads and verifies the `.sha256` file.
3. For `lazygit` and `k9s` (no predictable checksum URL): pin these to a specific version (add `lazygit_version` and `k9s_version` vars) and download the corresponding checksum files from their GitHub releases pages.
4. For `uv`: the official installer at `astral.sh/uv/install.sh` supports `UV_VERSION` env variable; pin it and cross-check the published SHA when pinning.

**AI agent instructions:**  
In `devplatform.yml`, for each binary tool listed in this issue: (1) `cosign` — add `checksum: "sha256:https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64.sha256"` to the existing `get_url` task. (2) `yq` — add `checksum: "sha256:https://github.com/mikefarah/yq/releases/latest/download/checksums"` to the existing `get_url` task. (3) `kubectl` — replace the existing shell block with the verified version shown above. For `lazygit` and `k9s`, add pinned version variables to the `vars:` block and note that a human must supply the checksum URL pattern from the upstream release page.

---

### SEC-4 · nvm and uv are installed via unpinned `curl | bash`

**File:** `devplatform.yml`  
**Lines:** 864–876 (nvm), 990–1000 (uv)  
**Fixable by:** Human  
**Status:** Open

**Problem:**  
Both nvm and uv are installed using `curl <url> | bash` (or `| sh`). While HTTPS provides transport security, neither install script is pinned to a specific version or verified against a known hash. If either project's CDN or GitHub account were compromised, a malicious installer would run as the real user with no warning. The `nvm_version` variable pins the NVM source URL correctly, but the install script itself at that URL is not hash-verified. For `uv`, neither version nor script hash is pinned.

**Fix for nvm — download, verify, then execute:**
```yaml
- name: "[NVM] Download nvm install script"
  ansible.builtin.get_url:
    url: "https://raw.githubusercontent.com/nvm-sh/nvm/{{ nvm_version }}/install.sh"
    dest: /tmp/nvm-install.sh
    mode: "0700"
    checksum: "sha256:{{ nvm_install_sha256 }}"   # add to vars block
  when: not _nvm_stat.stat.exists

- name: "[NVM] Run nvm install script"
  ansible.builtin.shell:
    cmd: /tmp/nvm-install.sh
    executable: /bin/bash
  become: true
  become_user: "{{ real_user }}"
  environment:
    HOME: "{{ real_home }}"
    NVM_DIR: "{{ real_home }}/.nvm"
  when: not _nvm_stat.stat.exists
```

**Add to `vars:` block:**
```yaml
# SHA256 of nvm v0.40.1 install.sh — update this when bumping nvm_version
# Generate with: curl -sL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | sha256sum
nvm_install_sha256: "<compute and fill in>"
```

**Human instructions:**  
1. For `nvm`: compute the SHA256 of the install script for the pinned `nvm_version` (`curl -sL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | sha256sum`). Add it to the `vars:` block as `nvm_install_sha256`. Split the nvm install into download + verify + execute as shown above.
2. For `uv`: add a `uv_version` variable to the `vars:` block. Use the official versioned installer URL (`https://astral.sh/uv/${uv_version}/install.sh`) and compute its SHA256, adding `checksum:` to a `get_url` task instead of piping from curl.
3. Update both `nvm_install_sha256` and `uv_version` whenever you bump the corresponding version variable.

**AI agent instructions:**  
In `devplatform.yml`, add `uv_version` and `nvm_install_sha256` to the `vars:` block with placeholder values and a comment instructing the user to compute them. Split the NVM install task from a single `cmd: curl ... | bash` into two tasks: a `get_url` download with `checksum:` parameter, followed by a `shell` execution of the downloaded script. Apply the same split pattern to the uv install task, using `https://astral.sh/uv/{{ uv_version }}/install.sh` as the URL.

---

## Idempotency Issues

> These do not fail but cause playbook re-runs to behave incorrectly — either always reporting changed when nothing changed, or never reporting changed when something did.

---

### IDEM-1 · `changed_when: false` on Flatpak remote-add always reports unchanged

**File:** `devplatform.yml`  
**Lines:** 618–622  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
`changed_when: false` causes the task to always report as `ok` (unchanged) — even the very first time it genuinely adds the Flathub remote. This makes it impossible to tell from playbook output whether Flathub was already registered or just added. The `--if-not-exists` flag handles Flatpak-level idempotency correctly but the Ansible-level change reporting is wrong.

**Current code:**
```yaml
- name: "[FLATPAK] Add Flathub remote"
  ansible.builtin.command:
    cmd: flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  changed_when: false
```

**Fixed code:**
```yaml
- name: "[FLATPAK] Check if Flathub remote is registered"
  ansible.builtin.command:
    cmd: flatpak remote-list
  register: _flatpak_remotes
  changed_when: false

- name: "[FLATPAK] Add Flathub remote"
  ansible.builtin.command:
    cmd: flatpak remote-add flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  when: "'flathub' not in _flatpak_remotes.stdout"
  # Reason: splitting the check and the add gives accurate changed reporting.
  # The task only runs — and only reports changed — when Flathub is genuinely absent.
```

**Human instructions:**  
1. Open `devplatform.yml` and find the `[FLATPAK] Add Flathub remote` task.
2. Insert a new `flatpak remote-list` check task before it, registered as `_flatpak_remotes`.
3. Replace `changed_when: false` on the add task with `when: "'flathub' not in _flatpak_remotes.stdout"`.
4. Remove `--if-not-exists` from the add command since the `when` guard now handles this.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[FLATPAK] Add Flathub remote`. Replace it with two tasks: first, a `ansible.builtin.command` task running `flatpak remote-list` with `register: _flatpak_remotes` and `changed_when: false`. Second, the original add task with `--if-not-exists` removed and `when: "'flathub' not in _flatpak_remotes.stdout"` added in place of `changed_when: false`.

---

### IDEM-2 · Global npm packages re-run every playbook invocation

**File:** `devplatform.yml`  
**Lines:** 897–909  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
`npm install -g pnpm yarn typescript ts-node nodemon http-server` runs unconditionally on every playbook invocation. `changed_when: false` suppresses the change report, making it look like nothing happened — while the task silently re-downloads and re-installs all packages (20–40 seconds on a slow connection). On the first run the task reports `ok` even though it genuinely installed packages. On re-runs it also reports `ok` while unnecessarily re-running npm.

**Current code:**
```yaml
- name: "[NVM] Install global npm packages"
  ansible.builtin.shell: |
    export NVM_DIR="{{ real_home }}/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    npm install -g pnpm yarn typescript ts-node nodemon http-server
  args:
    executable: /bin/bash
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

**Human instructions:**  
Open `devplatform.yml` and find the `[NVM] Install global npm packages` task. Replace the `cmd:` block and `changed_when: false` with the fixed version above, which checks each package with `npm list -g` before installing and echoes `1` only when something new was installed.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[NVM] Install global npm packages`. Replace the entire `cmd:` shell block content with the `_changed` / `_install_if_missing` version shown above. Replace `changed_when: false` with `register: _npm_global` and `changed_when: _npm_global.stdout | trim == '1'`. Preserve all existing `become:`, `become_user:`, and `environment:` keys.

---

### IDEM-3 · `ansible.builtin.shell` used for a command that needs no shell

**File:** `devplatform.yml`  
**Line:** 148  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
`lspci -nn` uses no shell features (no pipes, no redirects, no globs, no variable expansion). Using `ansible.builtin.shell` triggers the `command-instead-of-shell` ansible-lint rule and is a code smell. `ansible.builtin.command` does not invoke a shell, making it slightly safer (no shell injection risk) and more explicit.

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

**Human instructions:**  
Open `devplatform.yml`, find the `[detect] Query PCI devices` task, and change `ansible.builtin.shell:` to `ansible.builtin.command:`.

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[detect] Query PCI devices`. Change `ansible.builtin.shell:` to `ansible.builtin.command:`. No other changes.

---

### IDEM-4 · `upgrade: full` is more aggressive than needed for re-runs

**File:** `devplatform.yml`  
**Line:** 128  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**  
`upgrade: full` maps to `apt full-upgrade`, which can automatically **remove** installed packages when required to resolve dependency conflicts. On a clean first run this is equivalent to `dist-upgrade`. On a re-run of a partially-bootstrapped system — for example, if the first run installed Docker CE then failed — `full-upgrade` could remove packages to satisfy a conflict that `dist` would resolve differently. `upgrade: dist` is equivalent on a clean system but uses a more conservative conflict resolution strategy on already-configured systems.

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
    update_cache: false   # cache refreshed by the preceding [APT] task; set true if moved
  # Reason: 'dist' maps to apt-get dist-upgrade. Equivalent to 'full' on a
  # clean system, but less aggressive on conflict resolution during re-runs.
```

**Human instructions:**  
Open `devplatform.yml`, find the task at line 126 named `[FINAL] Full system upgrade`. Change `upgrade: full` to `upgrade: dist`. Also change `update_cache: true` to `update_cache: false` (the preceding `[APT] Refresh package cache` task already refreshed it).

**AI agent instructions:**  
In `devplatform.yml`, find the task named `[FINAL] Full system upgrade`. Change `upgrade: full` to `upgrade: dist`. Change `update_cache: true` to `update_cache: false`.

---

## Design Choices Worth Documenting

> These are not bugs or failures, but they create maintenance friction, user confusion, or unexpected behavior that should either be fixed or explicitly documented.

---

### DESIGN-1 · No upgrade path for stat-guarded binaries — not documented

**File:** `devplatform.yml`  
**Lines:** 859–876 (nvm), 985–1000 (uv), 1075–1088 (yq), 1155–1169 (kubectl), 1240–1259 (k9s), 1273–1286 (cosign)  
**Fixable by:** Human + AI agent  
**Status:** Open — document or implement

**Problem:**  
All binary tools that use a `stat` guard (`uv`, `yq`, `kubectl`, `k9s`, `cosign`, `lazygit`, Cursor IDE, JetBrainsMono Nerd Font, nvm) can only be upgraded by manually deleting the binary/sentinel and re-running the playbook. Individual inline comments mention this, but there is no consolidated reference. On a teaching platform where students will need to update tools over weeks or months, this creates repeated questions and confusion.

**Option A (recommended) — add a `force_reinstall` variable:**
```yaml
# In vars: block
# Set to true to force re-download of all stat-guarded binaries.
# Usage: ansible-playbook devplatform.yml -e "force_reinstall=true"
force_reinstall: false
```

Then add to every stat-guarded task:
```yaml
when: not _kubectl_stat.stat.exists or (force_reinstall | bool)
```

**Option B — document in README.md:**
```markdown
## Upgrading individual tools

Binary tools managed by a `stat` guard are only installed once. To upgrade,
delete the listed file and re-run `bash bootstrap.sh`.

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
| Node.js via nvm | `nvm install --lts && nvm alias default node` (no re-run needed) |
```

**Human instructions:**  
Choose Option A, Option B, or both. For Option A, add `force_reinstall: false` to the `vars:` block in `devplatform.yml` and update each stat-guarded `when:` condition. For Option B, add the upgrade table to `README.md`.

**AI agent instructions:**  
In `devplatform.yml`, add `force_reinstall: false` with its comment to the `vars:` block. Then, for each of the following tasks, append `or (force_reinstall | bool)` to their `when:` condition: `[NVM] Install nvm`, `[PYTHON] Install uv`, `[YQ] Install yq Go binary`, `[KUBECTL] Install kubectl`, `[K9S] Download k9s tarball`, `[K9S] Extract k9s binary`, `[COSIGN] Install cosign binary`, `[GIT] Install lazygit`, `[cursor] Download Cursor Debian package`, and `[fonts] Install JetBrainsMono Nerd Font`.

---

### DESIGN-2 · ANSI color codes emitted unconditionally — garbled in log files

**File:** `devplatformbootstrap.sh`  
**Lines:** 41–58  
**Fixable by:** AI agent  
**Status:** Open — document or fix

**Problem:**  
The script emits `\033[...m` ANSI escape sequences unconditionally. When the script output is captured to a log file (`bash bootstrap.sh | tee install.log`), piped through `grep`, or run in a CI environment that does not support colors, the log contains raw escape sequences that make it unreadable. The standard pattern is to check whether stdout is connected to a TTY before setting color codes.

**Current code:**
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'
```

**Fixed code:**
```bash
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi
```

**Human instructions:**  
Open `devplatformbootstrap.sh`. Replace the six standalone color variable assignments (lines 41–46) with the `if [[ -t 1 ]]; then ... else ... fi` block shown above.

**AI agent instructions:**  
In `devplatformbootstrap.sh`, find the block of six lines that assign `RED`, `GREEN`, `YELLOW`, `CYAN`, `BOLD`, and `RESET` using ANSI escape codes. Replace the entire block with the `[[ -t 1 ]]` conditional shown above that sets them to empty strings when stdout is not a TTY.

---

### DESIGN-3 · `[FINAL]` prefix used on tasks that run near the beginning of the playbook

**File:** `devplatform.yml`  
**Lines:** 126–139  
**Fixable by:** AI agent  
**Status:** Open — rename after applying PITFALL-2 fix

**Problem:**  
Three tasks labeled `[FINAL]` appear at lines 126–139, less than 30 lines into the `tasks:` section and before most of the playbook's work. A second set of `[FINAL]`-labeled tasks correctly appears at the actual end of the file (temp file cleanup and post-install summary). The early `[FINAL]` labels cause confusion when reading task names in playbook output, in `--list-tasks` output, or when searching the file. The intended meaning of `[FINAL]` is "end-of-run cleanup", and these three tasks clearly belong under the `[APT]` section prefix.

**Fix — rename to match their actual section:**
```yaml
# Before:
- name: "[FINAL] Full system upgrade"
- name: "[FINAL] Remove orphaned packages"
- name: "[FINAL] Clean apt package cache"

# After:
- name: "[APT] System upgrade"
- name: "[APT] Remove orphaned packages"
- name: "[APT] Clean apt package cache"
```

**Human instructions:**  
Open `devplatform.yml`. Find the three tasks at lines 126–139 named `[FINAL] Full system upgrade`, `[FINAL] Remove orphaned packages`, and `[FINAL] Clean apt package cache`. Rename them to `[APT] System upgrade`, `[APT] Remove orphaned packages`, and `[APT] Clean apt package cache`. Apply this rename after moving them to the correct position (see PITFALL-2).

**AI agent instructions:**  
In `devplatform.yml`, find the tasks named `[FINAL] Full system upgrade`, `[FINAL] Remove orphaned packages`, and `[FINAL] Clean apt package cache` located before the `[detect]` section. Rename them to `[APT] System upgrade`, `[APT] Remove orphaned packages`, and `[APT] Clean apt package cache` respectively. Do not rename the `[FINAL]` tasks at the end of the file (temp file cleanup, post-install summary).

---

## What Is Done Well

These patterns are correct, idiomatic, and should be preserved as reference implementations within the project.

| Pattern | Location | Why it is correct |
|---|---|---|
| Fully-qualified `ansible.builtin.*` module names | Throughout | No ambiguity with community collections; ansible-lint compliant |
| `getent passwd` for home directory resolution | `pre_tasks` | Handles non-standard home paths (`/data/users/x`, `/srv/home/x`) authoritatively |
| `append: true` on all `ansible.builtin.user` group tasks | KVM, Docker | Prevents accidental removal of the user from all other groups |
| Helm SHA256 checksum verification | HELM section | The exact pattern all other binary installs should follow |
| `become_user: real_user` for nvm, pipx, and uv tasks | NVM, Python | Correctly scopes per-user tools without polluting root's environment |
| VirtualBox ISO detection with graceful fallback and re-run path | VirtualBox section | Warns clearly; re-running after ISO insertion completes the step |
| `debconf` task for SDDM default display manager | KDE section | Correct, robust way to resolve display manager priority on Debian |
| Docker GPG key stored in `/etc/apt/keyrings/` | DOCKER section | Uses the Debian 12+ standard location for signed-by keys |
| `set -euo pipefail` in all inline shell tasks | Throughout | Prevents silent partial failures; task fails fast on first error |
| Self-escalation via `exec sudo` with `SUDO_USER` preservation | `bootstrap.sh` | Correctly propagates original caller identity into the Ansible environment |
| `getent passwd` + `id` user validation before doing any work | `bootstrap.sh` | Fails fast with a clear error before any system state is modified |
| kubectl installed via official binary, bypassing broken pkgs.k8s.io GPG v3 | KUBECTL section | Documents and correctly routes around a real, confirmed Debian 13 incompatibility |
| Multi-method user detection (`SUDO_USER → logname → PKEXEC_UID → prompt`) | `bootstrap.sh` | Covers all realistic invocation paths for a bootstrap script |

---

*Generated by code review · `devplatform.yml` + `devplatformbootstrap.sh` · Debian 13 trixie · April 2026*

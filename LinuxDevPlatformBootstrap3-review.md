# LinuxDevPlatformBootstrap3 Code Review Report

## Header block

**Files reviewed:** `devplatform.yml`, `devplatformbootstrap.sh`  
**Repository URL:** `https://github.com/Korplin/LinuxDevPlatformBootstrap3`  
**Target OS/runtime:** Debian 13 “trixie” amd64; Bash bootstrap; local Ansible playbook execution  
**One-line verdict:** Strong developer-workstation bootstrap draft, but not production grade until root-level supply-chain validation, first-run failures, SSH safety, and idempotency gaps are fixed.

---

## Table of Contents

- [Header block](#header-block)
- [Table of Contents](#table-of-contents)
- [Summary table](#summary-table)
- [Bugs](#bugs)
- [Pitfalls and Hidden Failures](#pitfalls-and-hidden-failures)
- [Security Issues](#security-issues)
- [Idempotency Issues](#idempotency-issues)
- [Design Choices Worth Documenting](#design-choices-worth-documenting)
- [What Is Done Well](#what-is-done-well)

---

## Summary table

| Category | Count | Priority |
|---|---|---|
| 🐛 Bugs | 3 | Fix before first use |
| ⚠️ Pitfalls | 4 | Fix before first real use |
| 🔒 Security | 4 | Fix before making repo public |
| 🔁 Idempotency | 3 | Fix for reliable re-runs |
| 📝 Design | 3 | Document or implement |

---

## Bugs

### BUG-1 · Hardware detection can fail because `lspci` is used before `pciutils` is installed

**File:** `devplatform.yml`  
**Line:** 168–172  
**Fixable by:** AI agent  
**Status:** Open -> Fixed

**Problem:**
The task `[detect] Query PCI devices` runs `lspci -nn`, but the playbook does not install `pciutils` before this point. On a minimal Debian 13 install, `lspci` may be missing, causing the playbook to fail before GPU and virtualization-dependent configuration can continue.

This is a normal first-run failure on lean netinstall systems, not only an edge case. Because this task happens early, the rest of the workstation provisioning never runs.

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
    - name: "[PRE] Install hardware detection prerequisites"
      ansible.builtin.apt:
        name:
          - pciutils
        state: present
        update_cache: true

    - name: "[detect] Query PCI devices"
      ansible.builtin.command:
        cmd: lspci -nn
      register: lspci_output
      changed_when: false
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[detect] Query PCI devices`.
3. Add a new task immediately before it named `[PRE] Install hardware detection prerequisites`.
4. Set that new task to install the `pciutils` package with `ansible.builtin.apt`.
5. Replace `ansible.builtin.shell` with `ansible.builtin.command` in the `[detect] Query PCI devices` task.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[detect] Query PCI devices"`.
2. Insert the fixed `[PRE] Install hardware detection prerequisites` task shown above immediately before that task.
3. In the task `[detect] Query PCI devices`, find the exact string `ansible.builtin.shell:` and replace it with `ansible.builtin.command:`.
4. Keep the `cmd: lspci -nn`, `register: lspci_output`, and `changed_when: false` fields unchanged.

### BUG-2 · SSH hardening writes into a directory that may not exist

**File:** `devplatform.yml`  
**Line:** 91–101  
**Fixable by:** AI agent  
**Status:** Open -> Fixed

**Problem:**
The task `[SSH] Write sshd hardening config` writes to `/etc/ssh/sshd_config.d/devplatform.conf`. On systems where `openssh-server` is not installed yet, `/etc/ssh/sshd_config.d` may not exist. The `copy` task can fail before the playbook reaches any package-install section.

The task also assumes an SSH daemon is present and restartable. If this playbook is intended to harden SSH, it should first install `openssh-server` or explicitly create the config directory.

**Current code:**
```yaml
    - name: "[SSH] Write sshd hardening config"
      ansible.builtin.copy:
        dest: /etc/ssh/sshd_config.d/devplatform.conf
        owner: root
        group: root
```

**Fixed code:**
```yaml
    - name: "[SSH] Ensure OpenSSH server and config directory exist"
      ansible.builtin.apt:
        name: openssh-server
        state: present
        update_cache: true

    - name: "[SSH] Ensure sshd config drop-in directory exists"
      ansible.builtin.file:
        path: /etc/ssh/sshd_config.d
        state: directory
        owner: root
        group: root
        mode: "0755"

    - name: "[SSH] Write sshd hardening config"
      ansible.builtin.copy:
        dest: /etc/ssh/sshd_config.d/devplatform.conf
        owner: root
        group: root
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[SSH] Write sshd hardening config`.
3. Add a new task immediately before it named `[SSH] Ensure OpenSSH server and config directory exist`.
4. Add a second new task immediately after that named `[SSH] Ensure sshd config drop-in directory exists`.
5. Leave the existing `[SSH] Write sshd hardening config` task in place after those two prerequisite tasks.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[SSH] Write sshd hardening config"`.
2. Insert the two fixed prerequisite tasks shown above immediately before `- name: "[SSH] Write sshd hardening config"`.
3. Do not remove the existing `[SSH] Write sshd hardening config` task.
4. Preserve the existing `notify: Restart ssh` line in the existing SSH hardening task.

### BUG-3 · VirtualBox Guest Additions installer can fail because build prerequisites are installed too late or not at all

**File:** `devplatform.yml`  
**Line:** 277–281  
**Fixable by:** Human and AI agent  
**Status:** Open -> Fixed

**Problem:**
The task `[gpu/vm] Install VirtualBox Guest Additions from ISO` executes `/mnt/vbox-ga/VBoxLinuxAdditions.run --nox11`, but the surrounding VirtualBox section does not install common build prerequisites such as `build-essential`, `dkms`, `linux-headers-amd64`, `bzip2`, and `perl` before running the installer.

On a fresh Debian VM, Guest Additions often needs kernel headers and build tools to compile kernel modules. Without them, the script can return non-zero or appear partially installed while graphics, clipboard, shared folders, or dynamic resizing remain broken.

**Current code:**
```yaml
    - name: "[gpu/vm] Install VirtualBox Guest Additions from ISO"
      ansible.builtin.shell:
        cmd: /mnt/vbox-ga/VBoxLinuxAdditions.run --nox11
      register: vbox_ga_result
      failed_when: vbox_ga_result.rc not in [0, 1, 2]
```

**Fixed code:**
```yaml
    - name: "[gpu/vm] Install VirtualBox Guest Additions prerequisites"
      ansible.builtin.apt:
        name:
          - build-essential
          - dkms
          - linux-headers-amd64
          - bzip2
          - perl
        state: present
        update_cache: true
      when:
        - is_virtualbox
        - not vbox_ga_installed.stat.exists
        - cdrom_stat.stat.exists

    - name: "[gpu/vm] Install VirtualBox Guest Additions from ISO"
      ansible.builtin.command:
        cmd: /mnt/vbox-ga/VBoxLinuxAdditions.run --nox11
      register: vbox_ga_result
      failed_when: vbox_ga_result.rc not in [0, 1, 2]
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[gpu/vm] Install VirtualBox Guest Additions from ISO`.
3. Add the new prerequisite-install task immediately before it.
4. Replace `ansible.builtin.shell` with `ansible.builtin.command` in the Guest Additions installer task.
5. Keep the existing `when` conditions on the Guest Additions installer task.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[gpu/vm] Install VirtualBox Guest Additions from ISO"`.
2. Insert the fixed task named `[gpu/vm] Install VirtualBox Guest Additions prerequisites` immediately before it.
3. In task `[gpu/vm] Install VirtualBox Guest Additions from ISO`, replace the exact string `ansible.builtin.shell:` with `ansible.builtin.command:`.
4. Do not change `cmd: /mnt/vbox-ga/VBoxLinuxAdditions.run --nox11`.

---

## Pitfalls and Hidden Failures

### PITFALL-1 · Bootstrap validates Debian release but not the required amd64 architecture

**File:** `devplatformbootstrap.sh`  
**Line:** 121–127  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**
The comments state that the target platform is Debian 13 `amd64`, and the playbook downloads several hardcoded `amd64` or `x86_64` artifacts. The bootstrap checks only `ID=debian` and `VERSION_CODENAME=trixie`, so it can proceed on `arm64`, `i386`, or another architecture until a later binary download or install fails.

This creates confusing mid-run failures and can leave a partially configured system. The architecture should be rejected before package changes begin.

**Current code:**
```bash
if [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
    die "This script requires Debian 13 (trixie).\n" \
        "  Detected: ${PRETTY_NAME:-unknown}\n" \
        "  Please run on a fresh Debian 13 installation."
fi

success "OS confirmed: ${PRETTY_NAME}"
```

**Fixed code:**
```bash
if [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
    die "This script requires Debian 13 (trixie).\n" \
        "  Detected: ${PRETTY_NAME:-unknown}\n" \
        "  Please run on a fresh Debian 13 installation."
fi

if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    die "This script requires Debian 13 amd64.\n" \
        "  Detected architecture: $(dpkg --print-architecture)"
fi

success "OS confirmed: ${PRETTY_NAME} amd64"
```

**Human instructions:**
1. Open `devplatformbootstrap.sh`.
2. Find the OS verification block that checks `VERSION_CODENAME`.
3. Add a new architecture check immediately after the `VERSION_CODENAME` block.
4. Change the success message to include `amd64`.

**AI agent instructions:**
1. In `devplatformbootstrap.sh`, find the exact string `success "OS confirmed: ${PRETTY_NAME}"`.
2. Replace that one line with the full fixed architecture-check block shown above.
3. Keep the existing `VERSION_CODENAME` check unchanged.
4. Do not move the `source /etc/os-release` statement.

### PITFALL-2 · Playbook has no Ansible-side architecture assertion

**File:** `devplatform.yml`  
**Line:** 45–52  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**
Even if the bootstrap gains an architecture check, the playbook can still be run directly with `ansible-playbook /tmp/devplatform.yml`. The playbook currently asserts only Debian and `trixie`, not `x86_64`.

Because the playbook contains hardcoded `amd64` downloads and repository architecture filters, it should fail at the top when `ansible_architecture` is not `x86_64`.

**Current code:**
```yaml
    - name: "[PRE] Assert Debian 13 trixie"
      ansible.builtin.assert:
        that:
          - ansible_distribution == "Debian"
          - ansible_distribution_release == "trixie"
        fail_msg: >
          This playbook requires Debian 13 (trixie).
```

**Fixed code:**
```yaml
    - name: "[PRE] Assert Debian 13 trixie amd64"
      ansible.builtin.assert:
        that:
          - ansible_distribution == "Debian"
          - ansible_distribution_release == "trixie"
          - ansible_architecture == "x86_64"
        fail_msg: >
          This playbook requires Debian 13 (trixie) amd64.
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[PRE] Assert Debian 13 trixie`.
3. Rename the task to `[PRE] Assert Debian 13 trixie amd64`.
4. Add `ansible_architecture == "x86_64"` to the `that` list.
5. Update the `fail_msg` to mention `amd64`.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact string `- name: "[PRE] Assert Debian 13 trixie"`.
2. Replace it with `- name: "[PRE] Assert Debian 13 trixie amd64"`.
3. In the same task, find the exact line `          - ansible_distribution_release == "trixie"` and insert `          - ansible_architecture == "x86_64"` immediately after it.
4. In the same task, replace `This playbook requires Debian 13 (trixie).` with `This playbook requires Debian 13 (trixie) amd64.`.

### PITFALL-3 · SSH password login is disabled without proving key-based access works

**File:** `devplatform.yml`  
**Line:** 97–101  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The SSH hardening block sets `PasswordAuthentication no` and restarts SSH. If a user is provisioning over SSH using password authentication, or has not yet confirmed that public-key authentication works, this can lock the operator out.

This is a production-impacting operational pitfall. The setting is valid for hardened machines, but it should be gated behind an explicit variable and should not be silently applied by default.

**Current code:**
```yaml
        content: |
          PermitRootLogin no
          PasswordAuthentication no
          X11Forwarding no
      notify: Restart ssh
```

**Fixed code:**
```yaml
        content: |
          PermitRootLogin no
          PasswordAuthentication {{ 'no' if disable_ssh_password_auth | default(false) else 'yes' }}
          X11Forwarding no
      notify: Restart ssh
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[SSH] Write sshd hardening config`.
3. Replace the literal line `PasswordAuthentication no` with the templated line shown in the fixed code.
4. Add documentation near the playbook variables explaining that `disable_ssh_password_auth: true` should only be set after SSH key login is verified.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[SSH] Write sshd hardening config"`.
2. Within that task, find the exact line `          PasswordAuthentication no`.
3. Replace it with `          PasswordAuthentication {{ 'no' if disable_ssh_password_auth | default(false) else 'yes' }}`.
4. Do not change `PermitRootLogin no` or `X11Forwarding no`.

### PITFALL-4 · Docker CE install does not remove conflicting Docker packages first

**File:** `devplatform.yml`  
**Line:** 1158–1166  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**
The playbook installs Docker CE packages from Docker’s upstream repository, but it does not first remove conflicting packages such as `docker.io`, `docker-compose`, `podman-docker`, `containerd`, or `runc`.

On systems that are not perfectly fresh, package conflicts can cause the Docker install to fail or produce an unexpected mix of Debian and Docker upstream components. This is especially likely if the user experimented with container tooling before running the bootstrap.

**Current code:**
```yaml
    - name: "[DOCKER] Install Docker CE"
      ansible.builtin.apt:
        name:
          - docker-ce              # Docker Engine
          - docker-ce-cli          # Docker CLI
```

**Fixed code:**
```yaml
    - name: "[DOCKER] Remove conflicting Docker packages"
      ansible.builtin.apt:
        name:
          - docker.io
          - docker-doc
          - docker-compose
          - docker-compose-v2
          - podman-docker
          - containerd
          - runc
        state: absent

    - name: "[DOCKER] Install Docker CE"
      ansible.builtin.apt:
        name:
          - docker-ce              # Docker Engine
          - docker-ce-cli          # Docker CLI
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[DOCKER] Install Docker CE`.
3. Add the new task `[DOCKER] Remove conflicting Docker packages` immediately before it.
4. Keep the existing Docker CE install task unchanged.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[DOCKER] Install Docker CE"`.
2. Insert the fixed task named `[DOCKER] Remove conflicting Docker packages` immediately before it.
3. Do not edit the `name:` package list inside `[DOCKER] Install Docker CE`.
4. Preserve the task name `[DOCKER] Install Docker CE`.

---

## Security Issues

### SEC-1 · Bootstrap downloads and executes a mutable `main` branch playbook as root

**File:** `devplatformbootstrap.sh`  
**Line:** 29–36, 271–301  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The bootstrap builds `PLAYBOOK_URL` from `GITHUB_BRANCH="main"`, downloads it, performs only a weak grep check for `^- name:`, and then executes the downloaded playbook as root. A force-push, compromised repository, account takeover, or unintended commit to `main` becomes root-level code execution on every machine running the bootstrap.

For production-grade bootstrapping, the downloaded artifact must be immutable and verified. At minimum, pin the reference to a release tag or commit SHA and verify the SHA256 of the downloaded playbook before execution.

**Current code:**
```bash
GITHUB_RAW_BASE="https://raw.githubusercontent.com"
GITHUB_USER="Korplin"
GITHUB_REPO="LinuxDevPlatformBootstrap3"
GITHUB_BRANCH="main"
PLAYBOOK_FILENAME="devplatform.yml"

PLAYBOOK_URL="${GITHUB_RAW_BASE}/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${PLAYBOOK_FILENAME}"
```

**Fixed code:**
```bash
GITHUB_RAW_BASE="https://raw.githubusercontent.com"
GITHUB_USER="Korplin"
GITHUB_REPO="LinuxDevPlatformBootstrap3"
GITHUB_REF="v1.0.0"
PLAYBOOK_FILENAME="devplatform.yml"
PLAYBOOK_SHA256="REPLACE_WITH_RELEASE_PLAYBOOK_SHA256"

PLAYBOOK_URL="${GITHUB_RAW_BASE}/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_REF}/${PLAYBOOK_FILENAME}"
```

**Human instructions:**
1. Open `devplatformbootstrap.sh`.
2. Replace `GITHUB_BRANCH="main"` with an immutable `GITHUB_REF` value such as a signed release tag or commit SHA.
3. Add a `PLAYBOOK_SHA256` variable containing the expected checksum for that exact playbook content.
4. Update `PLAYBOOK_URL` to use `GITHUB_REF`.
5. Compute and publish the checksum as part of the release process.

**AI agent instructions:**
1. In `devplatformbootstrap.sh`, find the exact string `GITHUB_BRANCH="main"` and replace it with `GITHUB_REF="v1.0.0"`.
2. In `devplatformbootstrap.sh`, find the exact string `PLAYBOOK_FILENAME="devplatform.yml"` and insert `PLAYBOOK_SHA256="REPLACE_WITH_RELEASE_PLAYBOOK_SHA256"` immediately after it.
3. In `devplatformbootstrap.sh`, find the exact string `${GITHUB_BRANCH}` in the `PLAYBOOK_URL` assignment and replace it with `${GITHUB_REF}`.
4. Do not invent the real checksum; leave `REPLACE_WITH_RELEASE_PLAYBOOK_SHA256` for the release maintainer.

### SEC-2 · Downloaded playbook is not checksum-verified before root execution

**File:** `devplatformbootstrap.sh`  
**Line:** 288–301  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**
The bootstrap checks only that the downloaded file is non-empty and contains a line beginning with `- name:`. That does not prove integrity or authenticity. A malicious playbook can trivially satisfy this check.

Because the next stage runs the file as root through Ansible, checksum verification should happen after download and before the Ansible handoff.

**Current code:**
```bash
# Guard: downloaded file must not be empty.
if [[ ! -s "${PLAYBOOK_DEST}" ]]; then
    die "Downloaded file is empty.\n  URL may be wrong: ${PLAYBOOK_URL}"
fi

# Guard: downloaded file must look like an Ansible playbook.
```

**Fixed code:**
```bash
# Guard: downloaded file must not be empty.
if [[ ! -s "${PLAYBOOK_DEST}" ]]; then
    die "Downloaded file is empty.\n  URL may be wrong: ${PLAYBOOK_URL}"
fi

if [[ "${PLAYBOOK_SHA256}" == "REPLACE_WITH_RELEASE_PLAYBOOK_SHA256" ]]; then
    die "PLAYBOOK_SHA256 is not set. Refusing to execute an unverified playbook."
fi

echo "${PLAYBOOK_SHA256}  ${PLAYBOOK_DEST}" | sha256sum -c -

# Guard: downloaded file must look like an Ansible playbook.
```

**Human instructions:**
1. Open `devplatformbootstrap.sh`.
2. Find the block that checks whether `PLAYBOOK_DEST` is empty.
3. Add the checksum validation block immediately after the empty-file check.
4. Replace `REPLACE_WITH_RELEASE_PLAYBOOK_SHA256` in the variable section with the real SHA256 before publishing.

**AI agent instructions:**
1. In `devplatformbootstrap.sh`, find the exact comment `# Guard: downloaded file must not be empty.`.
2. Find the `if [[ ! -s "${PLAYBOOK_DEST}" ]]; then` block ending with `fi`.
3. Insert the fixed checksum validation block immediately after that `fi`.
4. Do not remove the existing grep sanity check.

### SEC-3 · Predictable `/tmp` path allows avoidable symlink and race risks

**File:** `devplatformbootstrap.sh`  
**Line:** 36  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**
The bootstrap writes the root-executed playbook to `/tmp/devplatform.yml`. `/tmp` is shared and world-writable. Predictable file names in `/tmp` create avoidable symlink, overwrite, and race concerns, especially on multi-user systems.

The bootstrap should create a private temporary directory with `mktemp -d`, restrict permissions, and clean it up with a `trap`.

**Current code:**
```bash
PLAYBOOK_URL="${GITHUB_RAW_BASE}/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${PLAYBOOK_FILENAME}"
PLAYBOOK_DEST="/tmp/${PLAYBOOK_FILENAME}"
```

**Fixed code:**
```bash
PLAYBOOK_URL="${GITHUB_RAW_BASE}/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_REF}/${PLAYBOOK_FILENAME}"
WORKDIR="$(mktemp -d)"
chmod 700 "${WORKDIR}"
trap 'rm -rf "${WORKDIR}"' EXIT
PLAYBOOK_DEST="${WORKDIR}/${PLAYBOOK_FILENAME}"
```

**Human instructions:**
1. Open `devplatformbootstrap.sh`.
2. Find the `PLAYBOOK_DEST="/tmp/${PLAYBOOK_FILENAME}"` assignment.
3. Replace it with the `WORKDIR`, `chmod`, `trap`, and `PLAYBOOK_DEST` assignments shown in the fixed code.
4. Confirm that every later reference still uses `PLAYBOOK_DEST`.

**AI agent instructions:**
1. In `devplatformbootstrap.sh`, find the exact line `PLAYBOOK_DEST="/tmp/${PLAYBOOK_FILENAME}"`.
2. Replace that line with the four fixed lines beginning with `WORKDIR="$(mktemp -d)"`.
3. Ensure the `PLAYBOOK_URL` assignment uses `${GITHUB_REF}` if SEC-1 has also been applied.
4. Do not change references to `${PLAYBOOK_DEST}` elsewhere.

### SEC-4 · Docker group membership grants root-equivalent privileges by default

**File:** `devplatform.yml`  
**Line:** 1168–1175  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The task `[DOCKER] Add {{ real_user }} to docker group` adds the desktop user to the `docker` group. The comments correctly state that this is equivalent to effective root access on the host. As a developer-workstation convenience it may be acceptable, but production-grade bootstrap code should make this an explicit opt-in.

Defaulting to root-equivalent group membership widens the blast radius of a compromised user account and can surprise users who expect a hardened baseline.

**Current code:**
```yaml
    - name: "[DOCKER] Add {{ real_user }} to docker group"
      ansible.builtin.user:
        name: "{{ real_user }}"
        groups: docker
        append: true
      # SECURITY NOTE: docker group = effective root on the host.
```

**Fixed code:**
```yaml
    - name: "[DOCKER] Add {{ real_user }} to docker group"
      ansible.builtin.user:
        name: "{{ real_user }}"
        groups: docker
        append: true
      when: add_user_to_docker_group | default(false)
      # SECURITY NOTE: docker group = effective root on the host.
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[DOCKER] Add {{ real_user }} to docker group`.
3. Add `when: add_user_to_docker_group | default(false)` to the task.
4. Document that users can set `add_user_to_docker_group: true` only if they accept root-equivalent Docker access.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[DOCKER] Add {{ real_user }} to docker group"`.
2. Within that task, find the exact line `        append: true`.
3. Insert `      when: add_user_to_docker_group | default(false)` immediately after `        append: true`.
4. Do not alter the existing security comment.

---

## Idempotency Issues

### IDEM-1 · VS Code signing key is rewritten every run while reporting unchanged

**File:** `devplatform.yml`  
**Line:** 715–729  
**Fixable by:** AI agent  
**Status:** Open

**Problem:**
The task `[VSCODE] Download Microsoft signing key` uses `force: true`, and `[VSCODE] Install Microsoft signing key` writes `/usr/share/keyrings/microsoft.gpg` through a shell command with `changed_when: false`. This means the key can be rewritten on every run while Ansible reports no change.

That makes re-run output misleading and hides real state changes. Use a `creates:` guard or switch to an idempotent command pattern that only dearmors when the target file does not exist.

**Current code:**
```yaml
    - name: "[VSCODE] Download Microsoft signing key"
      ansible.builtin.get_url:
        url: https://packages.microsoft.com/keys/microsoft.asc
        dest: /tmp/microsoft.asc
        mode: "0644"
        force: true

    - name: "[VSCODE] Install Microsoft signing key"
      ansible.builtin.shell: |
        set -euo pipefail
        gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft.gpg
        chmod 0644 /usr/share/keyrings/microsoft.gpg
      args:
        executable: /bin/bash
      changed_when: false
```

**Fixed code:**
```yaml
    - name: "[VSCODE] Download Microsoft signing key"
      ansible.builtin.get_url:
        url: https://packages.microsoft.com/keys/microsoft.asc
        dest: /tmp/microsoft.asc
        mode: "0644"
        force: false

    - name: "[VSCODE] Install Microsoft signing key"
      ansible.builtin.shell: |
        set -euo pipefail
        gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft.gpg
        chmod 0644 /usr/share/keyrings/microsoft.gpg
      args:
        executable: /bin/bash
        creates: /usr/share/keyrings/microsoft.gpg
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[VSCODE] Download Microsoft signing key`.
3. Change `force: true` to `force: false`.
4. Find the task named `[VSCODE] Install Microsoft signing key`.
5. Add `creates: /usr/share/keyrings/microsoft.gpg` under `args`.
6. Remove the `changed_when: false` line from that task.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[VSCODE] Download Microsoft signing key"`.
2. Within that task, replace the exact line `        force: true` with `        force: false`.
3. In `devplatform.yml`, find the exact task name string `- name: "[VSCODE] Install Microsoft signing key"`.
4. Within that task, find the line `        executable: /bin/bash` and insert `        creates: /usr/share/keyrings/microsoft.gpg` immediately after it.
5. Within the same task, remove the exact line `      changed_when: false`.

### IDEM-2 · `latest` kubectl install never converges to a declared version after first install

**File:** `devplatform.yml`  
**Line:** 1191–1206  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The task `[KUBECTL] Install kubectl — official binary` installs whatever `https://dl.k8s.io/release/stable.txt` returns, but only when `/usr/local/bin/kubectl` is absent. After the first install, the playbook never updates kubectl and does not verify whether the installed version is desired.

This is not declarative convergence. Either pin `kubectl_version` or query the installed version and upgrade intentionally.

**Current code:**
```yaml
    - name: "[KUBECTL] Check if kubectl is already installed"
      ansible.builtin.stat:
        path: /usr/local/bin/kubectl
      register: _kubectl_stat

    - name: "[KUBECTL] Install kubectl — official binary"
      ansible.builtin.shell:
        cmd: |
          set -euo pipefail
          VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
          curl -sLO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
```

**Fixed code:**
```yaml
    - name: "[KUBECTL] Check installed kubectl version"
      ansible.builtin.command:
        cmd: /usr/local/bin/kubectl version --client=true --output=yaml
      register: _kubectl_installed
      changed_when: false
      failed_when: false

    - name: "[KUBECTL] Install kubectl — pinned official binary"
      ansible.builtin.shell:
        cmd: |
          set -euo pipefail
          VERSION="{{ kubectl_version }}"
          curl -fsSLO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Add a variable named `kubectl_version` to the playbook variables.
3. Replace the stat-based kubectl presence check with a command-based version check.
4. Replace the use of `stable.txt` with `VERSION="{{ kubectl_version }}"`.
5. Add a `when` condition that installs kubectl only when `kubectl_version` is not present in `_kubectl_installed.stdout`.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[KUBECTL] Check if kubectl is already installed"`.
2. Replace that task with the fixed task named `[KUBECTL] Check installed kubectl version`.
3. In `devplatform.yml`, find the exact task name string `- name: "[KUBECTL] Install kubectl — official binary"` and replace it with `- name: "[KUBECTL] Install kubectl — pinned official binary"`.
4. Within the kubectl install task, find the exact line `          VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)` and replace it with `          VERSION="{{ kubectl_version }}"`.
5. Within the kubectl install task, replace `      when: not _kubectl_stat.stat.exists` with `      when: kubectl_version not in (_kubectl_installed.stdout | default(''))`.

### IDEM-3 · Cursor install skips upgrades forever once `/usr/bin/cursor` exists

**File:** `devplatform.yml`  
**Line:** 756–815  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The Cursor section checks only whether `/usr/bin/cursor` exists. If it exists, the playbook skips fetching metadata, skips downloading the package, and never compares the installed version to the API-reported version.

This avoids repeated installs, but it does not keep the machine converged to the desired Cursor version. It also means a broken or stale binary at `/usr/bin/cursor` blocks remediation.

**Current code:**
```yaml
    - name: "[cursor] Check whether Cursor binary already exists"
      ansible.builtin.stat:
        path: /usr/bin/cursor
      register: cursor_binary_stat

    - name: "[cursor] Ensure xz-utils is present"
      ansible.builtin.apt:
        name: xz-utils
        state: present
        update_cache: false
```

**Fixed code:**
```yaml
    - name: "[cursor] Check installed Cursor version"
      ansible.builtin.command:
        cmd: /usr/bin/cursor --version
      register: cursor_installed_version
      changed_when: false
      failed_when: false

    - name: "[cursor] Ensure xz-utils is present"
      ansible.builtin.apt:
        name: xz-utils
        state: present
        update_cache: false
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[cursor] Check whether Cursor binary already exists`.
3. Replace the stat task with a command task that captures `/usr/bin/cursor --version`.
4. Fetch Cursor API metadata regardless of binary existence.
5. Change later `when` conditions from checking `not cursor_binary_stat.stat.exists` to comparing `cursor_expected_version` with `cursor_installed_version.stdout`.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[cursor] Check whether Cursor binary already exists"`.
2. Replace that task with the fixed task named `[cursor] Check installed Cursor version`.
3. In all Cursor tasks from `[cursor] Ensure xz-utils is present` through `[cursor] Install Cursor IDE from downloaded .deb`, replace the exact condition `when: not cursor_binary_stat.stat.exists` with `when: cursor_expected_version | default('') not in (cursor_installed_version.stdout | default(''))` after the metadata parse task exists.
4. Remove the variable name `cursor_binary_stat` from the Cursor install flow except where final binary existence verification is still needed.

---

## Design Choices Worth Documenting

### DESIGN-1 · Playbook overwrites `/etc/apt/sources.list` instead of managing a dedicated source file

**File:** `devplatform.yml`  
**Line:** 110–123  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The task `[APT] Write /etc/apt/sources.list` replaces the system’s main APT sources file. This is reasonable for a fresh, disposable Debian workstation image, but it can surprise users on systems that already use Deb822 `.sources` files, local mirrors, proxies, snapshot repositories, or corporate package policy.

The design should either be documented as “fresh install only” or changed to manage a dedicated file in `/etc/apt/sources.list.d`.

**Current code:**
```yaml
    - name: "[APT] Write /etc/apt/sources.list"
      ansible.builtin.copy:
        dest: /etc/apt/sources.list
        owner: root
        group: root
        mode: "0644"
```

**Fixed code:**
```yaml
    - name: "[APT] Write devplatform Debian sources"
      ansible.builtin.copy:
        dest: /etc/apt/sources.list.d/devplatform.list
        owner: root
        group: root
        mode: "0644"
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[APT] Write /etc/apt/sources.list`.
3. Rename the task to `[APT] Write devplatform Debian sources`.
4. Change `dest: /etc/apt/sources.list` to `dest: /etc/apt/sources.list.d/devplatform.list`.
5. Document whether existing Debian source files should be disabled or left active.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact string `- name: "[APT] Write /etc/apt/sources.list"`.
2. Replace it with `- name: "[APT] Write devplatform Debian sources"`.
3. In the same task, find the exact line `        dest: /etc/apt/sources.list`.
4. Replace it with `        dest: /etc/apt/sources.list.d/devplatform.list`.
5. Do not modify the repository content block in this edit.

### DESIGN-2 · Full upgrade and purge autoremove are aggressive defaults

**File:** `devplatform.yml`  
**Line:** 147–160  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
The playbook performs a full distribution upgrade and then purges orphaned packages. For a fresh bootstrap this is often desirable, but on an existing workstation it can remove packages the user expected to keep or trigger large changes unrelated to the developer platform.

This should be an explicit design choice controlled by variables. That makes the script safer for re-runs and clearer for users.

**Current code:**
```yaml
    - name: "[APT] Full system upgrade"
      ansible.builtin.apt:
        upgrade: full
        update_cache: true

    - name: "[FINAL] Remove orphaned packages"
      ansible.builtin.apt:
        autoremove: true
        purge: true
```

**Fixed code:**
```yaml
    - name: "[APT] Full system upgrade"
      ansible.builtin.apt:
        upgrade: full
        update_cache: true
      when: perform_full_upgrade | default(true)

    - name: "[FINAL] Remove orphaned packages"
      ansible.builtin.apt:
        autoremove: true
        purge: true
      when: perform_autoremove_purge | default(false)
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find the task named `[APT] Full system upgrade`.
3. Add `when: perform_full_upgrade | default(true)` to that task.
4. Find the task named `[FINAL] Remove orphaned packages`.
5. Add `when: perform_autoremove_purge | default(false)` to that task.
6. Document both variables in the repository README.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[APT] Full system upgrade"`.
2. Within that task, insert `      when: perform_full_upgrade | default(true)` immediately after `        update_cache: true`.
3. In `devplatform.yml`, find the exact task name string `- name: "[FINAL] Remove orphaned packages"`.
4. Within that task, insert `      when: perform_autoremove_purge | default(false)` immediately after `        purge: true`.
5. Do not change the `[FINAL] Clean apt package cache` task.

### DESIGN-3 · Many third-party tools use “latest” URLs instead of pinned versions

**File:** `devplatform.yml`  
**Line:** 568–579, 1116–1125, 1309–1322  
**Fixable by:** Human and AI agent  
**Status:** Open

**Problem:**
Several tools are installed from mutable `latest` URLs or release APIs, including lazygit, yq, and cosign. This reduces reproducibility because two machines provisioned at different times can receive different binaries.

Using “latest” is convenient for a personal workstation bootstrap, but production-grade provisioning should pin versions and checksums. If the project intentionally tracks latest releases, that policy should be documented and tested in CI.

**Current code:**
```yaml
    - name: "[COSIGN] Install cosign binary"
      ansible.builtin.get_url:
        url: https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
        dest: /usr/local/bin/cosign
        owner: root
```

**Fixed code:**
```yaml
    - name: "[COSIGN] Install cosign binary"
      ansible.builtin.get_url:
        url: "https://github.com/sigstore/cosign/releases/download/{{ cosign_version }}/cosign-linux-amd64"
        dest: /usr/local/bin/cosign
        owner: root
        checksum: "sha256:{{ cosign_sha256 }}"
```

**Human instructions:**
1. Open `devplatform.yml`.
2. Find each third-party binary install that references `/latest/` or a releases API.
3. Add explicit version variables such as `cosign_version`, `yq_version`, and `lazygit_version`.
4. Add checksum variables for each downloaded binary or archive.
5. Replace mutable latest URLs with versioned release URLs.
6. Document the update process for these pinned versions.

**AI agent instructions:**
1. In `devplatform.yml`, find the exact task name string `- name: "[COSIGN] Install cosign binary"`.
2. In that task, replace the exact URL `https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64` with `"https://github.com/sigstore/cosign/releases/download/{{ cosign_version }}/cosign-linux-amd64"`.
3. In that task, insert `        checksum: "sha256:{{ cosign_sha256 }}"` immediately after `        owner: root`.
4. Repeat the same pinned-version and checksum pattern for tasks `[YQ] Install yq Go binary (mikefarah/yq)` and `[GIT] Install lazygit — TUI git client`.

---

## What Is Done Well

1. `devplatformbootstrap.sh` uses `set -euo pipefail`, which is the right baseline for fail-fast shell scripting.
2. `devplatformbootstrap.sh` performs a clear Debian 13 `trixie` OS gate before modifying APT sources or installing packages.
3. `devplatformbootstrap.sh` has thoughtful real-user detection and validates that the detected user exists before handing off to Ansible.
4. `devplatform.yml` consistently uses fully qualified `ansible.builtin.*` module names, which improves readability and avoids collection ambiguity.
5. `devplatform.yml` uses `append: true` when adding the user to groups, preserving existing group memberships.
6. `devplatform.yml` uses modern APT repository patterns with `signed-by` keyrings for several third-party repositories.
7. `devplatform.yml` includes checksum verification for Helm, which is the right pattern to replicate for other downloaded binaries.
8. `devplatform.yml` separates bootstrap concerns from declared system state, which is a good architecture for workstation provisioning.
9. The comments explain many tradeoffs clearly, especially around Debian firmware components, Docker CE, and the Docker group.
10. The final cleanup section removes temporary artifacts, which is good hygiene even though the temp paths should be made private.

---

*Generated by code review · `devplatform.yml`, `devplatformbootstrap.sh` · 2026-04-25*

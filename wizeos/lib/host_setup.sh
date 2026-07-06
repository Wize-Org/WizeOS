#!/usr/bin/env bash
setup_host() {
  export DEBIAN_FRONTEND=noninteractive
  log "Allowing nsjail to use unprivileged user namespaces"
  if sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
    sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
    printf '%s\n' 'kernel.apparmor_restrict_unprivileged_userns=0' >/etc/sysctl.d/99-grapheneos-build.conf
  fi
  log "Installing base packages"
  apt-get update
  apt-get install -y ca-certificates curl gnupg sudo repo git openssh-client python3 zip unzip lz4 rsync diffutils fontconfig fonts-dejavu-core hostname openssl gperf gcc-multilib libc6-dev-i386 build-essential lftp openjdk-21-jdk-headless
  command -v java >/dev/null 2>&1 || die "java was not found after installing openjdk-21-jdk-headless"
  java -version
  log "Installing Node.js 24 and Yarn Classic"
  apt-get remove -y yarnpkg nodejs npm libnode-dev || true
  apt-get autoremove -y || true
  apt-get clean
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
  [ "${NODE_MAJOR}" -ge 24 ] || die "Node.js 24+ is required, installed: $(node -v)"
  npm install -g yarn@1.22.22
  hash -r; node -v; yarn --version
  if ! id -u "${BUILD_USER}" >/dev/null 2>&1; then useradd -m -s /bin/bash "${BUILD_USER}"; fi
  usermod -aG sudo "${BUILD_USER}"
  touch /etc/.repo_gitconfig.json; chown "${BUILD_USER}:${BUILD_USER}" /etc/.repo_gitconfig.json; chmod 0644 /etc/.repo_gitconfig.json
  log "Writing builder Git identity file"
  mkdir -p "/home/${BUILD_USER}"
  cat >"/home/${BUILD_USER}/.gitconfig" <<GITCONFIG_EOF
[user]
	name = ${GIT_USER_NAME}
	email = ${GIT_USER_EMAIL}
[protocol]
	version = 2
[color]
	ui = false
GITCONFIG_EOF
  chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.gitconfig"; chmod 0644 "/home/${BUILD_USER}/.gitconfig"
  printf '%s\n' 'export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin' >"/home/${BUILD_USER}/.bashrc.grapheneos"
  chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.bashrc.grapheneos"
  if ! grep -q '.bashrc.grapheneos' "/home/${BUILD_USER}/.bashrc" 2>/dev/null; then echo 'source ~/.bashrc.grapheneos' >>"/home/${BUILD_USER}/.bashrc"; fi
  chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.bashrc" 2>/dev/null || true
  mkdir -p "${BASE_DIR}"; chown -R "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}"
}

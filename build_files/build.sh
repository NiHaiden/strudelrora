#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Extract the architecture from the kernel package
arch=$(rpm -q kernel --qf "%{ARCH}\n" | head -n1)

# Thanks to bri for the inspiration! My script is mostly based on this example:
# https://github.com/briorg/bluefin/blob/c62c30a04d42fd959ea770722c6b51216b4ec45b/scripts/1password.sh

if [[ "$arch" != "aarch64" ]]; then
    echo "Installing 1Password"

    # On libostree systems, /opt is a symlink to /var/opt,
    # which actually only exists on the live system. /var is
    # a separate mutable, stateful FS that's overlaid onto
    # the ostree rootfs. Therefore we need to install it into
    # /usr/lib/1Password instead, and dynamically create a
    # symbolic link /opt/1Password => /usr/lib/1Password upon
    # boot.

    # Prepare staging directory
    mkdir -p /var/opt # -p just in case it exists
    # for some reason...

    # Setup repo
    cat << EOF > /etc/yum.repos.d/1password.repo
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

    # Normally, after-install.sh would create a group,
    # "onepassword", right about now. But if we do that during
    # the ostree build it'll disappear from the running system!
    # I'm going to work around that by hardcoding GIDs and
    # crossing my fingers that nothing else steps on them.
    # These numbers _should_ be okay under normal use, but
    # if there's a more specific range that I should use here
    # please submit a PR!

    # Specifically, GID must be > 1000, and absolutely must not
    # conflict with any real groups on the deployed system.
    # Normal user group GIDs on Fedora are sequential starting
    # at 1000, so let's skip ahead and set to something higher.
    GID_ONEPASSWORD="1790"
    GID_ONEPASSWORDCLI="1791"
    GID_ONEPASSWORDMCP="1792"

    cat >/usr/lib/sysusers.d/onepassword.conf <<EOF
g onepassword ${GID_ONEPASSWORD}
EOF

    cat >/usr/lib/sysusers.d/onepassword-cli.conf <<EOF
g onepassword-cli ${GID_ONEPASSWORDCLI}
EOF

    cat >/usr/lib/sysusers.d/onepassword-mcp.conf <<EOF
g onepassword-mcp ${GID_ONEPASSWORDMCP}
EOF

    systemd-sysusers /usr/lib/sysusers.d/onepassword.conf
    systemd-sysusers /usr/lib/sysusers.d/onepassword-cli.conf
    systemd-sysusers /usr/lib/sysusers.d/onepassword-mcp.conf

    # /usr/local points to /var/usrlocal, which is not populated during an
    # image build. The 1Password post-install script needs this target for
    # its MCP helper symlink.
    mkdir -p /var/usrlocal/bin

    # Now let's install the packages.
    dnf install -y 1password 1password-cli

    # Clean up the yum repo (updates are baked into new images)
    rm /etc/yum.repos.d/1password.repo -f

    # And then we do the hacky dance!
    mv /var/opt/1Password /usr/lib/1Password # move this over here

    # Create a symlink /usr/bin/1password => /opt/1Password/1password
    rm /usr/bin/1password
    ln -s /opt/1Password/1password /usr/bin/1password

    #####
    # The following is a bastardization of "after-install.sh"
    # which is normally packaged with 1password. You can compare with
    # /usr/lib/1Password/after-install.sh if you want to see.
    BROWSER_SUPPORT_PATH="/usr/lib/1Password/1Password-BrowserSupport"

    # BrowserSupport binary needs setgid. This gives no extra permissions to the binary.
    # It only hardens it against environmental tampering.
    chgrp "${GID_ONEPASSWORD}" "${BROWSER_SUPPORT_PATH}"
    chmod g+s "${BROWSER_SUPPORT_PATH}"

    # onepassword-cli also needs its own group and setgid, like the other helpers.
    chgrp ${GID_ONEPASSWORDCLI} /usr/bin/op
    chmod g+s /usr/bin/op

    # The desktop package also ships an MCP helper on recent releases.
    MCP_SUPPORT_PATH="/usr/lib/1Password/1password-mcp"
    if [[ -f "${MCP_SUPPORT_PATH}" ]]; then
        chgrp "${GID_ONEPASSWORDMCP}" "${MCP_SUPPORT_PATH}"
        chmod g+s "${MCP_SUPPORT_PATH}"
    fi

    # Register path symlink
    # We do this via tmpfiles.d so that it is created by the live system.
    cat >/usr/lib/tmpfiles.d/eternal-onepassword.conf <<EOF
L  /opt/1Password  -  -  -  -  /usr/lib/1Password
d  /var/usrlocal/bin  0755  root  root  -
L  /var/usrlocal/bin/1password-mcp  -  -  -  -  /opt/1Password/1password-mcp
EOF

    getent group onepassword
    getent group onepassword-cli
    getent group onepassword-mcp
else
    echo "1Password does not create aarch64 packages"
fi

dnf5 install -y webkit2gtk4.1 webkit2gtk4.1-devel

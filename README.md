# xtruder/homelab

My personal setup for homelab, just a bunch of services deployed with docker-compose and make

## Server deployment

Follow guide on [Installing fedora CoreOS on Bare Metal](https://docs.fedoraproject.org/en-US/fedora-coreos/bare-metal/)

1. Download FCOS ISO

```shell
podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data \
    quay.io/coreos/coreos-installer:release download -s stable -p metal -f iso
```

Burn ISO to USB drive or mount it via piKVM to server

2. Install FCOS

Reboot server and boot from USB drive

Run following command to install FCOS

```shell
sudo coreos-installer install --ignition-url https://github.com/xtruder/homelab/raw/main/ignition/jarvis.ign /dev/sdX
```

3. Reboot server

Reboot server to apply changes

```shell
sudo reboot
```

After reboot the server will automatically be rebased to [ucore server image](https://github.com/xtruder/homelab/pkgs/container/ucore-server),
this will cause server to restart twice.

4. Enroll ublue secure boot keys

```shell
sudo mokutil --import /etc/pki/akmods/certs/akmods-ublue.der
sudo reboot
```

During reboot you will be asked to enroll secure boot keys, select `enroll` and enter password.

## Setup user

1. Create host ssh key and add it as deploy key to github:

```shell
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
```

Add key to: https://github.com/xtruder/homelab/settings/keys

3. Clone and apply dotfiles

```shell
git clone git@github.com:xtruder/homelab.git ~/homelab
chezmoi init --apply --sourceDir ~/homelab
```

4. Reload systemd daemon and enable linger

```shell
systemctl --user daemon-reload
sudo loginctl enable-linger core
```

To pause automatic deployments create `.working` file and it will docker reloads

5. Setup tailscale

```
tailscale up
```


6. Setup firewall

```
firewall-cmd --zone=trusted  --change-interface=incusbr
firewall-cmd --zone=FedoraServer  --add-interface=tailscale0
firewall-cmd --add-port=80/tcp
firewall-cmd --add-port=443/tcp
firewall-cmd --add-port=8080/tcp
firewall-cmd --add-port=8443/tcp
firewall-cmd --runtime-to-permanent
```

7. Configure DNS entries for docker-compose stacks

## Automated updates

Renovate pushes minor and patch image bumps for compose stacks straight to
`master`. Major bumps still arrive as pull requests. GitHub holds no
credentials for jarvis; jarvis pulls and pushes on its own.

Every 5 minutes `homelab-cron.timer` runs `homelab-deploy`, which pulls
`master`, runs `chezmoi apply`, reloads all stacks, and starts
`homelab-verify.service`. When Renovate commits under `stacks/` landed since
the last verified commit, `homelab-verify` runs opencode with
`verify-deploy/prompt.md` in a scratch clone. opencode checks the changed
stacks and either pushes a fix to `master` or reverts the bump, adding a
`renovate.json` rule that stops automerging that package. Results go to a commit
comment, plus an issue when anything was fixed, reverted or still broken.
State lives in `~/.local/state/homelab-verify`; the `verified` file there holds
the last verified commit.

`~/homelab/.working` pauses both deploys and verification. Follow a run with
`journalctl --user -fu homelab-verify`.

Setup:

1. Create a fine-grained GitHub token for `xtruder/homelab` only, with
   Contents, Issues and Pull requests set to read and write.
2. On jarvis, store it with an OpenCode Go API key (mode 600):

   ```shell
   install -D -m 600 /dev/stdin ~/.config/homelab-verify/env <<EOF
   OPENCODE_API_KEY=...
   GH_TOKEN=github_pat_...
   EOF
   ```

3. Apply the dotfiles once by hand, so the new `homelab-cron.service` is in
   place. From then on it applies them itself:

   ```shell
   chezmoi init && chezmoi apply && systemctl --user daemon-reload
   ```

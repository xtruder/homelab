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

After reboot the server will automatically be rebased to [ucore server image](https://github.com/xtruder/homelab/pkgs/container/ucore-server)
and is ready to deploy services.


## Setup

1. Create host ssh key and add it as deploy key to github:

```shell
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub
```

Add key to: https://github.com/xtruder/homelab/settings/keys

2. Install cron job


```shell
git clone git@github.com:xtruder/homelab.git
mkdir -p ~/.config/systemd/user
cp homelab-cron.timer ~/.config/systemd/user/homelab-cron.timer
cp homelab-cron.service ~/.config/systemd/user/homelab-cron.service
systemctl --user daemon-reload
systemctl --user enable homelab-cron.timer
systemctl --user start homelab-cron.timer
```

To pause automatic deployments create `.pause` file and it will skip deployment


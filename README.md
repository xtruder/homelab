# xtruder/homelab

My personal setup for homelab, just a bunch of services deployed with docker-compose and make

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

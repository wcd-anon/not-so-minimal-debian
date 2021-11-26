# not-so-minimal-debian

`not-so-minimal-debian.sh` is a script for configuring Debian GNU/Linux. It is ideally run after the first successful boot into a [minimal install](https://www.dwarmstrong.org/minimal-debian/) of Debian 11 aka "bullseye".

A choice of either a *server* or *desktop* configuration is available. Server installs packages for a basic console setup, whereas desktop intalls a more complete setup with the option of either the [Openbox](https://www.dwarmstrong.org/openbox/) window manager or *Xorg* (with no desktop).

## How does it work

1. Connect to the internet.
2. If not already installed, `apt install curl`.
3. Run (as root) ...

```
bash <(curl -s https://gitlab.com/dwarmstrong/not-so-minimal-debian/-/raw/main/not-so-minimal-debian.sh)
```

## Author

[Daniel Wayne Armstrong](https://www.dwarmstrong.org)

## License

GPLv3. See [LICENSE](https://gitlab.com/dwarmstrong/debian-after-install/blob/master/LICENSE.md) for more details.

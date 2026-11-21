# Changelog

Dipstick follows [Semantic Versioning](https://semver.org/). Bug fixes raise the patch number, new features raise the minor number, and breaking changes raise the major number. The version in `manifest.json` is the source of truth, and each release is tagged `vX.Y.Z`.

## 0.9.0

First public release.

- One compact row of ringed icons for CPU, GPU, RAM, `/tmp`, disks and network.
- CPU and GPU thermometers where a sensor exists.
- Automatic disk discovery, with one ring per independent pool of free space.
- Popup with Overview, System, Storage, Temp, Network and Settings pages.
- Safe `/tmp` cleanup and guided, item-by-item `/boot` cleanup.
- Right click anywhere on Dipstick to open `btop`.

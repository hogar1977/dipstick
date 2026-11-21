# Dipstick

Pull the dipstick and check every level on your machine. Dipstick shows CPU, GPU, temperatures, RAM, `/tmp`, disks and network as one compact row of ringed icons in the Omarchy bar.

It covers permanently installed hardware. Use a removable drive plugin for USB and SD media.

## Install

```sh
omarchy plugin add https://github.com/hogar1977/dipstick --enable
```

## Remove

```sh
omarchy plugin remove io.github.hogar1977.dipstick
```

## Using it

- **Left click** any item to open the popup on that item's page.
- **Right click** anywhere on Dipstick to open `btop`.
- **Hover** an item for its exact value.
- In the popup, `Tab` or `h`/`l` changes page, `j`/`k` moves, and `Esc` closes.
- On the Temp page, `x` or `Enter` cleans the selected row, `P` cleans all stale items, `G` rescans, `v` switches view and `/` searches.

A ring uses your theme's normal color and switches to its alert color at the limit you set. Every limit, visible item and tracked disk can be changed under Settings.

## Disks

Dipstick shows one ring per independent pool of free space. btrfs subvolumes share one ring, while fixed partitions such as `/boot` get their own.

## Cleanup

`/tmp` cleanup never touches items that a running process holds, that belong to another user, or that changed since you reviewed them.

`/boot` cleanup lists kernels and snapshot entries for you to pick individually. Dipstick never deletes files in `/boot`. It shows the exact `limine-snapper-remove` and `pacman -R` commands and runs them in a visible terminal, where you authenticate. The running, default and last remaining kernels cannot be selected.

## Requirements and privileges

- Omarchy Quattro and Python 3 from the base install. No extra Python packages.
- Monitoring needs no root and makes no network requests.
- **Measure /boot** and **List snapshots** ask for authentication through `pkexec`, because `/boot` and snapper data are readable by root only.
- `/boot` removal uses `sudo` in a visible terminal.
- Optional tools: `nvidia-smi` for NVIDIA GPUs, `lspci` for GPU names, `limine-snapper-sync` and `snapper` for snapshot entries.

## Tests

```sh
python3 -B tests/test_janitor.py
python3 -B tests/test_storage.py
node tests/model.test.js
```

## Inspired by

Dipstick is an independent implementation inspired by the capabilities of [Hardware Monitor](https://github.com/edgarsilva/omarchy-hw-monitor) by Edgar Silva, [Disk Space](https://github.com/ErikBurdett/omarchy-diskspace) by Erik Burdett and [Tmpfs Monitor](https://github.com/Kristijan-K/omarchy-tmpfs-monitor) by Kristijan K.

## License

MIT

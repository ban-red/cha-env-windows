# cha-env-windows

Windows 11 as an environment for [Cha Portal](https://github.com/ban-red/cha-portal): a QEMU/KVM virtual machine inside the app container, with Direct3D 11 running on the node's GPU through UTM's Neptune stack. No GPU passthrough is involved, so the GPU stays shared with the node's other environments.

This is experimental. It has been tested on one node: an NVIDIA RTX 4090 running Windows 11 26H2. See [docs/testing.md](docs/testing.md) for what was tested and what was found.

## What to expect

- The first launch installs Windows unattended from an ISO you provide, in about 20 minutes. Later launches boot the installed disk in about a minute.
- Windows logs in automatically as a local account. The desktop, keyboard, mouse and sound go through Cha like any other app.
- Direct3D 11 programs use the node's GPU. Direct3D 12 and Vulkan programs in the guest don't.
- The display follows the size of the player's window, about 10 to 20 seconds after it changes.
- The guest runs at 60 Hz, whatever frame rate the stream is set to.
- There is no gamepad, clipboard or relative-mouse support yet, so games that capture the mouse won't play well.
- Windows is not activated. Activation needs your own licence.

## Requirements

- Cha Portal 0.4.0 or later. The template uses the `vm` security profile, which an admin has to approve.
- A node with KVM (`/dev/kvm`, from the `kvm_intel` or `kvm_amd` module), a Vulkan GPU and enough free memory. The container is capped at 12 GiB by default (`CHA_VM_MEMORY_MB` on the node), and the guest gets 8 GB of it.
- A Windows 11 x64 ISO. 26H2, from Microsoft's download page, is tested. 23H2 crashes when the display driver starts; 24H2 and 25H2 haven't been tried.
- About 16 GB of disk in the user's app data after installation, growing with use. The virtual disk is a sparse 128 GB file.

Only NVIDIA has been tested. AMD and Intel GPUs should work through Mesa but haven't been tried.

## Setting it up

1. In the portal, open **Admin → Catalogs**, add `https://raw.githubusercontent.com/ban-red/cha-env-windows/main/catalog.json`, and approve the template's `vm` profile.
2. Launch **Windows 11 (experimental)** once. It stops with "No Windows 11 ISO", having created its shared folder on the node: `shared/<catalog>.win11/` in the node's data root (`/srv/cha-portal` unless the owner changed it).
3. Put the Windows ISO in that folder, readable by uid 1000.
4. Launch it again. The page shows "Installing Windows" while Setup runs, then the desktop.

The account is `cha` with the password `cha`. Change it in Windows if you share the environment.

Stopping the environment shuts Windows down. The VM is kept in the user's home (`~/windows`) for as long as they keep their app data.

## How it works

```
browser ⇄ cha-streamer (compositor, encoder) ⇄ app container
                   ▲ Wayland, PulseAudio        QEMU's GTK window ── Windows 11 guest
                                                  │ virtio-gpu
                                                  ▼
                               virglrenderer (Neptune) → DXVK → Vulkan on the node's GPU
```

- The app is QEMU's GTK window, a Wayland client of the streamer's compositor. Cha streams it like any other window. QEMU shows the guest's display as a dma-buf through EGL, so frames stay on the GPU.
- Windows' sound goes to the streamer's PulseAudio socket through an emulated Intel HDA device.
- Keyboard and pointer events reach QEMU through the compositor. The guest has virtio keyboard and tablet devices, plus USB ones that Setup uses before the virtio driver is installed.
- The guest's `viogpu3d` driver, from UTM's guest tools, sends Direct3D 11 commands over virtio-gpu. virglrenderer's Neptune context runs them on DXVK, which translates them to Vulkan.
- The launcher, `bin/cha-windows`, writes the answer file to a virtual floppy, runs Setup, and installs the drivers on first logon from `unattend/firstlogon.ps1`. Every launch after that boots the disk with 3D on.

## Configuration

Set these as variables on a custom environment in the portal:

| Variable | Default | Meaning |
|---|---|---|
| `CHA_WINDOWS_ISO` | the newest `*.iso` in the shared folder | The installer to use |
| `CHA_WINDOWS_CPUS` | half the node's threads | Virtual CPUs |
| `CHA_WINDOWS_RAM` | `8G` | Guest memory; keep it below the container's cap |
| `CHA_WINDOWS_DISK` | `128G` | Size of the sparse virtual disk, set at install |
| `CHA_WINDOWS_USER`, `CHA_WINDOWS_PASSWORD` | `cha`, `cha` | The local account, set at install |
| `CHA_WINDOWS_EDITION` | `Windows 11 Pro` | The edition Setup installs |
| `CHA_WINDOWS_LOCALE`, `CHA_WINDOWS_TIMEZONE` | `en-US`, `UTC` | Set at install |
| `CHA_WINDOWS_STOP_GRACE` | `75` | Seconds Windows gets to shut down before QEMU is stopped |
| `CHA_WINDOWS_SLOT_ZAP_ALL` | unset | `off` makes freeing GPU memory in the guest faster. Needs Linux 6.13 or later on the node, or QEMU won't start |

## Building

```bash
docker build -t ghcr.io/ban-red/cha-env-windows:dev .
```

The build compiles three projects from source, pinned in the `Dockerfile`, and applies the patches in [patches/](patches/README.md):

| Project | Source | Licence |
|---|---|---|
| QEMU 10.0 | [utmapp/qemu](https://github.com/utmapp/qemu), branch `dev/neptune-linux` | GPL-2.0 |
| virglrenderer | [utmapp/virglrenderer](https://github.com/utmapp/virglrenderer), branch `dev/neptune-linux` | MIT |
| DXVK | [osy/dxvk](https://github.com/osy/dxvk), branch `master` | zlib |

The build takes about 10 minutes on 16 threads, and the image is about 1.1 GB. The runtime is based on Cha's environment base image.

## Troubleshooting

- `cha-windows doctor` checks inside the image for KVM, the render node, udmabuf, Vulkan and the QEMU build.
- QEMU's output is in `~/windows/logs/qemu.log`. If Windows crashes, the environment stops with the stop code.
- `CHA_WINDOWS_DISPLAY=headless` runs without a window and writes a screenshot to `~/windows/logs/screen.ppm` every few seconds. That only works before the 3D driver is active. `CHA_WINDOWS_QEMU_ARGS` adds QEMU arguments.

## Licence

The launcher, answer file, first-logon script, Dockerfile and documentation are licensed under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE).

The files in `patches/` change other projects and carry those projects' licences: zlib for DXVK, MIT for virglrenderer, GPL-2.0-or-later for QEMU.

Windows itself is not included. The answer file uses Microsoft's generic Windows 11 Pro installation key, which installs Windows but doesn't activate it. UTM's guest tools are downloaded on first launch and checked against a pinned SHA-256; they are not redistributed.

A published image contains QEMU, which is GPL-2.0. Its corresponding source is this repository plus the pinned upstream commits.

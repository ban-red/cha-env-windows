# Testing notes

What was tested, on what, and what turned up. Most findings led to a change in the launcher, the answer file or a patch.

## Test machine

- Intel Core i7-13700K, 62 GB RAM, NVIDIA GeForce RTX 4090 with driver 595.71
- Ubuntu with Linux 6.17, Docker 29.1
- Cha Portal 0.3.0 and 0.4.0, with the node agent and streamer on the same machine
- A MacBook running Chrome, on the same LAN, as the viewer

## Results

| Area | Result |
|---|---|
| Image build | Works; about 10 minutes, 1.1 GB |
| Unattended install, Windows 11 26H2 | Works; 13 to 22 minutes depending on load |
| Unattended install, Windows 11 23H2 | Installs, but crashes when the 3D driver starts |
| 3D (viogpu3d on Neptune) | Works with the patches in `patches/` |
| Streaming through Cha | Works, over WebRTC and WebTransport |
| Keyboard and mouse | Work; virtio devices after the first logon |
| Resizing | Follows the player window after 10 to 20 seconds |
| Sound | Windows opens a stream on Cha's sound server; not listened to yet |
| Stopping | Windows shuts down cleanly in 10 to 15 seconds |
| Gamepads, clipboard, relative mouse | Not implemented |

Measured in Edge with the WebGL Aquarium at 2304×1440:
- **Frame rate:** 57 to 59 fps from 500 to 30,000 fish.
- **Encoding:** HEVC took about 1.8 ms a frame, at about 28 Mbit/s.
- **Load:** the GPU stayed at 12% and the VM used about 5 CPU cores. The limit is the guest's 60 Hz display, not the GPU or Cha.

## Findings

**Secure Boot firmware.** Ubuntu's `OVMF_CODE_4M.secboot.fd` hangs at Windows Setup's "Press any key to boot from CD" unless QEMU also enables SMM and secure flash. The launcher uses the plain build, and the answer file tells Setup to skip its Secure Boot and TPM checks.

**The CD prompt.** "Press any key to boot from CD or DVD" appears for 5 seconds, at a time that depends on the firmware and the ISO: more than 30 seconds in for a 9 GB ISO. The launcher presses a key for two minutes. Windows 11 26H2's Setup has a focused Cancel button, and pressing space activates it, so the launcher presses `x`.

**Installing the display driver during Setup.** Binding viogpu3d to Setup's plain `virtio-vga` display hangs the guest. The first-logon script copies the driver and installs it from a RunOnce entry at the next logon, which is the first boot with the 3D device.

**Windows 11 23H2.** With viogpu3d, 23H2 stops with `0x7E SYSTEM_THREAD_EXCEPTION_NOT_HANDLED`, an access violation in `dxgmms2.sys` at offset `0xbeea0`, the same every time. 26H2 works. The faulting module was found by reading the paused guest's memory over QMP: walking back from the faulting address to the module's PE header, then reading its PDB name.

**Guest crashes looked like clean exits.** Windows reports a bugcheck through Hyper-V's crash registers, and QEMU's default panic action shuts down with exit status 0. The launcher sets `-action panic=exit-failure` and logs guest errors, so a crash fails the environment and shows the stop code.

**Recovery screen.** A container stopped while Windows boots makes Windows open its Recovery screen on the next start, which waits for input nobody gives. The first-logon script turns automatic recovery off.

**Shared surfaces on NVIDIA.** Every surface Windows' compositor created failed to export, and viogpu3d stopped with Code 43, for two reasons:
- **A8 surfaces:** NVIDIA offers no DRM format modifier for `VK_FORMAT_A8_UNORM`, so those surfaces couldn't be shared.
- **Scanout surfaces:** the guest asks for linear exports of them, and NVIDIA can't render to a linear layout.

DXVK patches 0001 and 0003 fix these.

**Black picture.** After that, the stream was black. QEMU described every scanout buffer as linear, and the render server never told it the real layout. The virglrenderer patch carries the layout (the DRM modifier) to QEMU, and QEMU patch 0001 uses it.

**Dropped and repeated keys.** Keys reached QEMU in order, but Windows lost some, and a lost key release made Windows repeat that key. QEMU's USB keyboard queues 16 events and drops the rest; a burst of input overflows it. QEMU patch 0002 raises the queue to 256. Virtio keyboard and tablet devices, used once their driver is installed, avoid the USB queue entirely.

**60 Hz.** On a 120 fps stream Windows still runs at 60 Hz; `Win32_VideoController` reports 60 as both minimum and maximum. QEMU passes the host's refresh rate (240 Hz) into the display's EDID, so the limit is in the guest driver.

**Shutdown time.** With Edge running WebGL, Windows didn't finish shutting down within 25 seconds. The first-logon script makes Windows end applications instead of waiting on them. The launcher now waits 75 seconds, and Cha gives `vm` environments 90.

**A node freeze.** The node once froze about three minutes into an install, with an 8 GB guest, `cache=writeback` and a node that had just written about 140 GB of other files. The cause wasn't found. Since then:
- **Disk:** QEMU uses `cache=none`, so the guest's writes bypass the host's page cache.
- **Memory:** Cha caps the container's memory.

There has been no recurrence in the installs and boots since.

## Useful techniques

- **Reading output from the guest without the 3D display:** add `-serial file:…` through `CHA_WINDOWS_QEMU_ARGS`, type a command into the Run box over QMP `send-key`, and redirect its output to `COM1`.
- **Screenshots of the 3D display:** QMP `screendump` can't read it, but a frame decoded by Cha's player can be drawn to a canvas.

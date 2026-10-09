# Patches

Changes to the pinned sources, applied by the `Dockerfile` with `git apply`, one at a time in name order. Each one is meant to go upstream; drop a patch once the pinned commit includes it. Each patch carries the licence of the project it changes.

## DXVK (osy/dxvk, zlib)

| Patch | What it fixes |
|---|---|
| `0001-dxgi-Map-A8_UNORM-to-R8_UNORM…` | NVIDIA offers no DRM format modifier for `VK_FORMAT_A8_UNORM`, so A8 textures shared as dma-bufs fail. Windows' compositor creates such textures when the display driver starts. Maps A8 to R8 with a swizzle, as DXVK already does where A8 lacks features |
| `0002-dxvk-Pass-the-view-format-list…` | The dma-buf modifier query for a mutable-format image left out the image's view format list, so the driver answered for a different image than the one created |
| `0003-dxvk-Negotiate-a-modifier…` | A texture flagged for a linear export may only use the linear layout, which NVIDIA can't render to. Windows' scanout surfaces carry that flag. Falls back to a tiled modifier and logs it once |

## virglrenderer (utmapp/virglrenderer, MIT)

| Patch | What it fixes |
|---|---|
| `0001-neptune-carry-an-exported-blob-s-DRM-modifier…` | A shared texture reaches QEMU as a bare dma-buf with its format but not its layout. Carries the DRM modifier from the render server to the resource and returns it from the export query. Also zero-initialises a struct that contexts fill only partly |

## QEMU (utmapp/qemu, GPL-2.0-or-later)

| Patch | What it fixes |
|---|---|
| `0001-virtio-gpu-virgl-scan-out-a-blob-with-its-DRM-modifier` | Blob scanouts were always described as linear, so a tiled buffer displayed black. Asks virglrenderer for the modifier and passes it to the display |
| `0002-hw-input-hid-queue-up-to-256-events…` | The USB HID queue held 16 events and dropped the rest; a burst of keys lost a release and Windows repeated the key |

The QEMU patches don't carry a `Signed-off-by` line. Add one when submitting them upstream.

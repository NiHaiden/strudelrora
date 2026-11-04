# Strudelrora

This image is based off of Aurora-DX Stable and installs Steam and 1Password for myself. This image is mostly intended to be consumed by myself, but feel free to use it.

Name is based on Apfelstrudel, yes I am very creative.

## LibrePods

[LibrePods](https://github.com/librepods-org/librepods) (AirPods controls: battery, listening modes, ear detection, etc.) is compiled from source on every image build from the upstream `linux/rust` branch (the Rust rewrite upstream recommends), because the published Linux release is very old. CI resolves the branch's latest commit and passes it as the `LIBREPODS_REF` build-arg; the commit baked into an image is recorded in `/usr/share/librepods/commit`.

The image also enables [VendorID spoofing](https://github.com/librepods-org/librepods#vendorid-spoofing) by setting `DeviceID = bluetooth:004C:0000:0000` in `/etc/bluetooth/main.conf`. This makes the machine identify as an Apple device to every Bluetooth peer. You may need to re-pair your AirPods once, since they cache this value. If you've edited `/etc/bluetooth/main.conf` yourself, bootc keeps your copy and you'll need to add the line manually.

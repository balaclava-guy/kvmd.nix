# kvmd.nix

NixOS packaging and modules for [PiKVM](https://pikvm.org)'s
[`kvmd`](https://github.com/pikvm/kvmd). Run a PiKVM on a stock NixOS Raspberry
Pi.

Not affiliated with the PiKVM project.

## Status

Three variants for the Raspberry Pi 4 are available:

- **`v2-hdmi-rpi4`**: CSI capture via the TC358743 HDMI→CSI bridge.
- **`v2-hdmiusb-rpi4`**: USB UVC capture dongle (e.g. MS2109), on any USB port.
- **`v3-hdmi-rpi4`**: official PiKVM V3 Steel / V3 HAT, including OLED and fan.

All build a flashable SD image. The V2 variants have been tested on real
hardware; V3 still needs physical validation.

## Outputs

- `packages.${system}.{default,kvmd,kvmd-fan}`: kvmd and its fan controller
  (`default` is `kvmd`).
- `nixosModules.{default,kvmd}`: the daemon set (kvmd +
  otg/media/pst/janus/nginx and optional vnc/ipmi/nbd/webterm); `default` is
  `kvmd`.
- `nixosModules.<variant>` (`v2-hdmi-rpi4`, `v2-hdmiusb-rpi4`, `v3-hdmi-rpi4`):
  the Pi 4 hardware profile (kernel patches, dwc2, capture); sets
  `services.kvmd.variant`, so pair it with `nixosModules.kvmd`.
- `nixosConfigurations.<variant>`: ready-to-flash SD images.

## Quick start

Build an SD image:

```sh
nix build github:aostanin/kvmd.nix#nixosConfigurations.v2-hdmi-rpi4.config.system.build.sdImage
```

Or compose it into your own host:

```nix
{
  inputs.kvmd.url = "github:aostanin/kvmd.nix";

  outputs = { nixpkgs, kvmd, ... }: {
    nixosConfigurations.mykvm = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        kvmd.nixosModules.default
        kvmd.nixosModules.v2-hdmi-rpi4
        {
          services.kvmd = {
            enable = true;

            ocrLanguages = ["eng" "rus"];

            htpasswdFile = "/run/secrets/kvmd-htpasswd";
            vnc = {
              enable = true;
              passwordFile = "/run/secrets/kvmd-vncpasswd";
            };
            ipmi = {
              enable = true;
              passwordFile = "/run/secrets/kvmd-ipmipasswd";
            };

            overrideConfig = {
              kvmd.streamer.resolution.default = "1280x720";
            };
          };
        }
      ];
    };
  };
}
```

## PiKVM V3 Steel

Use a Raspberry Pi 4 Model B with the official V3 HAT. The V3 profile enables
TC358743 CSI capture, native USB HID and virtual media, ATX, the USB breaker,
Janus/WebRTC, NBD, the Steel fan, OLED, PCF8563 RTC and RTC watchdog. It uses
upstream kvmd's V3 configuration and plugins, including EZCOO.

Build from this checkout on an aarch64 Linux machine (or with an aarch64 Linux
Nix builder):

```sh
nix build .#nixosConfigurations.v3-hdmi-rpi4.config.system.build.sdImage
```

Decompress the image in `result/sd-image/` and flash it to a spare SD card with
Raspberry Pi Imager's **Use custom** option. Flashing erases the selected card.
Keep the original PiKVM OS card and back up settings, credentials and virtual
media before migrating. PiKVM OS packages and its read-only-root update commands
are not used on NixOS. Connect Ethernet; the example image uses DHCP and
advertises `https://pikvm.local/` (or use its DHCP address). See the insecure
first-boot credentials below before connecting it to a shared network.

For an existing NixOS configuration, replace the V2 hardware module in the
example above with `kvmd.nixosModules.v3-hdmi-rpi4`. Merely setting
`services.kvmd.variant` does not configure the HAT. Reboot after changing
hardware profiles or USB gadget settings. Firmware overlays are applied at build
time to the generation's device tree; keep `useGenerationDeviceTree` enabled.
Retain a working generation and local serial/SD-card access for recovery.

The following defaults can be changed when using a bare HAT without the Steel
accessories:

```nix
services.kvmd.fan.enable = false;
services.kvmd.oled.enable = false;
```

The fan runs the upstream controller on GPIO 12 with hardware PWM, a 45–75 °C
control range and 3 °C hysteresis. Its default idle speed is 25%, rising to 75%
across that range and 100% above it; V3 has no tachometer. Use
`services.kvmd.fan.configFile` for a custom upstream INI file. The OLED is an
SSD1306, 128×32, at I²C bus 1 address 0x3c. It displays network information and
receives health, uptime and client counts through kvmd's authenticated local
socket. Display settings remain available under `overrideConfig.oled`.

The PCF8563 at I²C address 0x51 supplies the UTC hardware clock and watchdog
alarm. The watchdog refreshes a five-minute alarm every 30 seconds. As on PiKVM
OS, stopping the watchdog does **not** disarm it; a halted unit may reset while
power remains connected. To deliberately disarm it, stop `kvmd-watchdog`, then
run `kvmd-watchdog cancel` as root. Do not use another RTC alarm consumer at the
same time. The supercapacitor needs time to charge after a long power loss.

The HAT serial ports use `/dev/ttyAMA0` on GPIO 14/15 at 115200 baud for the
NixOS console. Bluetooth is disabled to free that UART. To use the port for a
server console instead, remove its `console=ttyAMA0,115200` kernel parameter and
disable `serial-getty@ttyAMA0` in your host configuration. EZCOO normally uses
its own USB serial management port; translate the upstream
[EZCOO configuration](https://docs.pikvm.org/ezcoo/) into
`services.kvmd.overrideConfig.kvmd.gpio`, preferably using
`/dev/serial/by-id/…`. The kvmd user already belongs to `dialout`.

HDMI I²S capture is configured, but the upstream V3 EDID leaves audio disabled.
For [two-way audio](https://docs.pikvm.org/audio/), retain the HAT audio jumpers
and supply an audio-enabled EDID through `services.kvmd.edidHex`. Edit a
writable copy with `kvmd-edidconf --edid=/path/to/copy.hex --set-audio=yes`,
then reference that file in Nix. Optional USB microphone emulation is enabled
with:

```nix
services.kvmd.overrideConfig.otg.devices.audio.enabled = true;
```

Reboot after enabling the microphone. USB endpoint limits still apply. SPI/AUM
extension boards, USB webcam emulation and PiKVM OS boot provisioning/update
scripts are outside this hardware profile. There is no separate V3 power-sense
GPIO in the upstream platform configuration. The USB-breaker control remains the
upstream **System → USB** control; do not reassign GPIO 5. ATX uses upstream
GPIO 24/22 inputs (non-inverted, 100 ms debounce) and 23/27 outputs. Leave the
HAT's reserved GPIOs and jumpers as documented in the
[V3 pinout](https://docs.pikvm.org/v3/#io-ports-and-jumpers).

### V3 validation checklist

V3 has not been tested on physical hardware. Before relying on remote access:

- Boot with Ethernet and verify local/serial recovery and the DHCP address.
- Check `/dev/kvmd-video`, EDID and DV timings; test HDMI hotplug, MJPEG and
  H.264/WebRTC at several resolutions.
- Test keyboard, absolute/relative mouse and reconnect after host reboot.
- Attach/detach CD-ROM and writable flash images; test NBD remote media.
- Check ATX power/HDD LEDs, power, long-press and reset; toggle the USB breaker.
- Check fan response to load, OLED network/health updates and loss of network.
- Check RTC time after power loss and watchdog recovery with local access ready.
- Test serial console, EZCOO switching and optional HDMI/USB microphone audio.
- Reboot and shut down; check OLED messages, USB teardown and watchdog behavior.
- Verify rollback to a working NixOS generation and recovery using the original
  SD.

## Security

The `nixosConfigurations` ship **insecure defaults** for first boot. Before
putting a box on a network you must change:

- Root password (`pikvm`) and root SSH login.
- The kvmd web / VNC / IPMI credentials. These default to the **upstream example
  files** (`admin`/`admin`). Point them at your own:

```nix
services.kvmd.htpasswdFile      = "/run/secrets/kvmd-htpasswd";   # user:{SSHA512}…
services.kvmd.vnc.passwordFile  = "/run/secrets/kvmd-vncpasswd";  # plaintext, one per line
services.kvmd.ipmi.passwordFile = "/run/secrets/kvmd-ipmipasswd"; # login:password
```

## License

This repository's Nix code is MIT (see [LICENSE](LICENSE)). It only packages and
configures upstream software consumed as flake inputs:

- [`pikvm/kvmd`](https://github.com/pikvm/kvmd): GPL-3.0-or-later, © Maxim
  Devaev; the resulting `kvmd` package is therefore GPL-3.0-or-later.
- [`pikvm/packages`](https://github.com/pikvm/packages): kernel and janus.js
  patches applied to the RPi kernel / Janus assets.

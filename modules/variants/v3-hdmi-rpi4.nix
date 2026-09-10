{
  config,
  lib,
  ...
}: {
  imports = [./hdmi-rpi4.nix];

  services.kvmd = {
    variant = "v3-hdmi-rpi4";
    edidHex = lib.mkDefault "${config.services.kvmd.configsDir}/kvmd/edid/v3.hex";
    fan.enable = lib.mkDefault true;
    oled.enable = lib.mkDefault true;
    watchdog.enable = lib.mkDefault true;
    janus.enable = lib.mkDefault true;
    nbd.enable = lib.mkDefault true;
  };

  hardware.raspberry-pi."4".i2c1.enable = true;
  hardware.raspberry-pi.configtxt = {
    settings.all = {
      gpu_mem = 128;
      hdmi_force_hotplug = true;
      # The onboard analog audio driver also uses the PWM hardware.
      dtparam = ["audio=off"];
    };
    # Route the bootloader console too; the generation overlay below
    # preserves that routing when U-Boot replaces the firmware device tree.
    deviceTreeOverlays.all = lib.mkAfter [{disable-bt = {};}];
  };
  boot.kernelModules = ["rtc-pcf8563"];
  boot.kernelParams = ["console=ttyAMA0,115200"];
  time.hardwareClockInLocalTime = false;

  # Keep HAT peripherals in the generation's device tree, like the CSI
  # and DWC2 overlays. Firmware-only overlays are lost when U-Boot loads it.
  hardware.deviceTree.overlays = [
    {
      name = "pikvm-v3-hat";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "brcm,bcm2711";

          fragment@0 {
            target = <&i2c1>;
            __overlay__ {
              #address-cells = <1>;
              #size-cells = <0>;
              rtc@51 {
                compatible = "nxp,pcf8563";
                reg = <0x51>;
                wakeup-source;
              };
            };
          };

          fragment@1 {
            target = <&led_act>;
            __overlay__ {
              gpios = <&gpio 13 0>;
            };
          };

          fragment@2 {
            target = <&uart0>;
            __overlay__ {
              pinctrl-names = "default";
              pinctrl-0 = <&uart0_gpio14>;
              status = "okay";
            };
          };

          fragment@3 {
            target = <&uart1>;
            __overlay__ {
              status = "disabled";
            };
          };

          fragment@4 {
            target = <&bt>;
            __overlay__ {
              status = "disabled";
            };
          };

          fragment@5 {
            target-path = "/aliases";
            __overlay__ {
              serial0 = "/soc/serial@7e201000";
              serial1 = "/soc/serial@7e215040";
            };
          };
        };
      '';
    }
    {
      # Same bindings as Raspberry Pi's tc358743-audio overlay. The V3
      # EDID leaves audio disabled by default; users can supply an audio EDID.
      name = "tc358743-audio";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "brcm,bcm2711";

          fragment@0 {
            target = <&i2s_clk_consumer>;
            __overlay__ {
              status = "okay";
            };
          };

          fragment@1 {
            target-path = "/";
            __overlay__ {
              tc358743_codec: tc358743-codec {
                #sound-dai-cells = <0>;
                compatible = "linux,spdif-dir";
                status = "okay";
              };
            };
          };

          fragment@2 {
            target = <&sound>;
            __overlay__ {
              compatible = "simple-audio-card";
              simple-audio-card,format = "i2s";
              simple-audio-card,name = "tc358743";
              simple-audio-card,bitclock-master = <&dailink0_master>;
              simple-audio-card,frame-master = <&dailink0_master>;
              status = "okay";

              simple-audio-card,cpu {
                sound-dai = <&i2s_clk_consumer>;
                dai-tdm-slot-num = <2>;
                dai-tdm-slot-width = <32>;
              };
              dailink0_master: simple-audio-card,codec {
                sound-dai = <&tc358743_codec>;
              };
            };
          };
        };
      '';
    }
  ];
}

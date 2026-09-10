{
  config,
  lib,
  pkgs,
  kvmdPackages,
  ...
}: let
  cfg = config.services.kvmd;
in {
  options.services.kvmd.fan = {
    enable = lib.mkEnableOption "the PiKVM fan controller";
    package = lib.mkOption {
      type = lib.types.package;
      default = kvmdPackages.${pkgs.stdenv.hostPlatform.system}.kvmd-fan;
      defaultText = lib.literalExpression "the flake's kvmd-fan package";
      description = "The fan controller package to use.";
    };
    configFile = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.configsDir}/kvmd/fan/v3-hdmi.ini";
      defaultText = lib.literalExpression ''"''${package}/share/kvmd/configs.default/kvmd/fan/v3-hdmi.ini"'';
      description = "Fan controller INI configuration.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.fan.enable) {
    systemd.services.kvmd-fan = {
      description = "PiKVM - A small fan controller daemon";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service" "systemd-tmpfiles-setup.service"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        # WiringPi maps the Pi's PWM registers through /dev/mem.
        ExecStart = "${lib.getExe cfg.fan.package} --config=${cfg.fan.configFile}";
        TimeoutStopSec = 3;
      };
    };
  };
}

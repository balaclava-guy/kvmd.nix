{
  imports = [./rpi4.nix];

  hardware.raspberry-pi."4".tc358743.enable = true;

  boot.kernelModules = ["tc358743"];
  boot.kernelParams = ["cma=192M"];
}

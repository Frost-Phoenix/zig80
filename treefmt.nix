{ ... }:
{
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "*.md"
    "*.png"
    "*.lock"
    "*.zon2json-lock"
    "LICENSE"
  ];

  programs = {
    nixfmt.enable = true;
    zig.enable = true;
    shfmt.enable = true;
  };

  settings.formatter = {
    nixfmt.options = [
      "-sv"
      "-w"
      "80"
    ];
    shfmt.options = [
      "-w"
      "-p"
      "-s"
      "-i"
      "4"
      "-ci"
    ];
  };
}

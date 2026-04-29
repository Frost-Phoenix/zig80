{ ... }:
{
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "*.md"
    "*.lock"
    "LICENSE"
  ];

  programs = {
    zig = {
      enable = true;
    };

    nixfmt = {
      enable = true;

      strict = true;
    };

    shfmt = {
      enable = true;

      indent_size = 4;
      simplify = true;
    };
  };

  settings.formatter = {
    shfmt.options = [
      "-ci"
      "-sr"
    ];
  };
}

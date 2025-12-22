{
  description = "Flake configuration for am-zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      utils,
      ...
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        DevEnv = pkgs.symlinkJoin {
          name = "dev-env";
          paths = with pkgs; [
            zig

            # simulators and tools
            qemu
            spike
            dtc

            # scripts dependencies
            nushell
            just
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ DevEnv ];
        };
      }
    );
}

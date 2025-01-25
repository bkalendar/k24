{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = inputs: let
    system = "aarch64-linux";
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        inputs.zig.packages.${system}.master
        pkgs.wasm-tools
        pkgs.wit-bindgen
        pkgs.deno
        pkgs.fish
      ];

      shellHook = ''
        exec fish
      '';
    };
  };
}

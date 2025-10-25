{
  description = "Nix flake for MXE (M cross environment)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      metadataPath = ./metadata/mxe-packages.json;
      metadata = builtins.fromJSON (builtins.readFile metadataPath);
      defaultTarget = "x86_64-w64-mingw32.static";
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        };
        mxeLib = import ./nix/lib.nix { inherit metadata; lib = pkgs.lib; };
        mxePackages = mxeLib.mkPackageSet pkgs;
      in {
        packages = {
          mxePackages = mxePackages;
          default = mxePackages.${defaultTarget}.cc;
        };

        devShells.default = pkgs.mkShell {
          packages = mxeLib.nativeInputs pkgs;
        };

        checks.metadata = pkgs.runCommand "mxe-metadata-check" {
          buildInputs = [ pkgs.python3 pkgs.git pkgs.diffutils ];
        } ''
          mkdir -p $TMPDIR/out
          python3 ${./tools/export-mxe-metadata.py} --compact -o $TMPDIR/out/mxe-packages.json
          diff -u ${metadataPath} $TMPDIR/out/mxe-packages.json
          mkdir -p $out
          cp ${metadataPath} $out/mxe-packages.json
        '';
      }
    ) // {
      overlay = final: prev:
        let
          mxeLib = import ./nix/lib.nix { inherit metadata; lib = prev.lib; };
        in {
          mxe = {
            lib = mxeLib;
            metadata = metadata;
            packages = mxeLib.mkPackageSet final;
            mkPackage = args: mxeLib.mkMxePackage ({ pkgs = final; } // args);
            nativeInputs = mxeLib.nativeInputs final;
            defaultTarget = defaultTarget;
          };
        };

      overlays.default = self.overlay;
    };
}


{
  description = "Secret Service provider and utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, crane, rust-overlay, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        inherit (pkgs) lib;

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        # Source filtering
        # Include service files and other assets if needed
        src = lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            (lib.hasSuffix ".rs" path) ||
            (lib.hasSuffix ".toml" path) ||
            (lib.hasSuffix ".lock" path) ||
            (lib.hasSuffix ".xml" path) ||
            (lib.hasSuffix ".py" path) ||
            (lib.hasSuffix ".pyi" path) ||
            (lib.hasSuffix "py.typed" path) ||
            (lib.hasSuffix ".md" path) ||
            (lib.hasSuffix ".desktop.in" path) ||
            (lib.hasSuffix ".portal.in" path) ||
            (lib.hasSuffix ".service.in" path) ||
            (lib.hasInfix "/fixtures/" path) ||
            (lib.hasInfix "/data/" path) ||
            (craneLib.filterCargoSources path type);
        };

        commonArgs = {
          inherit src;
          pname = "oo7";
          version = "0.6.0-alpha";
          strictDeps = true;

          nativeBuildInputs = with pkgs; [
            pkg-config
            gettext
            python3
            dbus # Added for tests if run manually
          ];

          buildInputs = with pkgs; [
            openssl
            python3
          ] ++ lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          ];
        };

        # Build the workspace
        oo7-workspace = craneLib.buildPackage (commonArgs // {
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          # Build all binaries and the PAM module
          cargoExtraArgs = "--workspace";

          # Integration tests require a running D-Bus session and a Secret Service
          # provider (like gnome-keyring or oo7-daemon itself), which are not
          # available in the Nix build sandbox.
          doCheck = false;

          postInstall = ''
            # Move the PAM module to the expected location
            mkdir -p $out/lib/security
            # The library name might be libpam_oo7.so or pam_oo7.so depending on target
            mv $out/lib/libpam_oo7.so $out/lib/security/pam_oo7.so || mv $out/lib/pam_oo7.so $out/lib/security/pam_oo7.so
            
            # Create a symlink for oo7 -> oo7-cli as in conda recipe
            ln -sf oo7-cli $out/bin/oo7
          '';
        });

        # Python package build using the root and maturin
        oo7-python = pkgs.python3.pkgs.buildPythonPackage {
          pname = "oo7-python";
          version = "0.6.0";
          format = "pyproject";

          src = src;

          nativeBuildInputs = with pkgs; [
            pkg-config
            rustToolchain
            pkgs.python3.pkgs.maturin
            pkgs.python3.pkgs.pip
          ];

          buildInputs = with pkgs; [
            openssl
          ];

          preBuild = ''
            cd python
          '';
        };

      in
      {
        packages = {
          default = oo7-workspace;
          oo7 = oo7-workspace;
          oo7-python = oo7-python;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ oo7-workspace ];
          nativeBuildInputs = with pkgs; [
            rustToolchain
            maturin
            python3
            python3Packages.pip
            pkg-config
          ];
          buildInputs = with pkgs; [
            openssl
            gettext
          ];
        };
      }
    );
}

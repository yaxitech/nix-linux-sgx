{
  description = "YAXI Linux SGX packages and modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";
    nixpkgs-sgx-psw.url = "github:veehaitch/nixpkgs/sgx-psw";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-sgx-psw, rust-overlay }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlay
          rust-overlay.overlay
        ];
      };
    in
    {
      overlay = final: prev: rec {
        sgx-psw = prev.callPackage "${nixpkgs-sgx-psw}/pkgs/os-specific/linux/sgx/psw" { };
        sgxs-tools = final.callPackage ./pkgs/sgxs-tools { };
        # Keep for compat
        intel-sgx.sdk = final.sgx-sdk;
        intel-sgx.psw = sgx-psw;
      };

      packages.${system} = {
        intel-sgx-sdk = pkgs.intel-sgx.sdk;
        intel-sgx-psw = pkgs.intel-sgx.psw;
        inherit (pkgs) sgxs-tools;
      };

      # By default, create a derivation from all output packages
      defaultPackage.${system} = pkgs.linkFarmFromDrvs "bundle" (builtins.attrValues self.packages.${system});

      nixosModules.sgx = {
        nixpkgs.overlays = [ self.overlay ];
        imports = [ "${nixpkgs-sgx-psw}/nixos/modules/services/security/aesmd.nix" ];
      };

      checks.${system}.nixpkgs-fmt = pkgs.runCommand "check-nix-format" { } ''
        ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
        mkdir $out #sucess
      '';

      devShell.${system} = pkgs.mkShell {
        name = "linux-sgx-devshell";

        nativeBuildInputs = with pkgs; [
          fish
          sgx-psw
          sgx-sdk
          sgxs-tools
        ];

        SGX_PSW = "${pkgs.intel-sgx.psw}";

        LD_LIBRARY_PATH = with pkgs; lib.makeLibraryPath [
          sgx-psw
          sgx-sdk
        ];

        shellHook = ''
          echo "SGX_SDK         = $SGX_SDK"
          echo "SGX_PSW         = $SGX_PSW"
          echo "LD_LIBRARY_PATH = $LD_LIBRARY_PATH"
        '';
      };
    };
}

{
  description = "YAXI Linux SGX packages and modules";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.nixpkgs-sgx.url = "github:veehaitch/nixpkgs/sgx-psw";

  outputs = { self, nixpkgs, nixpkgs-sgx }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      };
    in
    {
      overlay = final: prev: rec {
        sgx-sdk = prev.callPackage "${nixpkgs-sgx}/pkgs/os-specific/linux/sgx/sdk" { };
        sgx-psw = prev.callPackage "${nixpkgs-sgx}/pkgs/os-specific/linux/sgx/psw" { };
        # Keep for compat
        intel-sgx.sdk = sgx-sdk;
        intel-sgx.psw = sgx-psw;
      };

      packages.${system} = {
        intel-sgx-sdk = pkgs.intel-sgx.sdk;
        intel-sgx-psw = pkgs.intel-sgx.psw;
      };

      nixosModules.sgx = {
        nixpkgs.overlays = [ self.overlay ];
        imports = [ "${nixpkgs-sgx}/nixos/modules/security/sgx.nix" ];
      };

      checks.${system}.nixpkgs-fmt = pkgs.runCommand "check-nix-format" { } ''
        ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
        mkdir $out #sucess
      '';

      devShell.${system} = pkgs.mkShell {
        name = "linux-sgx-devshell";

        buildInputs = with pkgs; [
          intel-sgx.sdk
          intel-sgx.psw
          fish
        ];

        SGX_SDK = "${pkgs.intel-sgx.sdk}";
        SGX_PSW = "${pkgs.intel-sgx.psw}";

        shellHook = ''
          source $SGX_SDK/share/bin/environment

          export SGX_SDK_SAMPLES=$(mktemp -d)
          cp --no-preserve=all -r $SGX_SDK/share/SampleCode $SGX_SDK_SAMPLES/

          echo "SGX_SDK         = $SGX_SDK"
          echo "SGX_SDK_SAMPLES = $SGX_SDK_SAMPLES (rw)"
          echo "SGX_PSW         = $SGX_PSW"
          echo "LD_LIBRARY_PATH = $LD_LIBRARY_PATH"

          trap "rm -rf $SGX_SDK_SAMPLES && echo 'Cleaned up samples dir'" EXIT

          exec fish
        '';
      };
    };
}

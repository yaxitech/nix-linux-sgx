{
  description = "YAXI Linux SGX packages and modules";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      };
    in
    {
      overlay = final: prev:
        {
          intel-sgx = final.callPackage ./pkgs/intel-sgx { };
        };

      packages.${system} =
        {
          intel-sgx-sdk = pkgs.intel-sgx.sdk;
          intel-sgx-psw = pkgs.intel-sgx.psw;
        };

      nixosModules.sgx =
        { ... }:
        {
          nixpkgs.overlays = [ self.overlay ];
          imports = [ ./nixos/modules/sgx.nix ];
        };

      checks.${system}.nixpkgs-fmt = pkgs.runCommand "check-nix-format" { } ''
        ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
        mkdir $out #sucess
      '';

      devShell.${system} = pkgs.mkShell
        {
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

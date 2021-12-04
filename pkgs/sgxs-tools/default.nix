{ lib
, fetchFromGitHub
, libclang
, openssl
, pkg-config
, protobuf
, rust-bin
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  pname = "sgxs-tools";
  version = "0.8.3";

  src = fetchFromGitHub {
    owner = "fortanix";
    repo = "rust-sgx";
    rev = "sgxs-tools_v${version}";
    hash = "sha256-/cMuzsYxG1g6IEjT7Ajjvf9M5px63GK67EeR4Zq+emc=";
  };

  cargoSha256 = "sha256-cBFj+GijXcfJ1uUTFHrCrR7b4xqolTCdjucV1lc10O4=";

  cargoPatches = [
    # Cargo.lock is outdated
    ./Cargo-lock.patch
  ];

  nativeBuildInputs = [
    rust-bin.nightly.latest.minimal
    pkg-config
    protobuf
  ];

  buildInputs = [
    openssl
  ];

  cargoBuildFlags = [
    "--package ${pname}"
  ];

  doCheck = false;

  meta = with lib; {
    description = "Utilities for working with the SGX stream format";
    homepage = "https://github.com/fortanix/rust-sgx";
    license = licenses.mpl20;
    maintainers = with maintainers; [ veehaitch ];
    platforms = [ "x86_64-linux" ];
  };
}

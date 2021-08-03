{ callPackage
, coreutils
, fetchFromGitHub
, file
, glibc
, lib
, stdenv
, ...
}:
let
  version = "2.13";
  src = fetchFromGitHub {
    owner = "intel";
    repo = "linux-sgx";
    rev = "sgx_${version}";
    sha256 = "sha256-YEnWyLwp5se4q04sgKCar87GvNFn1Pl4Z6NH2PZDhmk=";
    # TODO: Enable to replace .gitmodules from ./deps.nix
    fetchSubmodules = false;
  };

  deps = callPackage ./deps.nix { inherit version; };
  prebuilts = deps.prebuilts;
  sdk = callPackage ./sdk.nix { inherit version; };
  openmpPatched = deps.openmp.overrideAttrs (old: {
    patches = [ "${src}/external/openmp/0001-Enable-OpenMP-in-SGX.patch" ];
  });
  permissionsFix = ''
    echo "Fixing permissions of external/dcap_source/"
    find external/dcap_source/ -type f -exec chmod 644 {} \;
    find external/dcap_source/ -type d -exec chmod 755 {} \;

    echo "Fixing permissions of external/openmp/openmp_code/"
    find external/openmp/openmp_code/ -type f -exec chmod 644 {} \;
    find external/openmp/openmp_code/ -type d -exec chmod 755 {} \;

    echo 'Fixing permissions of external/ippcp_internal/lib/linux/intel64/*/libippcp.a'
    chmod 644 external/ippcp_internal/lib/linux/intel64/*/libippcp.a
  '';
in
stdenv.mkDerivation {
  pname = "intel-sgx-repo-prepared";
  inherit version src;

  postUnpack = ''
    echo "Copying DCAP source (including prebuilt)"
    cp -r ${deps.dcap}/. $sourceRoot/external/dcap_source/

    echo "Copying SGX SSL source"
    chmod 755 $sourceRoot/external/dcap_source/QuoteVerification
    cp -r ${deps.sgxssl}/. $sourceRoot/external/dcap_source/QuoteVerification/sgxssl/

    echo "Copying OpenSSL source"
    chmod 755 $sourceRoot/external/dcap_source/QuoteVerification/sgxssl/openssl_source
    cp -r ${deps.openssl}/. $sourceRoot/external/dcap_source/QuoteVerification/sgxssl/openssl_source

    echo "Copying DNNL source"
    cp -r ${deps.dnnl}/. $sourceRoot/external/dnnl/dnnl

    echo "Copying IPP crypt source"
    cp -r ${deps.ipp-crypto}/. $sourceRoot/external/ippcp_internal/ipp-crypto

    echo "Copying OpenMP source"
    cp -r ${openmpPatched}/. $sourceRoot/external/openmp/openmp_code/

    echo "Copying prebuilts to source root"
    cp -r ${prebuilts.binutils}/. $sourceRoot/
    cp -r ${prebuilts.ae}/. $sourceRoot/
    cp -r ${prebuilts.optimizedLibs}/. $sourceRoot/
  '';

  postPatch = ''
    echo "Patch OpenMP Makefile to use our already patched version"
    substituteInPlace external/openmp/Makefile \
      --replace 'git clone -b svn-tags/RELEASE_801  https://github.com/llvm-mirror/openmp.git --depth 1 $(OMP_DIR)' \
                'echo "Patched out"' \
      --replace 'cd openmp_code && git apply ../0001-Enable-OpenMP-in-SGX.patch && cd ..' \
                'echo "Patched out"'

    echo "Patching out downloading of prebuilts"
    substituteInPlace Makefile \
      --replace './external/dcap_source/QuoteGeneration/download_prebuilt.sh' \
                'echo "Patched out."' \
      --replace './download_prebuilt.sh' \
                'echo "Patched out."'

    echo "Always use Nix binutils"
    substituteInPlace buildenv.mk \
      --replace 'ifneq ($(origin NIX_PATH), environment)' \
                'ifneq (1,1)' \
      --replace '$(ROOT_DIR)/external/toolset/nix/' \
                '${prebuilts.binutils}/external/toolset/nix/'

    echo "Fixing FSH paths"
    substituteInPlace buildenv.mk \
      --replace '/bin/cp' \
                '${coreutils}/bin/cp' \

    substituteInPlace sdk/gperftools/gperftools-2.7/src/pprof \
      --replace '/usr/bin/file' \
                '${file}/bin/file'

    substituteInPlace psw/ae/aesm_service/source/CMakeLists.txt \
      --replace '/usr/bin/getconf' \
                '${glibc.bin}/bin/getconf'

    echo "Running permissions fix just to see if it works. You have to call this in your derivation."
    ${permissionsFix}
  '';


  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir $out
    cp -r ./. $out/

    runHook postInstall
  '';

  inherit permissionsFix;

  meta = with lib; {
    homepage = "https://github.com/intel/linux-sgx";
    description = "Intel SGX GitHub repository with prepared sources";
    platforms = platforms.linux;
    license = licenses.free;
    maintainers = with maintainers; [ veehaitch ];
  };
}

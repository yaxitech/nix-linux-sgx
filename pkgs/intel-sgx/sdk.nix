{ autoconf
, automake
, binutils
, bison
, callPackage
, cmake
, file
, flex
, gcc
, gdb
, gnum4
, gnumake
, lib
, libtool
, linux
, ncurses
, ocaml
, ocamlPackages
, openssl
, perl
, python2
, stdenv
, texinfo
, validatePkgConfig
, which
  # Whether to build the SGX SDK with debug information. Adds a `-debug`
  # suffix to the derivation name, if `true`.
, debug ? false
}:
let
  deps = callPackage ./deps.nix { };
  repoPrepared = callPackage ./repo-prepared.nix { };
  installer = stdenv.mkDerivation {
    pname = "intel-sgx-sdk-installer" + lib.optionalString debug "-debug";
    version = repoPrepared.version;
    src = repoPrepared;

    postPatch = ''
      ${repoPrepared.permissionsFix}
    '';

    buildInputs = [
      gnum4
      autoconf
      automake
      libtool
      ocaml
      ocamlPackages.ocamlbuild
      file
      cmake
      openssl
      openssl.dev
      gnumake
      linux
      # glibc # Commented out deliberately: https://github.com/NixOS/nixpkgs/pull/28748
      binutils
      gcc
      texinfo
      bison
      flex

      # Additional build dependencies
      ncurses # tput
      which
      perl
      python2 # installer script
    ];

    # Apparently, dependencies are not properly declared, hence, parallel
    # building fails (sometimes).
    enableParallelBuilding = false;

    # We need `cmake` as a build input but don't use it to kick off the build phase
    dontUseCmakeConfigure = true;

    # Don't add any hardening flags the upstream package doesn't have.
    # At least Stack Protector cannot be used for the SDK:
    # https://github.com/intel/linux-sgx/issues/240#issuecomment-377839337
    hardeningDisable = [ "all" ];

    makeFlags = lib.optionals debug [
      "DEBUG=1"
    ];

    buildFlags = [
      "sdk_install_pkg"
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin/
      cp ./linux/installer/bin/sgx_linux_x64_sdk_*.bin $out/bin

      runHook postInstall
    '';
  };
in
stdenv.mkDerivation {
  pname = "intel-sgx-sdk" + lib.optionalString debug "-debug";
  version = installer.version;

  unpackPhase = "true";

  dontBuild = true;

  nativeBuildInputs = [ validatePkgConfig ];

  installPhase = ''
    runHook preInstall

    installDir=$TMPDIR
    ${installer}/bin/sgx_linux_x64_sdk_*.bin -prefix "$installDir"
    installDir=$installDir/sgxsdk

    echo "Installing files from $installDir"

    mkdir $out
    pushd $out

    mkdir $out/bin
    mv $installDir/bin/sgx-gdb $out/bin
    mkdir $out/bin/x64
    for file in $installDir/bin/x64/*; do
      mv $file bin/
      ln -sr bin/$(basename $file) bin/x64/
    done
    rmdir $installDir/bin/{x64,}

    # Move `lib64` to `lib` and symlink `lib64`
    mv $installDir/lib64 lib
    ln -s lib/ lib64

    mv $installDir/include/ .

    mkdir -p share/
    mv $installDir/{SampleCode,licenses} share/

    mkdir -p share/bin
    mv    $installDir/{environment,buildenv.mk} share/bin/
    ln -s share/bin/{environment,buildenv.mk} .

    # pkgconfig should go to lib/
    mv $installDir/pkgconfig lib/
    ln -s lib/pkgconfig/ .

    # Also create the `sdk_libs` for compat. All the files
    # link to libraries in `lib64/`, we shouldn't link the entire
    # directory, however, as there seems to be some ambiguity between
    # SDK and PSW libraries.
    mkdir sdk_libs/
    for file in $installDir/sdk_libs/*; do
      ln -sr lib/$(basename $file) sdk_libs/
      rm $file
    done
    rm -rf $installDir/sdk_libs

    # No uninstall script required
    rm $installDir/uninstall.sh

    # Make sure we didn't forget any files
    rmdir $installDir || (echo "Error: The directory $installDir still contains unhandled files: $(ls -A $installDir)" && exit 1)

    popd

    runHook postInstall
  '';

  preFixup = ''
    echo "Strip sgxsdk prefix"
    for path in "$out/share/bin/environment" "$out/bin/sgx-gdb"
    do
      substituteInPlace $path --replace "$TMPDIR/sgxsdk" "$out"
    done

    echo "Fixing pkg-config files"
    sed -i "s|prefix=.*|prefix=$out|g" $out/lib/pkgconfig/*.pc

    echo "Fixing SGX_SDK default in samples"
    substituteInPlace $out/share/SampleCode/LocalAttestation/buildenv.mk \
      --replace '/opt/intel/sgxsdk' "$out"
    for file in $out/share/SampleCode/*/Makefile; do
      substituteInPlace $file \
        --replace '/opt/intel/sgxsdk' "$out" \
        --replace '$(SGX_SDK)/buildenv.mk' "$out/share/bin/buildenv.mk"
    done

    echo "Patching buildenv.mk to use Intel's prebuilt Nix binutils"
    substituteInPlace $out/share/bin/buildenv.mk \
      --replace 'BINUTILS_DIR := /usr/local/bin' \
                "BINUTILS_DIR := ${deps.prebuilts.binutils}/external/toolset/nix/"

    echo "Patching GDB path in bin/sgx-gdb"
    substituteInPlace $out/bin/sgx-gdb \
      --replace '/usr/local/bin/gdb' \
                '${gdb}/bin/gdb'
  '';

  doInstallCheck = true;

  installCheckInputs = [ which ];

  hardeningDisable = [ "fortify" ];

  # Run the samples as tests in simulation mode.
  # The following samples are omitted:
  # - SampleCommonLoader: requires an actual SGX device
  # - PowerTransition: requires interaction
  installCheckPhase = ''
    runHook preInstallCheck

    source $out/share/bin/environment

    TESTDIR=`mktemp -d`
    cp -r $out/share/SampleCode $TESTDIR/

    for dir in "Cxx11SGXDemo" "SampleEnclave" "SampleEnclavePCL" "SealUnseal" "Switchless"; do
      cd $TESTDIR/SampleCode/$dir/
      make SGX_MODE=SIM
      ./app
    done

    cd $TESTDIR/SampleCode/LocalAttestation
    make SGX_MODE=SIM
    cd bin/
    ./app

    cd $TESTDIR/SampleCode/RemoteAttestation
    make SGX_MODE=SIM
    echo "a" | LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PWD/sample_libcrypto ./app

    # Make sure all symlinks are valid
    output=$(find "$out" -type l -exec test ! -e {} \; -print)
    if [[ -n "$output" ]]; then
      echo "Broken symlinks:"
      echo "$output"
      exit 1
    fi

    runHook postInstallCheck
  '';

  passthru.installer = installer;

  meta = with lib; {
    homepage = "https://github.com/intel/linux-sgx";
    description = "Intel SGX SDK";
    platforms = platforms.linux;
    license = licenses.free;
    maintainers = with maintainers; [ veehaitch ];
  };
}

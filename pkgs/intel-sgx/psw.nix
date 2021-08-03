{ callPackage
, coreutils
, curl
, glibc
, lib
, makeWrapper
, protobuf
, stdenv
, shadow
, systemd
, util-linux
  # Whether to build the SGX PSW with debug information. Adds a `-debug`
  # suffix to the derivation name, if `true`.
, debug ? false
  # If no SGX SDK given explicitly, pass the PSW debug flag to the SDK
, sgxSdk ? callPackage ./sdk.nix { inherit debug; }
}:
let
  deps = callPackage ./deps.nix { };
  tarballName = "sgxpsw_1.0.orig.tar.gz";
  tarball = sgxSdk.passthru.installer.overrideAttrs (oldAttrs: {
    pname = "intel-sgx-psw-tarball" + lib.optionalString debug "-debug";

    prePatch = ''
      substituteInPlace external/dcap_source/QuoteGeneration/buildenv.mk \
        --replace '$(SGX_SDK)/buildenv.mk' '${sgxSdk}/share/bin/buildenv.mk'
    '';

    buildInputs = oldAttrs.buildInputs ++ [
      protobuf
      curl
    ];

    makeFlags = lib.optionals debug [
      "DEBUG=1"
    ];

    buildFlags = [
      "SGX_SDK=${sgxSdk}"
      "psw_install_pkg"
    ];

    installPhase = ''
      mkdir $out
      cp linux/installer/common/psw/output/${tarballName} $out
    '';
  });
in
stdenv.mkDerivation {
  pname = "intel-sgx-psw" + lib.optionalString debug "-debug";
  version = tarball.version;
  src = "${tarball}/${tarballName}";
  sourceRoot = ".";

  nativeBuildInputs = [
    makeWrapper
  ];

  buildInputs = [
    coreutils
  ];

  buildFlags = [
    "DESTDIR=$(TMPDIR)/install"
    "install"
  ];

  installPhase = ''
    mkdir $out

    installDir=$TMPDIR/install
    sgxPswDir=$installDir/opt/intel/sgxpsw

    mv $installDir/usr/lib64/ $out/lib/
    ln -s lib/ lib64

    # Install udev rules to lib/udev/rules.d
    mv $sgxPswDir/udev/ $out/lib/

    # Install example AESM config
    mkdir $out/etc/
    mv $sgxPswDir/aesm/conf/aesmd.conf $out/etc/
    rmdir $sgxPswDir/aesm/conf/

    # Delete init service
    rm $sgxPswDir/aesm/aesmd.conf

    # Move systemd services
    mkdir -p $out/lib/systemd/system/
    mv $sgxPswDir/aesm/aesmd.service $out/lib/systemd/system/
    mv $sgxPswDir/remount-dev-exec.service $out/lib/systemd/system/

    # Move misc files
    mkdir $out/share/
    mv $sgxPswDir/licenses $out/share/

    # Remove unnecessary files
    rm $sgxPswDir/{cleanup.sh,startup.sh}
    rm -r $sgxPswDir/scripts

    mv $sgxPswDir/aesm/ $out/

    mkdir $out/bin
    makeWrapper $out/aesm/aesm_service $out/bin/aesm_service \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ protobuf ]}:$out/aesm \
      --run "cd $out/aesm"

    # Make sure we didn't forget to handle any files
    rmdir $sgxPswDir || (echo "Error: The directory $installDir still contains unhandled files: $(ls -A $installDir)" && exit 1)
  '';

  postFixup = ''
    echo "Fixing aesmd.service"
    substituteInPlace $out/lib/systemd/system/aesmd.service \
      --replace '@aesm_folder@' \
                "$out/aesm" \
      --replace 'Type=forking' \
                'Type=simple' \
      --replace "ExecStart=$out/aesm/aesm_service" \
                "ExecStart=$out/bin/aesm_service --no-daemon"\
      --replace "/bin/mkdir" \
                "${coreutils}/bin/mkdir" \
      --replace "/bin/chown" \
                "${coreutils}/bin/chown" \
      --replace "/bin/chmod" \
                "${coreutils}/bin/chmod" \
      --replace "/bin/kill" \
                "${coreutils}/bin/kill"

    echo "Fixing remount-dev-exec.service"
    substituteInPlace $out/lib/systemd/system/remount-dev-exec.service \
      --replace '/bin/mount' \
                "${util-linux}/bin/mount"

    echo "Fixing linksgx.sh"
    substituteInPlace $out/aesm/linksgx.sh \
      --replace '/usr/bin/getent' \
                '${glibc.bin}/bin/getent' \
      --replace '/usr/sbin/groupadd' \
                '${shadow}/bin/groupadd' \
      --replace 'udevadm' \
                '${systemd}/bin/udevadm' \
      --replace '/usr/sbin/usermod' \
                '${shadow}/bin/usermod'
  '';

  doInstallCheck = true;

  # Make sure that all of the prebuilt signed binaries weren't tampered.
  installCheckPhase = ''
    runHook preInstallCheck

    signedFiles=$(
      echo ${deps.dcap}/QuoteGeneration/psw/ae/data/prebuilt/libsgx_*.signed.so
      echo ${deps.prebuilts.ae}/psw/ae/data/prebuilt/libsgx_*.signed.so
    )

    function is_valid {
      orig=$1
      copy=$2

      echo -n "Checking integrity of $(basename $copy) ... "
      if [[ -e "$copy" ]]; then
        cmp --silent "$orig" "$copy" || (echo "corrupted!" && exit 1)
        echo "passed."
      else
        if [[ "$(basename $copy)" == "libsgx_qve.signed.so" ]]; then
          echo "ignored."
        else
          echo "does not exist!"
          exit 1
        fi
      fi
    }

    # Additional prebuilt in another location
    is_valid '${sgxSdk.passthru.installer.src}/psw/ae/data/prebuilt/white_list_cert_to_be_verify.bin' \
      "$out/aesm/data/white_list_cert_to_be_verify.bin"

    for file in $signedFiles; do
      filename=$(basename $file)
      outFile="$out/aesm/$filename"
      is_valid $file $outFile
    done

    # Make sure all symlinks are valid
    output=$(find "$out" -type l -exec test ! -e {} \; -print)
    if [[ -n "$output" ]]; then
      echo "Broken symlinks:"
      echo "$output"
      exit 1
    fi

    runHook postInstallCheck
  '';

  passthru.tarball = tarball;

  meta = with lib; {
    homepage = "https://github.com/intel/linux-sgx";
    description = "Intel SGX PSW";
    platforms = platforms.linux;
    license = licenses.free;
    maintainers = with maintainers; [ veehaitch ];
  };
}

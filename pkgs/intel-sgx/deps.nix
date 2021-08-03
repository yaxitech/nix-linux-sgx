{ autoPatchelfHook
, coreutils
, fetchFromGitHub
, fetchzip
, llvmPackages
, openssl
, pkgs
, stdenv
, versionIntelSgx ? "2.13"
, ...
}:
let
  opensslMeta = openssl.meta;
  base = attrs: stdenv.mkDerivation ({
    dontBuild = true;

    installPhase = ''
      mkdir $out
      cp -r . $out
    '';

    nativeBuildInputs = [ autoPatchelfHook ];
  } // attrs);
in
rec {
  dcap =
    let
      version = "1.10";
      prebuiltAe = base {
        pname = "sgx-dcap-prebuilt-ae";
        inherit version;

        src = fetchzip {
          url = "https://download.01.org/intel-sgx/sgx-dcap/${version}/linux/prebuilt_dcap_${version}.tar.gz";
          sha256 = "sha256-eG4AIt+RuEN+tXk83pdLBkZkgqiaNzV035F+1hymiZE=";
          stripRoot = false;
        };

        dontFixup = true;
      };
    in
    base {
      pname = "dcap";
      inherit version;

      src = fetchFromGitHub {
        owner = "intel";
        repo = "SGXDataCenterAttestationPrimitives";
        rev = "DCAP_${version}";
        sha256 = "sha256-OR7T7XRFnsBH6ccwqWQQUHm3iF1moQnJH4dfez6b0TI=";
      };

      postPhases = [ "rawCopyPhase" ];

      prePatch = ''
        echo "Stripping FHS paths"
        for file in "QuoteGeneration/buildenv.mk" tools/SGXPlatformRegistration/{Makefile,buildenv.mk}
        do
          substituteInPlace $file --replace '/bin/cp' '${coreutils}/bin/cp'
        done
      '';

      rawCopyPhase = ''
        echo "Copy signed prebuilt binaries"
        cp -r ${prebuiltAe}/. $out/QuoteGeneration
      '';

      meta.description = "Data Center Attestation Primitives (DCAP) provides SGX attestation support.";
    };
  dnnl = base rec {
    pname = "dnnl";
    version = "1.1";

    src = fetchFromGitHub {
      owner = "oneapi-src";
      repo = "oneDNN";
      rev = "rls-v${version}";
      sha256 = "sha256-aPvZdkuhoNh3LGpZ/LHfdyvX+SO1qN8jeQK0qztZWT4=";
    };

    meta.description = "oneAPI Deep Neural Network Library to provide building blocks for deep learning applications";
  };
  ipp-crypto = base rec {
    pname = "ipp-crypto";
    version = "2019_update5";

    src = fetchFromGitHub {
      owner = "intel";
      repo = "ipp-crypto";
      rev = "${pname}_${version}";
      sha256 = "sha256-+NUtcK5CQwvXUHdJwy/rJnPgKof/9FWx8kxZaPOZLUU=";
    };

    meta.description = "Intel Integrated Performance Primitives Cryptography";
  };
  openmp = base rec {
    pname = "openmp";
    version = "801";

    src = fetchFromGitHub {
      owner = "llvm-mirror";
      repo = pname;
      rev = "svn-tags/RELEASE_${version}";
      sha256 = "sha256-ShsFGHxx2vknZCQE9aZFroDeadB2KdbUU9lRY40czEM";
    };

    meta = llvmPackages.openmp;
  };
  openssl = base rec {
    pname = "openssl";
    version = "1.1.1i";

    src = fetchzip {
      url = "https://www.openssl.org/source/${pname}-${version}.tar.gz";
      sha256 = "sha256-9opyIA4WXokbvcIOcVb0yAs5j/1/3njhcNihPLNGxlo=";
    };

    meta = opensslMeta;
  };
  sgxssl = base rec {
    pname = "sgx-ssl";
    version = versionIntelSgx;

    src = fetchFromGitHub {
      owner = "intel";
      repo = "intel-sgx-ssl";
      rev = "lin_${version}_${openssl.version}";
      sha256 = "sha256-zztG3JrdYLFJ8cBAyjnsSkj/GLTf8/y+dRYUrl8IzEQ=";
    };

    meta.description = "Library based on OpenSSL to provide cryptographic services to SGX enclaves";
  };
  prebuilts = {
    optimizedLibs = base rec {
      pname = "optimized_libs";
      version = versionIntelSgx;

      src = fetchzip {
        url = "https://download.01.org/intel-sgx/sgx-linux/${version}/optimized_libs_${version}.tar.gz";
        sha256 = "sha256-r0OYI1VuCabwoScLITtHLBc3Nt+q1LrzwH9IF9TCoZ8=";
        stripRoot = false;
      };

      meta.description = "Prebuilt, optimized libs including Intel Integrated Performance Primitives (IPP) cryptographic libraries";
    };
    ae = base rec {
      pname = "ae";
      version = versionIntelSgx;

      src = fetchzip {
        url = "https://download.01.org/intel-sgx/sgx-linux/${version}/prebuilt_ae_${version}.tar.gz";
        sha256 = "sha256-+RMlGscao+prwreXCDdT9L4FvfTM5kWvx/x3iLTyNs8=";
        stripRoot = false;
      };

      dontFixup = true;

      meta.description = "Prebuilt SGX Application Enclave (AE) libraries";
    };
    binutils = base rec {
      pname = "binutils";
      version = versionIntelSgx;

      src = fetchzip {
        url = "https://download.01.org/intel-sgx/sgx-linux/${version}/as.ld.objdump.gold.r3.tar.gz";
        sha256 = "sha256-O2kQm1P/ENtsgLvd3jVsIIB17QYjezC5xtERyL86Zrc=";
        stripRoot = false;
      };

      # Override base
      nativeBuildInputs = [ stdenv.cc.cc.lib autoPatchelfHook ];

      meta.description = "Prebuilt as, ld, objdump, gold, and r3 for various platforms including Nix";
    };
  };
  meta.description = "Compile dependencies for intel/linux-sgx";
}

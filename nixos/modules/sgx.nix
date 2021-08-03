{ config, pkgs, lib, ... }:
with lib;
let
  kernelVersion = config.boot.kernelPackages.kernel.version;
  kernelAtLeast = config.boot.kernelPackages.kernel.passthru.kernelAtLeast;
  linuxKernelMinVersion = "5.11.0";
  enableSgxKernelPatch = {
    name = "sgx";
    patch = null;
    extraStructuredConfig.CRYPTO_SHA256 = kernel.yes;
    extraStructuredConfig.X86_SGX = kernel.yes;
  };
  cfgAesmd = config.services.aesmd;
  sgxPsw = pkgs.intel-sgx.psw.override { inherit (cfgAesmd) debug; };
  configFile =
    if cfgAesmd.config != null
    then pkgs.writeText "aesmd.conf" cfg.config
    else "${sgxPsw}/etc/aesmd.conf";
in
{
  # SGX kernel support
  options.hardware.cpu.intel.sgx = {
    enable = mkEnableOption "Intel SGX Linux kernel support";
  };

  # SGX AESM service
  options.services.aesmd = {
    enable = mkEnableOption "Intel's Architectural Enclave Service Manager (AESM) for Intel SGX";
    user = mkOption {
      type = types.str;
      default = "aesmd";
      description = "Username for the AESM service";
    };
    group = mkOption {
      type = types.str;
      default = "aesmd";
      description = "Group for the AESM service";
    };
    provision.group = mkOption {
      type = types.str;
      default = "sgx_prv";
      description = "SGX provisioning group for /dev/sgx_provision";
    };
    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to build the PSW package in debug mode";
    };
    config = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "AESM service config. If `null`, defaults to the packaged config";
      example = lib.literalExample ''
        #Line with comments only

        #proxy type    = direct #direct type means no proxy used
        #proxy type    = default #system default proxy
        #proxy type    = manual #aesm proxy should be specified for manual proxy type
        #aesm proxy    = http://proxy_url:proxy_port
        #whitelist url = http://sample_while_list_url/
        #default quoting type = ecdsa_256
        #default quoting type = epid_linkable
        #default quoting type = epid_unlinkable
      '';
    };
  };

  config = mkMerge [
    (
      mkIf config.hardware.cpu.intel.sgx.enable {
        assertions = [
          {
            assertion = kernelAtLeast linuxKernelMinVersion;
            message = "SGX not supported on Linux ${kernelVersion}, requires at least ${linuxKernelMinVersion}";
          }
        ];

        boot.kernelPatches = [ enableSgxKernelPatch ];
        hardware.cpu.intel.updateMicrocode = true;
        services.udev.extraRules = ''
          SUBSYSTEM=="misc", KERNEL=="sgx_enclave",   MODE="0666", SYMLINK+="sgx/enclave"
          SUBSYSTEM=="misc", KERNEL=="sgx_provision",              SYMLINK+="sgx/provision"
        '';
      }
    )
    (
      mkIf cfgAesmd.enable {
        users.groups = {
          ${cfgAesmd.group} = { };
          ${cfgAesmd.provision.group} = { };
        };

        services.udev.extraRules = ''
          SUBSYSTEM=="misc", KERNEL=="sgx_provision", MODE="0660", GROUP="${cfgAesmd.provision.group}"
        '';

        users.users.${cfgAesmd.user} = {
          description = "Intel Architectural Enclave Service Manager ";
          isSystemUser = true;
          extraGroups = [
            cfgAesmd.provision.group
          ];
        };

        systemd.services.remount-dev-exec = {
          description = "Remount /dev as exec to allow AESM service to boot and load enclaves into SGX";
          after = [ "systemd-udevd.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.util-linux}/bin/mount -o remount,exec /dev";
            RemainAfterExit = true;
          };
        };

        systemd.services.aesmd =
          let
            aesm_folder = "${sgxPsw}/aesm";
            # defined by AESM_DATA_FOLDER in psw/ae/aesm_service/source/oal/linux/aesm_util.cpp
            aesm_data_folder = "/var/opt/aesmd/data/";
          in
          {
            description = "Intel Architectural Enclave Service Manager";
            wantedBy = [ "multi-user.target" ];
            wants = [ "remount-dev-exec.service" ];

            after = [
              "syslog.target"
              "network.target"
              "auditd.service"
              "remount-dev-exec.service"
            ];

            environment = {
              NAME = "aesm_service";
              AESM_PATH = "${aesm_folder}";
              LD_LIBRARY_PATH = "${aesm_folder}";
            };

            serviceConfig = rec {
              ExecStartPre = pkgs.writeShellScript "copy-aesmd-data-files.sh" ''
                mkdir -m ${StateDirectoryMode} -p "${aesm_data_folder}"
                cp ${aesm_folder}/data/white_list_cert_to_be_verify.bin ${aesm_data_folder}
              '';
              ExecStart = "${sgxPsw}/bin/aesm_service --no-daemon";

              Restart = "on-failure";
              RestartSec = "15s";

              User = "${cfgAesmd.user}";
              Group = "${cfgAesmd.user}";

              StateDirectory = "aesmd";
              StateDirectoryMode = "0750";
              RuntimeDirectory = "aesmd";
              RuntimeDirectoryMode = "0755";
              BindPaths = [
                "${configFile}:/etc/aesmd.conf"
                # State directory
                "/var/lib/${StateDirectory}:/var/opt/aesmd"
                # AESM internal directory. Used to write the socket. Cleared when service stops.
                "/run/${RuntimeDirectory}:/var/run/aesmd"
              ];

              Type = "simple";
              WorkingDirectory = "${aesm_folder}";
              PermissionsStartOnly = true;
              InaccessibleDirectories = "/home";
              ExecReload = "${pkgs.coreutils}/bin/kill -SIGHUP $MAINPID";
              DevicePolicy = "closed";
              DeviceAllow = [
                "/dev/sgx/enclave rw"
                "/dev/sgx/provision rw"
              ];
            };
          };
      }
    )
  ];
}


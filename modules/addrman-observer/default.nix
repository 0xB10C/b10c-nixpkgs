{ config, lib, pkgs, ... }:

with lib;

let
  pkg = (pkgs.callPackage ../.. { }).addrman-observer;
  cfg = config.services.addrman-observer-proxy;
  #hardening = import ../systemd-hardening.nix { };

  nodeOpts = {
    options = {
      id = mkOption {
        type = types.ints.u16;
        description = "ID of the node as u16.";
        example = 1;
      };

      name = mkOption {
        type = types.str;
        description = "Name of the node as string. Max 32 chars.";
        example = "alice";
      };

      rpc = {
        port = mkOption {
          type = types.port;
          default = 8332;
          description = "Bitcoin Core RPC server port";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Bitcoin Core RPC server host";
        };

        user = mkOption {
          type = types.str;
          default = null;
          description = "Bitcoin Core RPC server user";
        };

        password = mkOption {
          type = types.str;
          default = null;
          description = "Bitcoin Core RPC server password";
        };

      };
    };
  };

  makeNodeConfig = node: ''

    [[nodes]]
    id = ${toString node.id}
    name = "${node.name}"
    rpc_host = "${node.rpc.host}"
    rpc_port = ${toString node.rpc.port}
    rpc_user = "${node.rpc.user}"
    rpc_password = "${node.rpc.password}"

  '';
in {
  options = {

    services.addrman-observer-proxy = {
      enable = mkEnableOption "addrman-observer-proxy";

      package = mkOption {
        type = types.package;
        default = pkg;
        description = "The addrman-observer-proxy package to use.";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1:3882";
        description = "Address the web-server listens on";
      };

      nodes = mkOption {
        type = types.listOf (types.submodule nodeOpts);
        default = [ ];
        description =
          "Specification of one or more nodes to proxy `getrawaddrman`.";
      };

    };
  };

  config = mkIf cfg.enable {
    users = {
      users.addrmanobserverproxy = {
        isSystemUser = true;
        group = "addrmanobserverproxy";
      };
      groups.addrmanobserverproxy = { };

    };

    systemd.services.addrman-observer-proxy = {
      description = "addrman-observer-proxy";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      startLimitIntervalSec = 120;
      preStart = ''
        cat <<EOF > /etc/addrman-observer-proxy/config.toml
        # addrman-observer-proxy configuration file
        # auto generated by the addrman-observer-proxy module

        www_path = "${cfg.package}/www"
        address = "${cfg.address}"

        ${concatMapStrings makeNodeConfig cfg.nodes}

        EOF'';

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/proxy";
        Environment =
          "CONFIG_FILE=/etc/addrman-observer-proxy/config.toml RUST_LOG=info";
        Restart = "always";
        # restart every 30 seconds but fail if we do more than 3 restarts in 120 sec
        RestartSec = 30;
        StartLimitBurst = 3;
        PermissionsStartOnly = true;
        MemoryDenyWriteExecute = true;
        ConfigurationDirectory = "addrman-observer-proxy"; # /etc/addrman-observer-proxy
        ConfigurationDirectoryMode = 710;
        DynamicUser = true;
        User = "addrmanobserverproxy";
        Group = "addrmanobserverproxy";
      };
    };
  };
}

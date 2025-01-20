{ config, lib, pkgs, ... }:

with lib;

let
  pkg = (pkgs.callPackage ../.. {}).peer-observer;
  cfg = config.services.peer-observer;
  hardening = {};#import ../systemd-hardening.nix { };
in {

  options = {

    services.peer-observer = {

      package = mkOption {
        type = types.package;
        default = pkg;
        defaultText = "pkgs.peer-observer";
        description = ''The peer-observer package to use.'';
      };

      extractor = {
        enable = mkEnableOption "peer-observer extractor";
        
        natsAddress = mkOption {
          type = types.str;
          default = "127.0.0.1:4222";
          example = "127.0.0.1:4222";
          description = "Address of the NATS server the extractor publishes events to";
        };
        
        bitcoindPath = mkOption {
          type = types.str;
          default = null;
          description = "Path to the bitcoind executable.";
        };
        
        bitcoindPIDFile = mkOption {
          type = types.str;
          default = null;
          description = "The path to the bitcoind PID file. This file is read by systemd during extractor startup.";
        };

        dependsOn = mkOption {
          type = types.str;
          default = null;
          example = "bitcoind-mainnet";
          description = "The bitcoind-*.service peer-observer depends on. i.e. the bitcoind process which should be traced. This is always 'bitcoind-<name>', where <name> is the name of the NixOS bitcoind service.";
        };
        
        extraArgs= mkOption {
          type = types.str;
          default = "";
          example = "--no-connection-tracepoints --addrman-tracepoints";
          description = "Extra arguments to pass to the peer-observer extractor.";
        };
      };

      metrics = {
        enable = mkEnableOption "prometheus metrics";
        
        metricsAddress = mkOption {
          type = types.str;
          default = "127.0.0.1:8282";
          example = "127.0.0.1:8282";
          description = "Address the metrics webserver should listen on.";
        };
      };
      
      addrConnectivity = {
        enable = mkEnableOption "addr connectivity lookup";

        metricsAddress = mkOption {
          type = types.str;
          default = "127.0.0.1:8282";
          example = "127.0.0.1:8282";
          description = "Address the metrics webserver should listen on.";
        };
      };
      
      websocket = {
        enable = mkEnableOption "websocket tool";

        websocketAddress = mkOption {
          type = types.str;
          default = "127.0.0.1:8282";
          example = "127.0.0.1:8282";
          description = "Address the websocket server should listen on.";
        };
      };
      
    };
  };
  config = mkIf (cfg.extractor.enable || cfg.metrics.enable || cfg.addrConnectivity.enable) {
    users = {
      users.peerobserver = { isSystemUser = true; group = "peerobserver"; };
      groups.peerobserver = { };
    };

    systemd.tmpfiles.rules = [
      "d '/var/lib/peer-observer/' 0770 'peerobserver' 'peerobserver' - -"
    ];

    # before we can start the peer-observer, wait until the PID file has been created by bitcoind
    # in the RuntimeDirectory
    systemd.services."${cfg.extractor.dependsOn}".serviceConfig = {
      RuntimeDirectory = "${cfg.extractor.dependsOn}";
      ExecStartPost = ''
        ${pkgs.bash}/bin/bash -c ' \
        while ! stat ${cfg.extractor.bitcoindPIDFile} 2>/dev/null; do \
          echo \"Waiting for bitcoind PID file...\"; \
          sleep 1; \
        done; \
        chmod +r ${cfg.extractor.bitcoindPIDFile}'
      '';
    };

    systemd.services.peer-observer-extractor = mkIf cfg.extractor.enable {
      description = "peer observer";
      wantedBy = [ "multi-user.target" ];
      after = ["network-online.target" "${cfg.extractor.dependsOn}.service" ];
      wants = ["network-online.target" "${cfg.extractor.dependsOn}.service" ];
      startLimitIntervalSec = 120;
      serviceConfig =
        {
          ExecStart = "${cfg.package}/bin/extractor --bitcoind-path ${cfg.extractor.bitcoindPath} --bitcoind-pid-file ${cfg.extractor.bitcoindPIDFile} --libbpf-debug --nats-address ${cfg.extractor.natsAddress} ${cfg.extractor.extraArgs}";
          Restart = "always";
          # restart every 30 seconds but fail if we do more than 3 restarts in 120 sec
          RestartSec = 30;
          StartLimitBurst = 3;
          PermissionsStartOnly = true;
          DynamicUser = true;
          ProtectProc = "default";
          ProcSubset = "all";
          AmbientCapabilities="CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE";
          CapabilityBoundingSet="CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE";
          PrivateUsers = "false";
          SystemCallFilter = [
            "@system-service"
            "~add_key clone3 get_mempolicy kcmp keyctl mbind move_pages name_to_handle_at personality process_vm_readv process_vm_writev request_key set_mempolicy setns unshare userfaultfd"
            "bpf"
            "clone3"
            "@debug"
          ];
          User = "peerobserver";
          Group = "peerobserver";
        };
      };

      systemd.services.peer-observer-metrics = mkIf cfg.metrics.enable {
        description = "peer-observer metrics";
        wantedBy = [ "multi-user.target" ];
        after = ["network-online.target" "peer-observer-extractor.service" ];
        wants = ["network-online.target" "peer-observer-extractor.service" ];
        startLimitIntervalSec = 120;
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/metrics --nats-address ${cfg.extractor.natsAddress} --metrics-address ${cfg.metrics.metricsAddress}";
          Environment = "RUST_LOG=info";
          Restart = "always";
          # restart every 30 seconds. Limit this to 3 times in 'startLimitIntervalSec'
          RestartSec = 30;
          StartLimitBurst = 3;
          PermissionsStartOnly = true;
          MemoryDenyWriteExecute = true;
          ConfigurationDirectory = "peer-observer";
          ConfigurationDirectoryMode = 710;
          DynamicUser = true;
          User = "peerobserver";
          Group = "peerobserver";
        };
      };

      systemd.services.peer-observer-addr-connectivity-check = mkIf cfg.addrConnectivity.enable {
        description = "peer-observer addr-connectivity-check";
        wantedBy = [ "multi-user.target" ];
        after = ["network-online.target" "peer-observer-extractor.service" ];
        wants = ["network-online.target" "peer-observer-extractor.service" ];
        startLimitIntervalSec = 120;
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/connectivity-check --nats-address ${cfg.extractor.natsAddress} --metrics-address ${cfg.addrConnectivity.metricsAddress}";
          Environment = "RUST_LOG=info";
          Restart = "always";
          # restart every 30 seconds. Limit this to 3 times in 'startLimitIntervalSec'
          RestartSec = 30;
          StartLimitBurst = 3;
          PermissionsStartOnly = true;
          MemoryDenyWriteExecute = true;
          ConfigurationDirectory = "peer-observer";
          WorkingDirectory = "/var/lib/peer-observer";
          ReadWriteDirectories = "/var/lib/peer-observer";
          ConfigurationDirectoryMode = 710;
          DynamicUser = true;
          User = "peerobserver";
          Group = "peerobserver";
        };
      };
      
      systemd.services.peer-observer-websocket = mkIf cfg.websocket.enable {
        description = "peer-observer websocket";
        wantedBy = [ "multi-user.target" ];
        after = ["network-online.target" "peer-observer-extractor.service" ];
        wants = ["network-online.target" "peer-observer-extractor.service" ];
        startLimitIntervalSec = 120;
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/websocket --nats-address ${cfg.extractor.natsAddress} --websocket-address ${cfg.websocket.websocketAddress}";
          Environment = "RUST_LOG=info";
          Restart = "always";
          # restart every 30 seconds. Limit this to 3 times in 'startLimitIntervalSec'
          RestartSec = 30;
          StartLimitBurst = 3;
          PermissionsStartOnly = true;
          MemoryDenyWriteExecute = true;
          DynamicUser = true;
          User = "peerobserver";
          Group = "peerobserver";
        };
      };

  };
}

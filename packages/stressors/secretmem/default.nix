{ pkgs, ... }:
let
  drv = pkgs.writeShellApplication {
    name = "stress-secretmem";
    runtimeInputs = [ pkgs.stress-ng ];
    text = ''
      PID_FILE="$KBN_STRESSOR_DIR/stressor.pid"
      STATUS_FILE="$KBN_STRESSOR_DIR/status.json"

      usage() {
        echo "Usage: $0 {--start|--stop}"
        exit 1
      }

      if [[ $# -eq 0 ]]; then
        usage
      fi

      case "$1" in
        --start)
          echo '{"stressed": true}' > "$STATUS_FILE"
          # Run in background, redirect FDs to avoid hanging SSH.
          # Use nohup to ensure it survives SSH session exit.
          nohup stress-ng --secretmem 0 >/dev/null 2>&1 &
          echo $! > "$PID_FILE"
          ;;
        --stop)
          if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE")
            kill "$pid" || true
            wait "$pid" 2>/dev/null || true
            rm "$PID_FILE"
          fi
          ;;
        *)
          usage
          ;;
      esac
    '';
    passthru = rec {
      falba-parsers.parsers.stressed_secretmem = {
        type = "command";
        artifact_regexp = "stressors/secretmem/status.json";
        args = [
          "${pkgs.jq}/bin/jq"
          ".stressed"
        ];
        fact = {
          name = "stressed_secretmem";
          type = "bool";
        };
      };
      falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" {
        parsers = falba-parsers.parsers;
      };
    };
  };
in
drv
// {
  heavyCheck = pkgs.callPackage ./test.nix {
    secretmem-stressor = drv;
  };
}

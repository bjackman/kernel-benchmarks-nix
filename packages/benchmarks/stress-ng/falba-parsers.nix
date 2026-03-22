{ pkgs, ... }:
{
  parsers.stress_ng_secretmem_bogo_ops_real_time = {
    type = "command";
    artifact_regexp = "stress-ng-metrics-brief.yaml";
    args = [
      # TODO: https://github.com/bjackman/falba/pull/8
      "${pkgs.yq}/bin/yq"
      ".metrics[] | select(.stressor == \"secretmem\") | .\"bogo-ops-per-second-real-time\""
    ];
    metric = {
      name = "stress_ng_secretmem_bogo_ops_real_time";
      type = "float";
    };
  };
  parsers.stress_ng_secretmem_system_time = {
    type = "command";
    artifact_regexp = "stress-ng-metrics-brief.yaml";
    args = [
      "${pkgs.yq}/bin/yq"
      ".metrics[] | select(.stressor == \"secretmem\") | .\"system-time\""
    ];
    metric = {
      name = "stress_ng_secretmem_system_time";
      type = "float";
      unit = "s";
    };
  };
}

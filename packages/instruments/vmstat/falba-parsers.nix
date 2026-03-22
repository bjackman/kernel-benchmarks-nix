{ pkgs, ... }:
let
  # List of important vmstat metrics we want to track.
  # This avoids overwhelming the DB while providing useful data.
  # If the user wants ALL metrics, we could generate this list or
  # use a different Falba mechanism if available.
  metrics = [
    "pgfault"
    "pgmajfault"
    "pgpgin"
    "pgpgout"
    "pswpin"
    "pswpout"
    "nr_free_pages"
    "nr_active_anon"
    "nr_inactive_anon"
    "nr_active_file"
    "nr_inactive_file"
  ];

  # Helper to create a parser entry for a single vmstat metric.
  makeVmstatParser = metric: {
    name = "vmstat_diff_${metric}";
    value = {
      type = "command";
      artifact_regexp = "instrumentation/vmstat/diff";
      args = [
        "${pkgs.gawk}/bin/gawk"
        # Search for the line starting with the metric name and print its value.
        "$1 == \"${metric}\" { print $2 }"
      ];
      metric = {
        name = "vmstat_diff_${metric}";
        type = "int";
      };
    };
  };
in
{
  parsers = builtins.listToAttrs (map makeVmstatParser metrics);
}

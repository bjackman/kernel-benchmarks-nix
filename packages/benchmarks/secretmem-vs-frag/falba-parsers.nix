{
  parsers.secretmem_allocated_bytes = {
    type = "jsonpath";
    artifact_regexp = "secretmem_vs_frag_run_.*\\.json";
    jsonpath = "$.allocated_bytes";
    metric = {
      name = "secretmem_allocated_bytes";
      type = "int";
      unit = "B";
    };
  };
}

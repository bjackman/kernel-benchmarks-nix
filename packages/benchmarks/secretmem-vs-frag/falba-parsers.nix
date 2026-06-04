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
  parsers.secretmem_antagonized = {
    type = "jsonpath";
    artifact_regexp = "secretmem_vs_frag_summary\\.json";
    jsonpath = "$.antagonized";
    fact = {
      name = "secretmem_antagonized";
      type = "bool";
    };
  };
  parsers.secretmem_iterations = {
    type = "jsonpath";
    artifact_regexp = "secretmem_vs_frag_summary\\.json";
    jsonpath = "$.iterations";
    fact = {
      name = "secretmem_iterations";
      type = "int";
    };
  };
}

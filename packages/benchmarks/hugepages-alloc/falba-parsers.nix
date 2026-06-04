{
  parsers.allocated_hugepages = {
    type = "jsonpath";
    artifact_regexp = "hugepages_alloc_summary\\.json";
    jsonpath = "$.allocated_hugepages";
    fact = {
      name = "allocated_hugepages";
      type = "int";
    };
  };
}

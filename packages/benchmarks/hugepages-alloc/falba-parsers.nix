{
  parsers = {
    requested_hugepages = {
      type = "jsonpath";
      artifact_regexp = "hugepages_alloc_summary\\.json";
      jsonpath = "$.requested_hugepages";
      fact = {
        name = "requested_hugepages";
        type = "int";
      };
    };
    allocated_hugepages = {
      type = "jsonpath";
      artifact_regexp = "hugepages_alloc_summary\\.json";
      jsonpath = "$.allocated_hugepages";
      metric = {
        name = "allocated_hugepages";
        type = "int";
      };
    };
  };
}

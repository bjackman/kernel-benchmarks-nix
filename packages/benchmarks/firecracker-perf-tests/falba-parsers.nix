{
  parsers.populate_latency = {
    type = "jsonpath";
    artifact_regexp = "test_population_latency.*/metrics.json";
    jsonpath = "$.metrics.populate_latency.values";
    metric = {
      name = "populate_latency";
      type = "float";
      unit = "ms";
    };
  };
}
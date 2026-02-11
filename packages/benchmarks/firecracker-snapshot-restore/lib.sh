# Note you need to set FC_SOCK for this to work.

fc_request() {
    local verb="$1"
    local path="$2"
    local json="$3"

    curl --unix-socket "$FC_SOCK" -i -X "$verb" "http://localhost$path" \
    -H "Accept: application/json" -H "Content-Type: application/json" \
    -d "$json"
}

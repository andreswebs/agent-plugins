# One record per tag on each resource. Works for both resource lists and
# resource-group lists; $scope labels which one this input is.
[ .[] | . as $r
  | ($r.tags // {}) | to_entries[]
  | {key: .key, value: .value, scope: $scope, type: ($r.type // "Microsoft.Resources/resourceGroups"), name: $r.name}
]

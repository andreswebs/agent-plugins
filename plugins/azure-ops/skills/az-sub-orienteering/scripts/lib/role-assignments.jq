# Role assignments with an origin column. Input: az role assignment list
# --include-inherited. $sub: the swept subscription id.
# $mode: "all" | "privileged"
# Rows: [principal, type, role, scope, origin]

def privileged_roles:
    ["Owner", "Contributor", "User Access Administrator", "Role Based Access Control Administrator",
     "Security Admin", "Key Vault Administrator", "Storage Blob Data Owner"];

def origin($sub):
    if (.scope | ascii_downcase) == ("/subscriptions/" + ($sub | ascii_downcase)) then "subscription"
    elif (.scope | ascii_downcase | startswith("/subscriptions/" + ($sub | ascii_downcase) + "/")) then "resource group / resource"
    elif (.scope | startswith("/providers/Microsoft.Management/")) then "management group"
    elif .scope == "/" then "root"
    else "other"
    end;

[ .[]
  | select($mode == "all" or (.roleDefinitionName | IN(privileged_roles[])))
  | [
      (.principalName // .principalId),
      (.principalType // "-"),
      .roleDefinitionName,
      .scope,
      origin($sub)
    ]
]
| sort_by(.[2], .[0])

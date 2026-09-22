#!/usr/bin/env bash
# Key Vault: where the credentials that should not exist tend to live.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_33_keyvault() {
    report_begin "Key Vault"

    if skip_if_absent "Microsoft.KeyVault/vaults"; then
        return 0
    fi

    run_az_json vaults keyvault list || true

    emit_section "Vaults"
    emit "\`az keyvault list\` returns a summary; per-vault settings come from \`show\` below."
    emit ""
    local kv
    while IFS=$'\t' read -r kv _rg _rid; do
        [ -z "${kv}" ] && continue
        run_az_json "show-${kv}" keyvault show --name "${kv}" || true
    done < <(inventory_of_type "Microsoft.KeyVault/vaults")

    local shows="${AZSD_RAW_DIR}/vaults-detail.json"
    if ! find "${AZSD_RAW_DIR}" -maxdepth 1 -name 'show-*.json' -type f -print0 |
        xargs -0 jq --slurp 'map(select(type == "object"))' >"${shows}" 2>/dev/null; then
        echo "[]" >"${shows}"
    fi

    emit_table "${shows}" "Vault|RG|SKU|RBAC authz|Soft delete|Retention days|Purge protection|Public access|Default action|Access policies|Deployment|Template|Disk encryption" \
        '.[] | [.name, .resourceGroup, (.properties.sku.name // "-"), (.properties.enableRbacAuthorization // false), (.properties.enableSoftDelete // false), (.properties.softDeleteRetentionInDays // "-"), (.properties.enablePurgeProtection // false), (.properties.publicNetworkAccess // "-"), (.properties.networkAcls.defaultAction // "-"), ((.properties.accessPolicies // []) | length), (.properties.enabledForDeployment // false), (.properties.enabledForTemplateDeployment // false), (.properties.enabledForDiskEncryption // false)]'

    emit_section "Legacy access policies"
    emit "Vaults not on RBAC authorization grant access here, outside Azure RBAC and its audit trail."
    emit ""
    # shellcheck disable=SC2016  # jq program
    emit_table "${shows}" "Vault|Object ID|Secrets|Keys|Certificates" \
        '.[] | select((.properties.enableRbacAuthorization // false) == false) | .name as $v | (.properties.accessPolicies // [])[] | [$v, .objectId, ((.permissions.secrets // []) | join(",")), ((.permissions.keys // []) | join(",")), ((.permissions.certificates // []) | join(","))]'

    emit_section "Object counts"
    emit "Needs data-plane access (Key Vault Reader or an access policy); a dash means the caller could not list, not that the vault is empty."
    emit ""
    local secrets keys certs
    local counts="${AZSD_RAW_DIR}/object-counts.jsonl"
    : >"${counts}"
    while IFS=$'\t' read -r kv _rg _rid; do
        [ -z "${kv}" ] && continue
        secrets="-"
        keys="-"
        certs="-"
        if run_az_json "secrets-${kv}" keyvault secret list --vault-name "${kv}" --query "[].{name:name, enabled:attributes.enabled, expires:attributes.expires}"; then
            secrets="$(json_count "${AZSD_RAW_DIR}/secrets-${kv}.json")"
        fi
        if run_az_json "keys-${kv}" keyvault key list --vault-name "${kv}" --query "[].{name:name, enabled:attributes.enabled, expires:attributes.expires}"; then
            keys="$(json_count "${AZSD_RAW_DIR}/keys-${kv}.json")"
        fi
        if run_az_json "certs-${kv}" keyvault certificate list --vault-name "${kv}" --query "[].{name:name, enabled:attributes.enabled, expires:attributes.expires}"; then
            certs="$(json_count "${AZSD_RAW_DIR}/certs-${kv}.json")"
        fi
        jq --null-input --compact-output --arg v "${kv}" --arg s "${secrets}" --arg k "${keys}" --arg c "${certs}" \
            '[$v, $s, $k, $c]' >>"${counts}"
    done < <(inventory_of_type "Microsoft.KeyVault/vaults")
    jq --slurp '.' "${counts}" | render_table "Vault|Secrets|Keys|Certificates" >>"${AZSD_REPORT_FILE}"

    return 0
}

function module_33_keyvault_types() {
    echo "Microsoft.KeyVault/vaults"
    echo "Microsoft.KeyVault/managedHSMs"
}

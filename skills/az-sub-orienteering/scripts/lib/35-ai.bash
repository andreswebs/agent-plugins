#!/usr/bin/env bash
# AI services: Cognitive Services / Azure OpenAI accounts and deployments, ML workspaces.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_35_ai() {
    report_begin "AI services"

    emit_section "Cognitive Services and Azure OpenAI accounts"
    if ! skip_if_absent "Microsoft.CognitiveServices/accounts"; then
        run_az_json accounts cognitiveservices account list || true
        emit_table "${AZSD_RAW_DIR}/accounts.json" "Account|RG|Kind|SKU|Public access|Local auth|Custom domain|Endpoint" \
            '.[] | [.name, .resourceGroup, .kind, (.sku.name // "-"), (.properties.publicNetworkAccess // "-"), (if .properties.disableLocalAuth == true then "disabled" else "enabled" end), (.properties.customSubDomainName // "-"), (.properties.endpoint // "-")]'

        emit_section "Model deployments"
        local acc rg kind
        while IFS=$'\t' read -r acc rg _rid; do
            [ -z "${acc}" ] && continue
            kind="$(jq --raw-output --arg n "${acc}" '.[] | select(.name == $n) | .kind' "${AZSD_RAW_DIR}/accounts.json" 2>/dev/null || echo "")"
            case "${kind}" in
            OpenAI | AIServices) ;;
            *) continue ;;
            esac
            run_az_json "deployments-${acc}" cognitiveservices account deployment list --name "${acc}" --resource-group "${rg}" || true
            emit_subsection "${acc} (${kind})"
            emit_table "${AZSD_RAW_DIR}/deployments-${acc}.json" "Deployment|Model|Version|SKU|Capacity|Content filter|State" \
                '.[] | [.name, (.properties.model.name // "-"), (.properties.model.version // "-"), (.sku.name // "-"), (.sku.capacity // "-"), (.properties.raiPolicyName // "-"), (.properties.provisioningState // "-")]'
        done < <(inventory_of_type "Microsoft.CognitiveServices/accounts")
    fi

    emit_section "Machine Learning and AI Foundry workspaces"
    if ! skip_if_absent "Microsoft.MachineLearningServices/workspaces"; then
        run_az_json ml-workspaces resource list --resource-type "Microsoft.MachineLearningServices/workspaces" || true
        emit_columns "${AZSD_RAW_DIR}/ml-workspaces.json" "Workspace|RG|Kind|Location|Identity" "name|resourceGroup|kind|location|identity.type"
    fi

    emit_section "Search services"
    if ! skip_if_absent "Microsoft.Search/searchServices"; then
        run_az_json search resource list --resource-type "Microsoft.Search/searchServices" || true
        emit_columns "${AZSD_RAW_DIR}/search.json" "Service|RG|SKU|Location" "name|resourceGroup|sku.name|location"
    fi

    return 0
}

function module_35_ai_types() {
    cat <<'EOF'
Microsoft.CognitiveServices/accounts
Microsoft.MachineLearningServices/workspaces
Microsoft.Search/searchServices
EOF
}

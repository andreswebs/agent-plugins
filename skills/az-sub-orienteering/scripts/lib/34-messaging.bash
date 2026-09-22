#!/usr/bin/env bash
# Messaging and eventing: Service Bus, Event Hubs, Event Grid.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_34_messaging() {
    report_begin "Messaging and eventing"

    emit_section "Service Bus namespaces"
    if ! skip_if_absent "Microsoft.ServiceBus/namespaces"; then
        run_az_json servicebus servicebus namespace list || true
        emit_table "${AZSD_RAW_DIR}/servicebus.json" "Namespace|RG|SKU|Capacity|Zone redundant|Public access|Local auth|Min TLS" \
            '.[] | [.name, .resourceGroup, .sku.name, (.sku.capacity // "-"), (.zoneRedundant // false), (.publicNetworkAccess // "-"), (if .disableLocalAuth == true then "disabled" else "enabled" end), (.minimumTlsVersion // "-")]'
        local ns rg
        while IFS=$'\t' read -r ns rg _rid; do
            [ -z "${ns}" ] && continue
            run_az_json "sb-queues-${ns}" servicebus queue list --namespace-name "${ns}" --resource-group "${rg}" || true
            run_az_json "sb-topics-${ns}" servicebus topic list --namespace-name "${ns}" --resource-group "${rg}" || true
            run_az_json "sb-authrules-${ns}" servicebus namespace authorization-rule list --namespace-name "${ns}" --resource-group "${rg}" || true
            emit_subsection "${ns}: queues"
            emit_table "${AZSD_RAW_DIR}/sb-queues-${ns}.json" "Queue|Status|Sessions|Active|Dead-lettered|Max size MB" \
                '.[] | [.name, .status, (.requiresSession // false), (.countDetails.activeMessageCount // 0), (.countDetails.deadLetterMessageCount // 0), (.maxSizeInMegabytes // "-")]'
            emit_subsection "${ns}: topics"
            emit_columns "${AZSD_RAW_DIR}/sb-topics-${ns}.json" "Topic|Status|Subscriptions" "name|status|subscriptionCount"
            emit_subsection "${ns}: shared access policies"
            emit_table "${AZSD_RAW_DIR}/sb-authrules-${ns}.json" "Policy|Rights" '.[] | [.name, ((.rights // []) | join(","))]'
        done < <(inventory_of_type "Microsoft.ServiceBus/namespaces")
    fi

    emit_section "Event Hubs namespaces"
    if ! skip_if_absent "Microsoft.EventHub/namespaces"; then
        run_az_json eventhubs eventhubs namespace list || true
        emit_table "${AZSD_RAW_DIR}/eventhubs.json" "Namespace|RG|SKU|Capacity|Auto-inflate|Public access|Local auth|Min TLS" \
            '.[] | [.name, .resourceGroup, .sku.name, (.sku.capacity // "-"), (.isAutoInflateEnabled // false), (.publicNetworkAccess // "-"), (if .disableLocalAuth == true then "disabled" else "enabled" end), (.minimumTlsVersion // "-")]'
    fi

    emit_section "Event Grid"
    if ! skip_if_absent "Microsoft.EventGrid/topics" "Microsoft.EventGrid/systemTopics" "Microsoft.EventGrid/domains"; then
        run_az_json eg-topics eventgrid topic list || true
        run_az_json eg-system-topics eventgrid system-topic list || true
        run_az_json eg-domains eventgrid domain list || true
        emit_subsection "Custom topics"
        emit_table "${AZSD_RAW_DIR}/eg-topics.json" "Topic|RG|Public access|Local auth|Input schema" \
            '.[] | [.name, .resourceGroup, (.publicNetworkAccess // "-"), (if .disableLocalAuth == true then "disabled" else "enabled" end), (.inputSchema // "-")]'
        emit_subsection "System topics"
        emit_table "${AZSD_RAW_DIR}/eg-system-topics.json" "Topic|RG|Source|Topic type" \
            '.[] | [.name, .resourceGroup, ((.source // "-") | split("/") | last), (.topicType // "-")]'
        emit_subsection "Domains"
        emit_columns "${AZSD_RAW_DIR}/eg-domains.json" "Domain|RG|Public access" "name|resourceGroup|publicNetworkAccess"
    fi

    return 0
}

function module_34_messaging_types() {
    cat <<'EOF'
Microsoft.ServiceBus/namespaces
Microsoft.EventHub/namespaces
Microsoft.EventGrid/topics
Microsoft.EventGrid/systemTopics
Microsoft.EventGrid/domains
Microsoft.EventGrid/eventSubscriptions
EOF
}

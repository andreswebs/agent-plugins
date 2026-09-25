#!/usr/bin/env bash
# Managed databases and caches: PostgreSQL, MySQL, SQL, Cosmos DB, Redis.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_32_data() {
    report_begin "Databases and caches"

    emit_section "PostgreSQL Flexible Server"
    if ! skip_if_absent "Microsoft.DBforPostgreSQL/flexibleServers"; then
        run_az_json postgres postgres flexible-server list || true
        emit_table "${AZSD_RAW_DIR}/postgres.json" "Name|RG|Version|SKU|Tier|Storage GB|HA|Backup days|Geo backup|Public access|Password auth|Entra auth" \
            '.[] | [.name, .resourceGroup, .version, .sku.name, .sku.tier, (.storage.storageSizeGb // "-"), (.highAvailability.mode // "Disabled"), (.backup.backupRetentionDays // "-"), (.backup.geoRedundantBackup // "-"), (.network.publicNetworkAccess // "-"), (.authConfig.passwordAuth // "-"), (.authConfig.activeDirectoryAuth // "-")]'
        local srv rg
        while IFS=$'\t' read -r srv rg _rid; do
            [ -z "${srv}" ] && continue
            run_az_json "pg-firewall-${srv}" postgres flexible-server firewall-rule list --name "${srv}" --resource-group "${rg}" || true
            run_az_json "pg-databases-${srv}" postgres flexible-server db list --server-name "${srv}" --resource-group "${rg}" || true
            emit_subsection "${srv}: firewall rules"
            emit_columns "${AZSD_RAW_DIR}/pg-firewall-${srv}.json" "Rule|Start|End" "name|startIpAddress|endIpAddress"
            emit_subsection "${srv}: databases"
            emit_columns "${AZSD_RAW_DIR}/pg-databases-${srv}.json" "Database|Charset|Collation" "name|charset|collation"
        done < <(inventory_of_type "Microsoft.DBforPostgreSQL/flexibleServers")
    fi

    emit_section "MySQL Flexible Server"
    if ! skip_if_absent "Microsoft.DBforMySQL/flexibleServers"; then
        run_az_json mysql mysql flexible-server list || true
        emit_table "${AZSD_RAW_DIR}/mysql.json" "Name|RG|Version|SKU|HA|Backup days|Geo backup|Public access" \
            '.[] | [.name, .resourceGroup, .version, .sku.name, (.highAvailability.mode // "Disabled"), (.backup.backupRetentionDays // "-"), (.backup.geoRedundantBackup // "-"), (.network.publicNetworkAccess // "-")]'
    fi

    emit_section "Azure SQL"
    if ! skip_if_absent "Microsoft.Sql/servers"; then
        run_az_json sql-servers sql server list || true
        emit_table "${AZSD_RAW_DIR}/sql-servers.json" "Server|RG|Version|Public access|Min TLS|Entra-only auth|Entra admin" \
            '.[] | [.name, .resourceGroup, (.version // "-"), (.publicNetworkAccess // "-"), (.minimalTlsVersion // "-"), (.administrators.azureAdOnlyAuthentication // false), (.administrators.login // "-")]'
        local srv rg
        while IFS=$'\t' read -r srv rg _rid; do
            [ -z "${srv}" ] && continue
            run_az_json "sql-dbs-${srv}" sql db list --server "${srv}" --resource-group "${rg}" || true
            run_az_json "sql-firewall-${srv}" sql server firewall-rule list --server "${srv}" --resource-group "${rg}" || true
            emit_subsection "${srv}: databases"
            emit_table "${AZSD_RAW_DIR}/sql-dbs-${srv}.json" "Database|SKU|Max size GB|Zone redundant|Backup redundancy" \
                '.[] | [.name, (.currentSku.name // .sku.name // "-"), ((.maxSizeBytes // 0) / 1073741824 | floor), (.zoneRedundant // false), (.requestedBackupStorageRedundancy // "-")]'
            emit_subsection "${srv}: firewall rules"
            emit "A rule 0.0.0.0-0.0.0.0 is the \"Allow Azure services\" switch: any tenant's Azure resources."
            emit ""
            emit_columns "${AZSD_RAW_DIR}/sql-firewall-${srv}.json" "Rule|Start|End" "name|startIpAddress|endIpAddress"
        done < <(inventory_of_type "Microsoft.Sql/servers")
    fi

    emit_section "Cosmos DB"
    if ! skip_if_absent "Microsoft.DocumentDB/databaseAccounts"; then
        run_az_json cosmos cosmosdb list || true
        emit_table "${AZSD_RAW_DIR}/cosmos.json" "Account|RG|Kind|API|Public access|Local auth|IP rules|VNet filter|Backup|Multi-region write" \
            '.[] | [.name, .resourceGroup, (.kind // "-"), ((.capabilities // []) | map(.name) | join(",")), (.publicNetworkAccess // "-"), (if .disableLocalAuth == true then "disabled" else "enabled" end), ((.ipRules // []) | length), (.isVirtualNetworkFilterEnabled // false), (.backupPolicy.type // "-"), (.enableMultipleWriteLocations // false)]'
    fi

    emit_section "Azure Cache for Redis"
    if ! skip_if_absent "Microsoft.Cache/redis" "Microsoft.Cache/redisEnterprise"; then
        run_az_json redis redis list || true
        emit_table "${AZSD_RAW_DIR}/redis.json" "Name|RG|SKU|Size|Min TLS|Non-SSL port|Public access|Access key auth" \
            '.[] | [.name, .resourceGroup, (.sku.name // "-"), ("\(.sku.family // "")\(.sku.capacity // "")"), (.minimumTlsVersion // "-"), (.enableNonSslPort // false), (.publicNetworkAccess // "-"), (if .disableAccessKeyAuthentication == true then "disabled" else "enabled" end)]'
        emit_subsection "Redis Enterprise (names only)"
        run_az_json redis-enterprise resource list --resource-type "Microsoft.Cache/redisEnterprise" || true
        emit_columns "${AZSD_RAW_DIR}/redis-enterprise.json" "Name|RG|Location|SKU" "name|resourceGroup|location|sku.name"
    fi

    return 0
}

function module_32_data_types() {
    cat <<'EOF'
Microsoft.DBforPostgreSQL/flexibleServers
Microsoft.DBforMySQL/flexibleServers
Microsoft.Sql/servers
Microsoft.Sql/servers/databases
Microsoft.DocumentDB/databaseAccounts
Microsoft.Cache/redis
Microsoft.Cache/redisEnterprise
EOF
}

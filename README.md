# agent-plugins

A Claude Code plugin marketplace whose plugins are also
[Agent Plugins](https://agent-plugins.org) 1.0.0 packages. Each plugin lives in
its own directory under `plugins/` and works in Claude Code and in any client
that implements the Agent Plugins format.

## Plugins

| Plugin                          | Description                                                                             |
| ------------------------------- | --------------------------------------------------------------------------------------- |
| [azure-ops](plugins/azure-ops/) | Skills and MCP servers for operating Azure subscriptions and Azure DevOps organisations |

## Install

### Claude Code

Add the marketplace, then install a plugin by name:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install azure-ops@andreswebs
```

The same commands work inside a session as `/plugin marketplace add` and
`/plugin install`.

To offer the marketplace to everyone working in a project, add it to the
project's `.claude/settings.json`. Claude Code prompts each person to install
it once they trust the folder:

```json
{
  "extraKnownMarketplaces": {
    "andreswebs": {
      "source": { "source": "github", "repo": "andreswebs/agent-plugins" }
    }
  },
  "enabledPlugins": {
    "azure-ops@andreswebs": true
  }
}
```

### Other Agent Plugins clients

Each `plugins/<name>/` directory is a self-contained Agent Plugins 1.0.0
package. The format does not define how packages are installed, so load one
the way your client loads a package from a local directory or a git
subdirectory; see its documentation.

## Layout

```text
.claude-plugin/marketplace.json   Claude Code catalog; lists every plugin
plugins/<name>/
  plugin.json                     Agent Plugins manifest
  mcp.json                        MCP servers, read by both formats
  skills/<skill>/SKILL.md         Agent Skills, read by both formats
  .claude-plugin/plugin.json      Claude Code manifest
  README.md
  LICENSE
scripts/check-plugins.bash        static checks for the whole repository
```

The repository root is a marketplace, not a package. Each plugin carries two
manifests because the formats read different files: Agent Plugins requires
`plugin.json` at the package root with a closed schema, and Claude Code reads
`.claude-plugin/plugin.json`. Claude Code looks for MCP servers in `.mcp.json`
by default, so the Claude manifest points it at the shared `mcp.json` with
`"mcpServers": "./mcp.json"`. Keep `name` and `version` identical in both.

Claude-only components such as `agents/`, `hooks/` or `commands/` load in
Claude Code and are ignored by other clients, but a plugin that ships them no
longer conforms fully to the Agent Plugins specification. Prefer skills and
MCP servers.

## Add a plugin

1. Create `plugins/<name>/` with a `plugin.json` that validates against the
   [Agent Plugins schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json).
2. Add skills under `skills/` and MCP servers in `mcp.json`, as needed.
3. Add `.claude-plugin/plugin.json` with the same `name` and `version`. It is
   required when the plugin has an `mcp.json`, for the redirect above.
4. Add an entry to `.claude-plugin/marketplace.json` with
   `"source": "./plugins/<name>"` and the same `name`. Leave `version` out of
   the entry; the manifests own it.
5. Add a `README.md` and a copy of the repository `LICENSE`. The plugin is
   installed on its own, without the rest of this repository.
6. Run `scripts/check-plugins.bash`.

## Develop

Load a plugin in place for one session, without installing it:

```sh
claude --plugin-dir ./plugins/azure-ops
```

Run `/reload-plugins` inside the session to pick up edits.

`scripts/check-plugins.bash` checks the catalog against the plugin
directories, compares the two manifests of every plugin, validates the
portable files against the Agent Plugins schemas, and runs
`claude plugin validate` when Claude Code is installed. It needs `jq` and
`uv`.

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).

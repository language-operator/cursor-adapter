/**
 * Cursor emitter — placeholder.
 *
 * The shape of coding-runtime's `examples/minimal`: one managed file, one owned
 * key. The real translation of the operator's config into Cursor's — MCP
 * servers, rules, the vendor key — is language-operator/cursor-adapter#1; this
 * stub exists so the runtime seeds cleanly in the meantime.
 *
 * Cursor reads `mcp.json` from its config directory, which runtime.json points
 * at `${STATE_DIR}/cursor` through CURSOR_CONFIG_DIR. `mcpServers` is owned in
 * full and stated as `null` on every run, so the file holds no servers until #1
 * fills it in, and whatever #1 writes is removed again if the key is withdrawn.
 */

export function emit(config) {
  const configDir = `${config.paths.stateDir}/cursor`;

  return [
    {
      path: `${configDir}/mcp.json`,
      owns: ['mcpServers'],
      values: { mcpServers: null },
    },
  ];
}

export default emit;

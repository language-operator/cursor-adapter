/**
 * Cursor emitter.
 *
 * Cursor is a vendor-key runtime: it authenticates to Cursor with
 * CURSOR_API_KEY (or an interactive `agent login`) and has no custom base URL,
 * so `config.gateway` and `config.models` go unused here — gateway model ids are
 * not Cursor model names. CURSOR_MODEL, read by the launchers, picks a model.
 *
 * Two things are written:
 *
 * - MCP servers, to $HOME/.cursor/mcp.json. That path is fixed: Cursor reads its
 *   global MCP file from the home directory and ignores CURSOR_CONFIG_DIR for
 *   it. Global servers, unlike a project's .cursor/mcp.json, need no approval,
 *   so they load in the TUI and under `-p` alike without an approval file — one
 *   keyed on a hash of the interpolated config, which a rotated secret would
 *   silently invalidate.
 *
 * - The persona, as an always-applied rule in the *workspace's* .cursor/rules.
 *   Cursor loads rules from the working directory and every ancestor of it, so
 *   when the agent works in a cloned repo below /workspace the rule applies
 *   without dirtying that repo's tree. There is no supported flag for a system
 *   prompt; a rule is the standing-context mechanism Cursor offers.
 *
 * Instructions are deliberately not a rule. They are the opening message in
 * service mode and the prompt in task mode (see the launchers), so a task run
 * does not receive them twice.
 */

const RULE_FILE = 'langop-persona.mdc';

function personaRule(persona) {
  if (!persona) {
    // A whole-file write cannot be withdrawn, so a removed persona is replaced
    // by a rule that never applies rather than left in force.
    return '---\ndescription: Language Operator persona (none configured)\nalwaysApply: false\n---\n';
  }
  return `---\ndescription: Language Operator persona for this agent\nalwaysApply: true\n---\n\n${persona}\n`;
}

export function emit(config, { renderHeaders = null } = {}) {
  // An external server's headers go in as `${env:NAME}`, which Cursor expands
  // from its own environment when it loads mcp.json, so the token is never
  // written to the workspace volume. Rendering is all-or-nothing: a server
  // whose headers cannot all be rendered is left out (the helper warns), never
  // configured without auth to 401 unexplained. A base runtime without the
  // helper cannot honour headers at all; failing the seed says so.
  const mcpServer = (tool) => {
    if (!tool.headers) return { type: 'http', url: tool.endpoint };
    if (!renderHeaders) {
      throw new Error(`tool '${tool.name}' has headers, which need coding-runtime's ctx.renderHeaders; rebuild on a base that provides it`);
    }
    const headers = renderHeaders(tool.headers, {
      path: `tools.${tool.name}`,
      rewrite: (name) => `\${env:${name}}`,
      clientSyntax: /\$\{/,
    });
    return headers ? { type: 'http', url: tool.endpoint, headers } : null;
  };

  // Supplied on every run, null included: an explicit null removes the key, so
  // a withdrawn tool does not linger. Cursor treats a file that fails its
  // schema as having no servers at all, so only fields it validates are set.
  const servers = config.tools.map((tool) => [tool.name, mcpServer(tool)]).filter(([, server]) => server);
  const mcpServers = servers.length > 0 ? Object.fromEntries(servers) : null;

  return [
    {
      path: `${config.paths.home}/.cursor/mcp.json`,
      owns: ['mcpServers'],
      values: { mcpServers },
    },
    {
      path: `${config.paths.workspace}/.cursor/rules/${RULE_FILE}`,
      contents: personaRule(config.systemPrompt),
    },
  ];
}

export default emit;

// Serveur MCP local (stdio) lancé par Claude Desktop sur le mini PC.
// Outil unique « sql » : lance une ou plusieurs requêtes et renvoie les résultats.
// Connexion : variable PT_DB (rôle claude_rw, jamais postgres), localhost seulement.
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import pg from 'pg';

const MAX_LIGNES = 500;
const pool = new pg.Pool({
  connectionString: process.env.PT_DB,
  max: 2,
  statement_timeout: 60000,
  application_name: 'claude-mcp',
});

const server = new McpServer({ name: 'pixeltrade-sql', version: '1.0.0' });

server.registerTool(
  'sql',
  {
    title: 'SQL Pixel Trade',
    description:
      'Lance du SQL sur la base PostgreSQL 17 de Pixel Trade (serveur maison, schéma public). ' +
      'Plusieurs instructions possibles (séparées par ;) ; elles tournent dans une transaction : ' +
      'tout passe ou rien. Résultats limités à ' + MAX_LIGNES + ' lignes par requête.',
    inputSchema: { query: z.string().describe('Le SQL à lancer') },
  },
  async ({ query }) => {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const res = await client.query(query);
      await client.query('commit');
      const list = Array.isArray(res) ? res : [res];
      const out = list.map((r) => {
        const rows = r.rows ?? [];
        return {
          commande: r.command,
          lignes: r.rowCount,
          resultat: rows.slice(0, MAX_LIGNES),
          ...(rows.length > MAX_LIGNES ? { tronque: rows.length } : {}),
        };
      });
      return { content: [{ type: 'text', text: JSON.stringify(out.length === 1 ? out[0] : out, null, 1) }] };
    } catch (e) {
      await client.query('rollback').catch(() => {});
      return { isError: true, content: [{ type: 'text', text: 'ERREUR (rien n\'a été modifié) : ' + e.message }] };
    } finally {
      client.release();
    }
  }
);

await server.connect(new StdioServerTransport());

# Pages

Top-level page components (routed views).

## Pages to Build

| Page | Route | Purpose |
|------|-------|---------|
| `Lobby.tsx` | `/` | List of open tables, create new table button, join table flow |
| `Table.tsx` | `/table/:id` | Active poker table view for players. Shows hand, community cards, betting controls. |
| `Spectator.tsx` | `/spectator/:id` | Watch-only view of a table with wagering panel. No hole cards visible. |

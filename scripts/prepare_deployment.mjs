import { renameSync } from 'node:fs';

// Vercel serves physical index.html before rewrites. Keep the SPA entry named
// explicitly so '/' can select the public site or dashboard by hostname.
renameSync('dist/index.html', 'dist/dashboard.html');

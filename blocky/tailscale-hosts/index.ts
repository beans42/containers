import { Elysia } from 'elysia';
import { Database } from 'bun:sqlite';
import { copyFile, access, rm } from 'node:fs/promises';
import { constants as FS } from 'node:fs';
import ipaddr from 'ipaddr.js';

async function exists(path: string) {
	try {
		await access(path, FS.F_OK);
		return true;
	} catch {
		return false;
	}
}

const app = new Elysia()
	.onError(({ error, code }) => {
		if (code === 'NOT_FOUND')
			return 'not found :(';
		console.error(error);
	})
	.get('/hosts', async () => {
		await copyFile('/headscale/db.sqlite', '/db.sqlite');
	
		const SRC_WAL = '/headscale/db.sqlite-wal';
		if (await exists(SRC_WAL))
			await copyFile(SRC_WAL, '/db.sqlite-wal');
		else
			await rm('/db.sqlite-wal');
	
		const SRC_SHM = '/headscale/db.sqlite-shm';
		if (await exists(SRC_SHM))
			await copyFile(SRC_SHM, '/db.sqlite-shm');
		else
			await rm('/db.sqlite-shm');
	
		let db: Database | undefined;
		try {
			db = new Database('/db.sqlite', { readonly: true });
			db.run('PRAGMA query_only = ON;');
	
			let out = '';
			db.query('SELECT given_name, endpoints FROM nodes;')
				.all()
				.filter((x: any) => x.given_name !== 'headplane-agent' && x.given_name !== 'vps1')
				.forEach((x:any) => {
					let ipv4 = null, ipv6 = null;
					for (const raw_ip of JSON.parse(x.endpoints)) {
						const ip = raw_ip.startsWith('[') ? raw_ip.split(']')[0].slice(1) :
							raw_ip.split(':')[0]
						if (ipaddr.parse(ip).range() !== 'unicast')
							continue;
						
						if (ip.includes(':'))
							ipv6 = ipv6 ? ipv6 : ip;
						else
							ipv4 = ipv4 ? ipv4 : ip;
					}

					if (!ipv6) {
						out += `${ipv4} v4.${x.given_name}.ebra.dev\n`;
						out += `:: v4.${x.given_name}.ebra.dev\n`;
						out += `0.0.0.0 v6.${x.given_name}.ebra.dev\n`;
						out += `:: v6.${x.given_name}.ebra.dev\n`;
					} else if (!ipv4) {
						out += `0.0.0.0 v4.${x.given_name}.ebra.dev\n`;
						out += `:: v4.${x.given_name}.ebra.dev\n`;
						out += `0.0.0.0 v6.${x.given_name}.ebra.dev\n`;
						out += `${ipv6} v6.${x.given_name}.ebra.dev\n`;
					} else {
						out += `${ipv4} v4.${x.given_name}.ebra.dev\n`;
						out += `:: v4.${x.given_name}.ebra.dev\n`;
						out += `0.0.0.0 v6.${x.given_name}.ebra.dev\n`;
						out += `${ipv6} v6.${x.given_name}.ebra.dev\n`;
					}
				});
	
			return out;
		} finally {
			try {
				db?.close();
			} catch {}
		}
	})
	.listen(16932);

const stopApp = () => { app.stop(); process.exit(0); }
process.on('SIGINT', stopApp);
process.on('SIGTERM', stopApp);

export type App = typeof app;

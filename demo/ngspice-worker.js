// A dedicated worker that loads ngspice.wasm once, stages code models and spinit,
// and runs a single circuit per worker (app-style ngspice build).

const MODEL_FILES = [
	'analog.cm',
	'digital.cm',
	'spice2poly.cm',
	'table.cm',
	'tlines.cm',
	'xtradev.cm',
	'xtraevt.cm',
];

let stdoutLog = '';
let stderrLog = '';
let isInitialized = false;
let pendingNetlist = null;

const moduleReady = new Promise((resolve, reject) => {
	stdoutLog = '';
	stderrLog = '';

	self.Module = {
		noInitialRun: true,
		locateFile: (path) => (path.endsWith('.wasm') ? 'ngspice.wasm' : path),
		print: (text) => {
			stdoutLog += text + '\n';
			self.postMessage({ type: 'stdout', line: text });
		},
		printErr: (text) => {
			if (text.startsWith('fopen("/proc/meminfo"')) return; // Ignore expected /proc absence in WASM
			if (text.includes('keepRuntimeAlive() is set')) return; // Suppress keepRuntimeAlive warning from single-shot run
			stderrLog += text + '\n';
			self.postMessage({ type: 'stderr', line: text });
		},
		onRuntimeInitialized: () => {
			isInitialized = true;
			stageFilesystem().then(() => {
				if (pendingNetlist) {
					runSimulation(pendingNetlist);
					pendingNetlist = null;
				}
			});
			resolve();
		},
	};

	try {
		importScripts('ngspice.js');
	} catch (err) {
		reject(err);
	}
});

self.addEventListener('message', (event) => {
	const { type, netlist } = event.data || {};
	if (type !== 'run') return;

	if (isInitialized) {
		runSimulation(netlist);
	} else {
		pendingNetlist = netlist;
	}
});

async function runSimulation(netlist) {
	if (!netlist || !netlist.trim()) {
		self.postMessage({ type: 'error', message: 'Netlist is empty.' });
		return;
	}

	await moduleReady;
	self.postMessage({ type: 'status', message: 'Running simulation…' });

	try {
		FS.writeFile('/circuit.cir', netlist);
		try { FS.unlink('/output.txt'); } catch (_) {}
		invokeNgspice(['-b', '/circuit.cir']);
		self.postMessage({ type: 'done', exitCode: 0, stdout: stdoutLog, stderr: stderrLog });
	} catch (err) {
		self.postMessage({ type: 'error', message: err.message || String(err), stdout: stdoutLog, stderr: stderrLog });
	} finally {
		self.close();
	}
}

async function stageFilesystem() {
	ensurePath('/usr/local/lib/ngspice');
	ensurePath('/usr/local/share/ngspice/scripts');

	await Promise.all(MODEL_FILES.map(async (name) => {
		const data = await fetchBinary(`cm/${name}`);
		FS.writeFile(`/usr/local/lib/ngspice/${name}`, new Uint8Array(data));
	}));

	const spinitText = await fetchText('spinit');
    console.log(spinitText)
	FS.writeFile('/usr/local/share/ngspice/scripts/spinit', spinitText);
	FS.writeFile('/spinit', spinitText);
}

async function fetchBinary(path) {
	const response = await fetch(path);
	if (!response.ok) {
		throw new Error(`Failed to fetch ${path}: ${response.status} ${response.statusText}`);
	}
	return response.arrayBuffer();
}

async function fetchText(path) {
	const response = await fetch(path);
	if (!response.ok) {
		throw new Error(`Failed to fetch ${path}: ${response.status} ${response.statusText}`);
	}
	return response.text();
}

function ensurePath(path) {
	const parts = path.split('/').filter(Boolean);
	let current = '/';
	for (const part of parts) {
		FS.createPath(current, part, true, true);
		current = current === '/' ? `/${part}` : `${current}/${part}`;
	}
}

function invokeNgspice(args) {
	if (typeof callMain === 'function') return callMain(args);
	if (typeof Module !== 'undefined' && typeof Module.callMain === 'function') return Module.callMain(args);
	throw new Error('ngspice entrypoint callMain is not available in this build.');
}

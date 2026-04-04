export type AnalysisType =
	| 'tran'
	| 'ac'
	| 'dc'
	| 'op'
	| 'noise'
	| 'sens'
	| 'tf'
	| 'unknown';

export interface SweepInfo {
	name: string;
	unit: string;
	values: Float64Array;
}

export interface VectorInfo {
	name: string;
	unit: string;
	real: Float64Array;
	imag: Float64Array | null;
	complex: boolean;
}

export interface AnalysisMeta {
	plotName: string;
}

export interface NormalizedResult {
	type: AnalysisType;
	sweep: SweepInfo | null;
	vectors: VectorInfo[];
	scalars: Record<string, number> | null;
	meta: AnalysisMeta;
}

export interface SimulationCallbacks {
	onProgress?: (data: {
		progress: number;
		currentTime: number;
		finalTime: number;
	}) => void;
	onStdout?: (line: string) => void;
	onStderr?: (line: string) => void;
	onStatus?: (message: string) => void;
	onDebug?: (data: unknown) => void;
}

export interface SimulationResult {
	exitCode: number;
	finalTime: number | null;
	progress: number;
	stdout: string;
	stderr: string;
	analyses: NormalizedResult[];
}

export function runSimulation(
	netlist: string,
	callbacks?: SimulationCallbacks,
	options?: { workerUrl?: string; assetBaseUrl?: string },
): Promise<SimulationResult>;

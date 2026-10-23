import ts from 'typescript';
import path from 'node:path';

const root = process.cwd();
const declarations = path.join(root, 'supabase/functions/_shared/__deno_test_ambient.d.ts');
const canonical = file => path.resolve(file).replaceAll('\\', '/');
const isAmbient = file => canonical(file) === canonical(declarations);
const ambient = 'declare namespace Deno { const env: {get(name:string):string|undefined}; function serve(handler:(request:Request)=>Response|Promise<Response>):void; }';
const options = {
  strict: true, noEmit: true, skipLibCheck: true,
  target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext,
  moduleResolution: ts.ModuleResolutionKind.Bundler,
  allowImportingTsExtensions: true,
  lib: ['lib.es2022.d.ts', 'lib.dom.d.ts', 'lib.dom.iterable.d.ts'],
};
const host = ts.createCompilerHost(options);
const originalRead = host.readFile.bind(host);
const originalExists = host.fileExists.bind(host);
const originalSource = host.getSourceFile.bind(host);
host.readFile = file => isAmbient(file) ? ambient : originalRead(file);
host.fileExists = file => isAmbient(file) || originalExists(file);
host.getSourceFile = (file, version, ...args) => isAmbient(file)
  ? ts.createSourceFile(file, ambient, version, true)
  : originalSource(file, version, ...args);
host.resolveModuleNames = (names, file) => names.map(name => ts.resolveModuleName(
  name === 'npm:@supabase/supabase-js@2.118.0' ? '@supabase/supabase-js' : name,
  file, options, host,
).resolvedModule);
const program = ts.createProgram([
  'supabase/functions/assinatura-checkout/index.ts',
  'supabase/functions/assinatura-webhook/index.ts', declarations,
], options, host);
const diagnostics = ts.getPreEmitDiagnostics(program);
if (diagnostics.length) {
  console.error(ts.formatDiagnosticsWithColorAndContext(diagnostics, {
    getCanonicalFileName: file => file,
    getCurrentDirectory: () => root,
    getNewLine: () => String.fromCharCode(10),
  }));
  process.exitCode = 1;
} else {
  console.log('PASS: subscription edge handlers and Supabase adapter type-check; no dependencies installed.');
}
